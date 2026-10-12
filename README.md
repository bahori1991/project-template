# sample — Docker 開発環境

このリポジトリは、フロントエンド・バックエンド・PostgreSQL を Docker Compose で動かすための開発用セットアップです。アプリケーションはリポジトリ直下の `frontend/` と `backend/` をコンテナにマウントして編集します。

- **frontend/** — [TanStack Start](https://tanstack.com/start) + [Vite+](https://vite.plus)（pnpm）。clone 時点で雛形が含まれます。
- **backend/** — ASP.NET Core を置く想定（プロジェクトは各自で配置。ホストから DB に接続する例は `backend/.env.example`）。

## リポジトリ構成

```
sample/
├── frontend/              # フロントエンド（コンテナの /app にマウント）
├── backend/               # バックエンド（コンテナの /app にマウント）
├── compose.yaml           # Compose 定義（dotfiles / Neovim データのマウント含む）
├── base.Dockerfile        # 共通開発ベース（build-only・entrypoint 同梱）
├── frontend.Dockerfile
├── backend.Dockerfile
├── entrypoint.sh          # 起動時に dotfiles があれば symlink.sh を実行
├── symlink.sh             # dotfiles → $HOME へのシンボリックリンク
├── dev.sh                 # 入力ハッシュ付きビルド → compose up → tmux 開発レイアウト
├── .env.example           # ルート `.env` のテンプレート（git 管理）
├── .env                   # 実際に使う設定（git 管理外。自分で作成）
└── .lazysql.toml          # ホストから DB に接続する LazySQL 用（任意・git 管理外）
```

ビルド定義はリポジトリ直下の `*.Dockerfile` です。Compose からそのままビルドします。

## サービス構成

| サービス | 説明 | ホストポート |
|----------|------|--------------|
| `frontend` | 共通ベース + Vite+（Node / pnpm） | 3000 |
| `backend` | 共通ベース + .NET SDK 10 | 8080 |
| `db` | PostgreSQL 18 (bookworm) | 5432 |
| `base` | Ubuntu 24.04 開発ベース（Neovim / eza / tree-sitter CLI 等・ビルド専用・`dev:base`） | — |

`frontend` と `backend` は Compose で `user: "${UID}:${GID}"` と `userns_mode: keep-id` を指定し、ホストのユーザー ID と揃えた状態で動かします。bind mount したソースに作成したファイルの所有者がホスト側と一致しやすくなります。

共通ベース **`base`** には、開発用 CLI（Neovim・eza・tree-sitter CLI など）が含まれます。バージョンは `.env` の `NVIM_VERSION` / `EZA_VERSION` / `TREE_SITTER_CLI_VERSION` で指定します（`base` ビルド時）。`frontend` / `backend` は `.env` の `DEV_BASE_IMAGE`（既定 `dev:base`）を前提にビルドし、ベースの [entrypoint.sh](entrypoint.sh) を継承します。

## 前提条件

- [Docker Engine](https://docs.docker.com/engine/install/) と [Docker Compose V2](https://docs.docker.com/compose/install/)（`docker compose` サブコマンド）。rootless / Podman など `userns_mode: keep-id` をサポートする環境を想定しています。
- マウント元パスを `.env` の `FRONTEND_HOST` / `BACKEND_HOST` に設定できること（通常はこのリポジトリ内の `frontend` / `backend` の絶対パス）
- （推奨）ホスト上の dotfiles を `DOTFILES_HOST` で指定し、[compose.yaml](compose.yaml) からコンテナにマウントすること（未マウントでも起動は可能。後述）
- （任意）[dev.sh](dev.sh) を使う場合: `jq` / `tmux` / Cursor CLI（`cursor` コマンド）
- （任意）コンテナ内から Git over SSH を使う場合は、compose に `~/.ssh` マウント等を自分で追加する必要があります（デフォルトの Compose 定義には含まれません）

## 初回セットアップ

### 1. 環境変数

リポジトリ直下で `.env` を用意します。テンプレートをコピーして値を編集してください。

```bash
cp .env.example .env
```

主な変数（[`.env.example`](.env.example) 参照）:

| 変数 | 説明 |
|------|------|
| `PROJECT_NAME` | Compose プロジェクト名（DB ボリューム名 `${PROJECT_NAME}_pg_db` にも使用） |
| `DEV_BASE_IMAGE` | ベースイメージのタグ（`dev:base`） |
| `UID` / `GID` | ホストと同じユーザー / グループ ID（`id -u` / `id -g`）。`frontend` / `backend` の実行ユーザーとベースイメージビルド時の ID |
| `USERNAME` | コンテナ内の Linux ユーザー名 |
| `FRONTEND_HOST` / `BACKEND_HOST` | ホスト側のフロント / バックエンドディレクトリの絶対パス |
| `DOTFILES_HOST` | ホスト側 dotfiles の絶対パス（コンテナ内 `~/.config/dotfiles` に read-only マウント） |
| `NVIM_VERSION` / `EZA_VERSION` / `TREE_SITTER_CLI_VERSION` | `base` ビルド時に使うツールのバージョン |

`frontend` / `backend` サービスはルートの `.env` を `env_file` として読み込みます。アプリ固有の変数があれば同じ `.env` に追記するか、各ディレクトリの `.env.example` を参考にしてください。

DB 接続は **バックエンド（コンテナ内）のみ** を想定しており、接続文字列は [compose.yaml](compose.yaml) の `ConnectionStrings__PostgreSql` で渡します（ルート `.env` に `DATABASE_URL` 等は不要です）。

### 2. ベースイメージのビルド

`frontend` と `backend` は `DEV_BASE_IMAGE` を前提としています。先にベースをビルドします（`build-only` プロファイル）。

```bash
docker compose --profile build-only build base
```

[dev.sh](dev.sh) を使う場合は、Dockerfile / `entrypoint.sh` / `symlink.sh` などの入力ハッシュを比較し、変更があれば base → frontend / backend を順にビルドします。

### 3. サービスの起動

```bash
docker compose up -d --build
```

または一括で開発用 tmux レイアウトまで開く:

```bash
./dev.sh
```

`dev.sh --no-cache` でイメージをキャッシュなしビルドできます。`db` のヘルスチェックが通るまで待ってから `backend` が起動します。

### 4. フロントエンドの依存関係（初回）

コンテナ内で pnpm を実行する想定です。

```bash
docker compose exec frontend bash -lc 'cd /app && pnpm install'
```

## 日常的な操作

いずれも **リポジトリ直下** で実行してください。

```bash
# 起動
docker compose up -d

# dev.sh: 差分ビルド + 起動 + tmux（frontend/backend の nvim・シェル・agent ペイン等）
./dev.sh

# 停止
docker compose down

# 停止（DB ボリュームも削除）
docker compose down -v

# ログ
docker compose logs -f
docker compose logs -f backend

# イメージの再ビルド
docker compose build
docker compose up -d --build

# コンテナに入る（対話シェル）
docker compose exec frontend bash
docker compose exec backend bash
```

各アプリコンテナのデフォルト CMD は `sleep infinity` です。起動時に entrypoint が dotfiles のシンボリックリンク処理を行ったあと、この CMD が実行されます。開発サーバーや `dotnet run` はコンテナ内で手動実行する想定です。

### 例: 開発サーバー

```bash
# フロントエンド（Vite+ / TanStack Start）
docker compose exec frontend bash -lc 'cd /app && pnpm dev'

# バックエンド
docker compose exec backend bash -lc 'cd /app && dotnet run'
```

フロントエンドから API を呼ぶときの URL は、ホストのブラウザからなら `http://localhost:8080`、コンテナ内からなら `http://backend:8080` など環境に合わせて設定してください。

## データベース

アプリから PostgreSQL に触るのは **バックエンドのみ** です。フロントエンドは API 経由とし、DB 用の環境変数は Compose / ルート `.env` では用意しません。

Compose の `db` サービスは次の固定値で起動します（[compose.yaml](compose.yaml)）。

| 項目 | 値 |
|------|-----|
| コンテナ内から（.NET・`backend`） | `Host=db;Port=5432;Database=db;Username=user;Password=password` |
| ホストから（`backend/.env.example` 等） | `Host=localhost;Port=5432;…` |
| データ永続化 | Docker ボリューム `${PROJECT_NAME}_pg_db` |

`backend` では上記が環境変数 `ConnectionStrings__PostgreSql` として注入されます。ASP.NET Core では `GetConnectionString("PostgreSql")` で参照できます。

EF Core のマイグレーションなども **`backend` コンテナ内** で実行する想定です（`Host=db` のまま使えます）。

```bash
docker compose exec backend bash -lc 'cd /app && dotnet ef database update'
```

（プロジェクトに EF ツールを入れている場合。コマンドはプロジェクトに合わせて読み替えてください。）

`db` の認証情報を変える場合は、compose の `db` サービスと `backend` の `ConnectionStrings__PostgreSql` を**両方**揃えて変更してください。

### LazySQL（任意・ホスト）

DB を直接覗く必要があるときだけ、ホストから [LazySQL](https://github.com/jorgerojas26/lazysql) を使えます。**リポジトリ直下**に `.lazysql.toml` を置きます（`.gitignore` 対象）。接続先は公開ポート `localhost:5432` です。`dev.sh` はホスト tmux に LazySQL 用ウィンドウも開きます。

```toml
[[database]]
Name = "sample (compose db)"
Provider = "postgres"
URL = "postgres://user:password@localhost:5432/db?sslmode=disable"
DBName = "db"
Schemas = ["public"]
ReadOnly = false
```

## ボリュームとマウント

[compose.yaml](compose.yaml) の主なマウント（`frontend` / `backend` 共通）:

- `${FRONTEND_HOST}` または `${BACKEND_HOST}` → `/app`
- ホストの dotfiles（`DOTFILES_HOST`）→ `/home/${USERNAME}/.config/dotfiles`（read-only）
- ホストの `~/.local/state` → コンテナ内の同パス
- ホストの `~/.local/share/nvim` → コンテナ内の同パス（Neovim のデータ・ログ等）
- Mason パッケージ用 named volume → `/home/${USERNAME}/.local/share/nvim/mason`（ボリューム名 `${PROJECT_NAME}_mason_share`）

アプリコンテナは `user: "${UID}:${GID}"` のため、`.env` の `UID` / `GID` をホストと揃えてから起動してください。

環境変数 `XDG_CONFIG_HOME` / `XDG_CACHE_HOME` は `/home/${USERNAME}/.config` と `/home/${USERNAME}/.cache` に設定されています。

### dotfiles とシンボリックリンク（起動時）

ベースイメージの [entrypoint.sh](entrypoint.sh) は、`frontend` / `backend` コンテナ起動時に次を行います。

1. `~/.config/dotfiles` が存在すれば [symlink.sh](symlink.sh) を実行
2. 存在しなければスキップ（メッセージは stderr）
3. 元の CMD（`sleep infinity`）を `exec`

[symlink.sh](symlink.sh) は dotfiles 内の設定へ `$HOME` 側からシンボリックリンクを張ります（現状: `~/.bashrc` / `~/.bash_logout` / `~/.profile`、`~/.config/nvim` → `dotfiles/nvim`）。リンク元パスが無い場合は警告を出しますが、コンテナの起動は続行します。dotfiles を更新したあとリンク定義を変えた場合は、イメージの再ビルドまたはコンテナの再作成で entrypoint を再度走らせてください。

## トラブルシューティング

**`DEV_BASE_IMAGE` が見つからない / frontend・backend のビルドが失敗する**

→ `docker compose --profile build-only build base` を実行し、`DEV_BASE_IMAGE` のタグが `.env` と一致しているか確認してください。`./dev.sh` でも base のビルド入力ハッシュを見て自動ビルドします。

**ポートが既に使用中**

→ ホストで 3000 / 8080 / 5432 を使っているプロセスを止めるか、[compose.yaml](compose.yaml) の `ports` を変更してください。

**権限エラー（作成ファイルの所有者）**

→ `.env` の `UID` / `GID` がホストの `id -u` / `id -g` と一致しているか確認し、変更した場合はベースとアプリイメージを再ビルドしてから再起動してください。

```bash
docker compose --profile build-only build --no-cache base
docker compose build --no-cache
docker compose up -d
```

**マウント先が空 / 別ディレクトリを指している**

→ `FRONTEND_HOST` / `BACKEND_HOST` / `DOTFILES_HOST` が意図した絶対パスか確認してください。

**コンテナ内で bash / nvim 設定が効かない**

→ `docker compose exec frontend bash -lc 'ls -la ~/.bashrc ~/.config/nvim'` でシンボリックリンクを確認。dotfiles がマウントされていない、または `symlink.sh` 実行前に作られたコンテナの場合は `docker compose up -d --force-recreate frontend backend` で再起動してください。

**`docker compose` が見つからない**

→ Docker Desktop または Docker Engine + Compose プラグインをインストールしてください。[Install Docker Compose](https://docs.docker.com/compose/install/) を参照。

## 参考

- Compose 定義: [compose.yaml](compose.yaml)
- 環境変数テンプレート: [.env.example](.env.example)
- Docker: [Install Docker Engine](https://docs.docker.com/engine/install/)
