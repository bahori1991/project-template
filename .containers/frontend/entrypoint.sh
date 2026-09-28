#!/usr/bin/env bash
set -euo pipefail

MARKER="${HOME}/.cache/container-init.done"

run_init() {
  set +eu
  if [ -f "$HOME/.config/dotfiles/scripts/symlink.sh" ]; then
    source "$HOME/.config/dotfiles/scripts/symlink.sh"
  fi
  set -eu
}

if [ ! -f "$MARKER" ]; then
  run_init
  mkdir -p "$(dirname "$MARKER")"
  touch "$MARKER"
fi
exec "$@"
