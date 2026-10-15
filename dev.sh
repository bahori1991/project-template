#!/usr/bin/env bash
# ビルド入力ハッシュに応じたビルド → compose 起動 → tmux で frontend/backend 開発環境を開く
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

NO_CACHE=false
for arg in "$@"; do
  case "$arg" in
    --no-cache) NO_CACHE=true ;;
    *)
      echo "dev.sh: unknown argument: $arg" >&2
      exit 1
      ;;
  esac
done

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "dev.sh: required command not found: $1" >&2
    exit 1
  fi
}

require_nonempty() {
  local name=$1
  local value=$2
  if [[ -z "${value// /}" ]]; then
    echo "dev.sh: $name must be set in .env" >&2
    exit 1
  fi
}

# --- 前提: 必要コマンドと .env ---
require_cmd docker
require_cmd jq
require_cmd tmux
require_cmd cursor

if [[ ! -f "$ROOT/.env" ]]; then
  echo "dev.sh: .env not found. Copy .env.example to .env and configure it." >&2
  exit 1
fi

# .envのKEY=VALUEを1行読む
read_env_var() {
  local key=$1
  local file=$2
  local line value
  line=$(grep -E "^${key}=" "$file" | tail -n 1) || true
  [[ -n "$line" ]] || return 1
  value=${line#*=}
  value=${value#\"}; value=${value%\"}
  value=${value#\'}; value=${value%\'}
  printf '%s' "$value"
}

# .envから値を取得
PROJECT_NAME=$(read_env_var PROJECT_NAME "$ROOT/.env") || true
FRONTEND_HOST=$(read_env_var FRONTEND_HOST "$ROOT/.env") || true
BACKEND_HOST=$(read_env_var BACKEND_HOST "$ROOT/.env") || true
DEV_BASE_IMAGE=$(read_env_var DEV_BASE_IMAGE "$ROOT/.env") || DEV_BASE_IMAGE=dev:base

image_exists() {
  docker image inspect "$1" >/dev/null 2>&1
}

compose_built_image_tag() {
  local service=$1
  printf '%s-%s' "$PROJECT_NAME" "$service"
}

require_nonempty PROJECT_NAME "$PROJECT_NAME"
require_nonempty FRONTEND_HOST "$FRONTEND_HOST"
require_nonempty BACKEND_HOST "$BACKEND_HOST"

# --- 1. ビルド入力ハッシュとイメージラベルの比較 ---
BUILD_INPUT_LABEL='dev.sample.build-input-hash'
BUILD_HASH_ALG=1
export DEV_SAMPLE_BUILD_HASH_BASE="${DEV_SAMPLE_BUILD_HASH_BASE-}"
export DEV_SAMPLE_BUILD_HASH_FRONTEND="${DEV_SAMPLE_BUILD_HASH_FRONTEND-}"
export DEV_SAMPLE_BUILD_HASH_BACKEND="${DEV_SAMPLE_BUILD_HASH_BACKEND-}"

sha256_lines() {
  sha256sum | awk '{print $1}'
}

compose_service_build_json() {
  local service=$1
  local profile_args=()
  if [[ "$service" == base ]]; then
    profile_args=(--profile build-only)
  fi
  docker compose "${profile_args[@]}" config --format json \
    | jq -c ".services[\"${service}\"].build // empty"
}

base_image_id_or_empty() {
  if image_exists "$DEV_BASE_IMAGE"; then
    docker image inspect "$DEV_BASE_IMAGE" --format '{{.Id}}'
  else
    printf 'missing'
  fi
}

image_build_input_hash() {
  local ref=$1
  docker image inspect "$ref" --format "{{index .Config.Labels \"${BUILD_INPUT_LABEL}\"}}" 2>/dev/null \
    | grep -v '^$' || true
}

compute_base_input_hash() {
  local build_json
  build_json=$(compose_service_build_json base)
  {
    printf 'alg=%s\n' "$BUILD_HASH_ALG"
    printf 'service=base\n'
    cat "$ROOT/base.Dockerfile"
    cat "$ROOT/entrypoint.sh"
    cat "$ROOT/symlink.sh"
    printf 'build=%s\n' "$build_json"
  } | sha256_lines
}

compute_app_input_hash() {
  local service=$1
  local dockerfile=$2
  local build_json base_id
  build_json=$(compose_service_build_json "$service")
  base_id=$(base_image_id_or_empty)
  {
    printf 'alg=%s\n' "$BUILD_HASH_ALG"
    printf 'service=%s\n' "$service"
    cat "$ROOT/$dockerfile"
    printf 'BASE_IMAGE_ID=%s\n' "$base_id"
    printf 'build=%s\n' "$build_json"
  } | sha256_lines
}

service_needs_build() {
  local image_ref=$1
  local expected_hash=$2
  if ! image_exists "$image_ref"; then
    return 0
  fi
  local current
  current=$(image_build_input_hash "$image_ref")
  [[ "$current" != "$expected_hash" ]]
}

verify_image_build_label() {
  local ref=$1
  local expected=$2
  local got
  got=$(image_build_input_hash "$ref")
  if [[ "$got" != "$expected" ]]; then
    echo "dev.sh: after build, ${BUILD_INPUT_LABEL} mismatch for $ref" >&2
    echo "dev.sh:   expected=$expected" >&2
    echo "dev.sh:   got=${got:-<empty>}" >&2
    return 1
  fi
}

[[ "${DEV_BUILD_NO_CACHE:-}" == 1 ]] && NO_CACHE=true

build_extra_args=()
[[ "$NO_CACHE" == true ]] && build_extra_args+=(--no-cache)

want_base=false
want_frontend=false
want_backend=false

hash_base=$(compute_base_input_hash)
if service_needs_build "$DEV_BASE_IMAGE" "$hash_base"; then
  want_base=true
fi

hash_frontend=$(compute_app_input_hash frontend frontend.Dockerfile)
hash_backend=$(compute_app_input_hash backend backend.Dockerfile)

if [[ "$want_base" == true ]]; then
  want_frontend=true
  want_backend=true
else
  if service_needs_build "$(compose_built_image_tag frontend)" "$hash_frontend"; then
    want_frontend=true
  fi
  if service_needs_build "$(compose_built_image_tag backend)" "$hash_backend"; then
    want_backend=true
  fi
fi

# --- 1. 条件付き docker compose build ---
if [[ "$want_base" == true || "$want_frontend" == true || "$want_backend" == true ]]; then
  if [[ "$want_base" == true ]]; then
    export DEV_SAMPLE_BUILD_HASH_BASE="$hash_base"
    if [[ "$NO_CACHE" == true ]]; then
      echo "dev.sh: building base (--no-cache, input ${hash_base:0:12}...)..."
    else
      echo "dev.sh: building base (input ${hash_base:0:12}...)..."
    fi
    docker compose --profile build-only build "${build_extra_args[@]}" base
    verify_image_build_label "$DEV_BASE_IMAGE" "$hash_base"
    hash_frontend=$(compute_app_input_hash frontend frontend.Dockerfile)
    hash_backend=$(compute_app_input_hash backend backend.Dockerfile)
    want_frontend=true
    want_backend=true
  fi

  if [[ "$want_frontend" == true ]]; then
    export DEV_SAMPLE_BUILD_HASH_FRONTEND="$hash_frontend"
    if [[ "$NO_CACHE" == true ]]; then
      echo "dev.sh: building frontend (--no-cache, input ${hash_frontend:0:12}...)..."
    else
      echo "dev.sh: building frontend (input ${hash_frontend:0:12}...)..."
    fi
    docker compose build "${build_extra_args[@]}" frontend
    verify_image_build_label "$(compose_built_image_tag frontend)" "$hash_frontend"
  fi

  if [[ "$want_backend" == true ]]; then
    export DEV_SAMPLE_BUILD_HASH_BACKEND="$hash_backend"
    if [[ "$NO_CACHE" == true ]]; then
      echo "dev.sh: building backend (--no-cache, input ${hash_backend:0:12}...)..."
    else
      echo "dev.sh: building backend (input ${hash_backend:0:12}...)..."
    fi
    docker compose build "${build_extra_args[@]}" backend
    verify_image_build_label "$(compose_built_image_tag backend)" "$hash_backend"
  fi
  RAN_BUILD=true
else
  echo "dev.sh: skipping build (images match build inputs)"
  RAN_BUILD=false
fi

# --- 2. コンテナ起動（未起動時だけ up) ---
compose_services_running() {
  local svc
  for svc in db frontend backend; do
    if [[ -z $(docker compose ps -q --status running "$svc" 2>/dev/null) ]]; then
      return 1
    fi
  done
  return 0
}

if compose_services_running && [[ "$RAN_BUILD" != true ]]; then
  echo "dev.sh: db/frontend/backend already running; skipping compose up"
else
  echo "dev.sh: starting services..."
  docker compose up -d --wait
fi

# tmux: 右列 claude の幅、左列 nvim 上段の高さ（%）
CLAUDE_PANE_PERCENT=35
NVIM_PANE_PERCENT=35

read_pane_indices() {
  PANE_BASE=$(tmux show-option -t "$PROJECT_NAME" -v pane-base-index 2>/dev/null || true)
  if [[ -z "${PANE_BASE:-}" ]]; then
    PANE_BASE=1
  fi
  NVIM_PANE=$((PANE_BASE))
  TERM_PANE=$((PANE_BASE + 1))
  CLAUDE_PANE=$((PANE_BASE + 2))
}

read_term_dimensions() {
  if [[ -n "${TMUX:-}" ]]; then
    TERM_COLS=$(tmux display-message -p '#{client_width}')
    TERM_LINES=$(tmux display-message -p '#{client_height}')
  else
    TERM_COLS=$(tput cols)
    TERM_LINES=$(tput lines)
  fi
  (( TERM_COLS >= 20 )) || TERM_COLS=80
  (( TERM_LINES >= 5 )) || TERM_LINES=24
}


# --- 3〜5. tmux: サービスごとにウインドウと 3 ペイン（nvim / terminal / claude）---
setup_service_window() {
  local win_name=$1
  local service=$2
  local host_path=$3
  local win_target="${PROJECT_NAME}:${win_name}"
  read_term_dimensions

  # セッション初回は frontend ウインドウで new-session、以降は new-window
  if [[ "$win_name" == "frontend" ]]; then
    tmux new-session -d -s "$PROJECT_NAME" -n "$win_name" -c "$ROOT" \
      -x "$TERM_COLS" -y "$TERM_LINES"
    tmux set-environment -g DEV_COMPOSE_ROOT "$ROOT"
    read_pane_indices
  else
    tmux new-window -t "$PROJECT_NAME" -n "$win_name" -c "$ROOT"
  fi

  # 先に横分割 → 右ペインが claude 列（ウインドウ全高）。続けて左列だけ縦分割
  tmux resize-window -t "$win_target" -x "$TERM_COLS" -y "$TERM_LINES"
  tmux split-window -h -t "$win_target" -p "$CLAUDE_PANE_PERCENT"
  tmux select-pane -t "${win_target}.${NVIM_PANE}"
  tmux split-window -v -t "${win_target}.${NVIM_PANE}" -p "$NVIM_PANE_PERCENT"

  # service_idの取得 (docker直叩きに必要)
  local service_id
  service_id="$(docker compose ps -q "$service")"
  if [[ -z "$service_id" ]]; then
    echo "dev.sh: no running container for service: $service" >&2
    exit 1
  fi

  # 左上 nvim、左下 terminal、右 claude（split 順による index）
  local nvim_cmd="docker exec --detach-keys='' -it -u "${UID}:$(id -g)" -w /app ${service_id} bash -lc 'nvim'"
  local term_cmd="docker exec --detach-keys='' -it -u "${UID}:$(id -g)" -w /app ${service_id} bash"
  local claude_cmd="cd $(printf '%q' "$host_path") && claude"

  tmux send-keys -t "${win_target}.${NVIM_PANE}" "$nvim_cmd" C-m
  tmux send-keys -t "${win_target}.${TERM_PANE}" "$term_cmd" C-m
  tmux send-keys -t "${win_target}.${CLAUDE_PANE}" "$claude_cmd" C-m
  
  tmux select-pane -t "${win_target}.${NVIM_PANE}"
}

setup_host_tool_window() {
  local win_name=$1
  local cmd=$2
  local work_dir=${3:-$ROOT}
  local win_target="${PROJECT_NAME}:${win_name}"
  tmux new-window -t "$PROJECT_NAME" -n "$win_name" -c "$work_dir"
  tmux send-keys -t "$win_target" "$cmd" C-m
}

attach_or_switch_session() {
  if [[ -n "${TMUX:-}" ]]; then
    tmux switch-client -t "$PROJECT_NAME"
    exit 0
  else
    exec tmux attach -t "$PROJECT_NAME"
  fi
}


# 同名セッションが既にある場合はペインを作らず attach のみ（ビルド・起動は上で済み）
if tmux has-session -t "$PROJECT_NAME" 2>/dev/null; then
  tmux set-environment -g DEV_COMPOSE_ROOT "$ROOT"
  echo "dev.sh: tmux session '$PROJECT_NAME' already exists; attaching."
  read_pane_indices
  tmux select-window -t "${PROJECT_NAME}:frontend" || true
  tmux select-pane -t "${PROJECT_NAME}:frontend.${NVIM_PANE}" || true
  attach_or_switch_session
fi

setup_service_window frontend frontend "$FRONTEND_HOST"
setup_service_window backend backend "$BACKEND_HOST"

setup_host_tool_window sql "lazysql"
setup_host_tool_window docker "lazydocker"
setup_host_tool_window git-frontend "lazygit" "$FRONTEND_HOST"
setup_host_tool_window git-backend "lazygit" "$BACKEND_HOST"

tmux select-window -t "${PROJECT_NAME}:frontend"
tmux select-pane -t "${PROJECT_NAME}:frontend.${NVIM_PANE}"

attach_or_switch_session
