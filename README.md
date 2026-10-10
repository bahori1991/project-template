# sample — Docker 開発環境

このリポジトリは、フロントエンド・バックエンド・PostgreSQL を Docker Compose で動かすための開発用セットアップです。アプリケーションはリポジトリ直下の `frontend/` と `backend/` をコンテナにマウントして編集します。

- **frontend/** — [TanStack Start](https://tanstack.com/start) + [Vite+](https://vite.plus)（pnpm）。clone 時点で雛形が含まれます。
- **backend/** — ASP.NET Core を置く想定（プロジェクトは各自で配置。接続設定の例は `backend/.env.example`）。

## リポジトリ構成

```
sample/
├── frontend/              # フロントエンド（コンテナの /app にマウント）
├── backend/               # バックエンド（コンテナの /app にマウント）
├── compose.yaml           # メインの Compose 定義
├── compose.personal.yaml  # dotfiles / Neovim 用の上書き（任意）
├── base.Dockerfile        # 共通開発ベース（build-only・最小構成）
├── base.nvim.Dockerfile   # Neovim 等を含む開発ベース（build-only）
├── frontend.Dockerfile
├── backend.Dockerfile
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
| `base` | Ubuntu 24.04 共通開発ベース（ビルド専用・`dev:base`） | — |
| `base-nvim` | 上記 + Neovim / eza / tree-sitter CLI（ビルド専用・`dev:nvim`） | — |

`frontend` と `backend` は Compose で `user: "${UID}:${GID}"` を指定し、ホストのユーザー ID と揃えた状態で動かします。bind mount したソースに作成したファイルの所有者がホスト側と一致しやすくなります。

ベースイメージは **`base`**（最小）と **`base-nvim`**（エディタ付き）の二つから選びます。`base-nvim` では Neovim・eza・tree-sitter CLI などが入ります。バージョンは `.env` の `NVIM_VERSION` / `EZA_VERSION` / `TREE_SITTER_CLI_VERSION` で指定します（`base-nvim` ビルド時のみ）。

## 前提条件

- [Docker Engine](https://docs.docker.com/engine/install/) と [Docker Compose V2](https://docs.docker.com/compose/install/)（`docker compose` サブコマンド）
- マウント元パスを `.env` の `FRONTEND_HOST` / `BACKEND_HOST` に設定できること（通常はこのリポジトリ内の `frontend` / `backend` の絶対パス）
- （任意）`compose.personal.yaml` を使う場合、ホスト上に dotfiles が `DOTFILES_HOST` で指定したパスに存在すること
- （任意）コンテナ内から Git over SSH を使う場合は、ホストの `~/.ssh` と `SSH_AUTH_SOCK` の設定

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
| `DEV_BASE_IMAGE` | ベースイメージのタグ（`dev:base` または `dev:nvim`） |
| `UID` / `GID` | ホストと同じユーザー / グループ ID（`id -u` / `id -g`）。`frontend` / `backend` の実行ユーザーとベースイメージビルド時の ID |
| `USERNAME` | コンテナ内の Linux ユーザー名 |
| `FRONTEND_HOST` / `BACKEND_HOST` | ホスト側のフロント / バックエンドディレクトリの絶対パス |
| `DOTFILES_HOST` | （任意）ホスト側 dotfiles の絶対パス — `compose.personal.yaml` 利用時 |
| `NVIM_VERSION` / `EZA_VERSION` / `TREE_SITTER_CLI_VERSION` | `base-nvim` ビルド時に使うツールのバージョン |

`frontend` / `backend` サービスはルートの `.env` を `env_file` として読み込みます。アプリ固有の変数があれば同じ `.env` に追記するか、各ディレクトリの `.env.example` を参考にしてください。

DB 接続は **バックエンド（コンテナ内）のみ** を想定しており、接続文字列は [compose.yaml](compose.yaml) の `ConnectionStrings__PostgreSql` で渡します（ルート `.env` に `DATABASE_URL` 等は不要です）。

### 2. ベースイメージのビルド

`frontend` と `backend` は `DEV_BASE_IMAGE` を前提としています。先にベースをビルドします（`build-only` プロファイル）。

最小構成:

```bash
docker compose --profile build-only build base
```

Neovim 付きベースを使う場合（`.env` で `DEV_BASE_IMAGE=dev:nvim` にしたうえで）:

```bash
docker compose --profile build-only build base-nvim
```

### 3. サービスの起動

```bash
docker compose up -d --build
```

dotfiles / Neovim のマウントも使う場合は、個人用 Compose を重ねて起動します。

```bash
docker compose -f compose.yaml -f compose.personal.yaml up -d --build
```

`db` のヘルスチェックが通るまで待ってから `backend` が起動します。

### 4. フロントエンドの依存関係（初回）

コンテナ内で pnpm を実行する想定です。

```bash
docker compose exec frontend bash -lc 'cd /app && pnpm install'
```

## 日常的な操作

いずれも **リポジトリ直下** で実行してください（個人用オーバーレイを常に使う場合は `-f compose.yaml -f compose.personal.yaml` を付けてください）。

```bash
# 起動
docker compose up -d

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

各アプリコンテナのデフォルト CMD は `sleep infinity` です。開発サーバーや `dotnet run` はコンテナ内で手動実行する想定です。

### 例: 開発サーバー

```bash
# フロントエンド（Vite+ / TanStack Start）
docker compose exec frontend bash -lc 'cd /app && pnpm dev'

# バックエンド
docker compose exec backend bash -lc 'cd /app && dotnet run'
```

フロントエンドから API を呼ぶときの URL は、ホストのブラウザからなら `http://localhost:8080`、コンテナ内からなら `http://backend:8080` など環境に合わせて設定してください（`frontend/.env.example` 参照）。

## データベース

アプリから PostgreSQL に触るのは **バックエンドのみ** です。フロントエンドは API 経由とし、DB 用の環境変数は Compose / ルート `.env` では用意しません。

Compose の `db` サービスは次の固定値で起動します（[compose.yaml](compose.yaml)）。

| 項目 | 値 |
|------|-----|
| コンテナ内から（.NET・`backend`） | `Host=db;Port=5432;Database=db;Username=user;Password=password` |
| データ永続化 | Docker ボリューム `${PROJECT_NAME}_pg_db` |

`backend` では上記が環境変数 `ConnectionStrings__PostgreSql` として注入されます。ASP.NET Core では `GetConnectionString("PostgreSql")` で参照できます。

EF Core のマイグレーションなども **`backend` コンテナ内** で実行する想定です（`Host=db` のまま使えます）。

```bash
docker compose exec backend bash -lc 'cd /app && dotnet ef database update'
```

（プロジェクトに EF ツールを入れている場合。コマンドはプロジェクトに合わせて読み替えてください。）

`db` の認証情報を変える場合は、compose の `db` サービスと `backend` の `ConnectionStrings__PostgreSql` を**両方**揃えて変更してください。

### LazySQL（任意・ホスト）

DB を直接覗く必要があるときだけ、ホストから [LazySQL](https://github.com/jorgerojas26/lazysql) を使えます。**リポジトリ直下**に `.lazysql.toml` を置きます（`.gitignore` 対象）。接続先は公開ポート `localhost:5432` です。

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

メインの [compose.yaml](compose.yaml):

- `${FRONTEND_HOST}` → `/app`（frontend）
- `${BACKEND_HOST}` → `/app`（backend）
- ホストの `~/.ssh` → コンテナ内（read-only）

[compose.personal.yaml](compose.personal.yaml) を重ねた場合の追加マウント:

- ホストの dotfiles（`DOTFILES_HOST`）→ `/home/${USERNAME}/.config/dotfiles`（read-only）
- dotfiles 内の nvim 設定 → `/home/${USERNAME}/.config/nvim`（read-only）
- ホストの `~/.local/state`、Neovim データ用 named volume（`${PROJECT_NAME}_nvim_share`）

アプリコンテナは `user: "${UID}:${GID}"` のため、`.env` の `UID` / `GID` をホストと揃えてから起動してください。

`compose.personal.yaml` では `XDG_CONFIG_HOME` 等を dotfiles に合わせています。dotfiles 側でシンボリックリンク用スクリプトなどを使う場合は、**必要に応じてコンテナ内で手動実行**してください（Compose による自動実行はありません）。

## トラブルシューティング

**`DEV_BASE_IMAGE` が見つからない / frontend・backend のビルドが失敗する**

→ `docker compose --profile build-only build base`（または `base-nvim`）を実行し、`DEV_BASE_IMAGE` のタグが `.env` と一致しているか確認してください。

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

→ `FRONTEND_HOST` / `BACKEND_HOST` が意図した絶対パスか確認してください。

**`docker compose` が見つからない**

→ Docker Desktop または Docker Engine + Compose プラグインをインストールしてください。[Install Docker Compose](https://docs.docker.com/compose/install/) を参照。

## 参考

- Compose 定義: [compose.yaml](compose.yaml)、任意: [compose.personal.yaml](compose.personal.yaml)
- 環境変数テンプレート: [.env.example](.env.example)
- Docker: [Install Docker Engine](https://docs.docker.com/engine/install/)
