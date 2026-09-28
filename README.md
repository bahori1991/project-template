# sample — Docker 開発環境

このリポジトリは、フロントエンド・バックエンド・PostgreSQL を Docker Compose で動かすための開発用セットアップです。アプリケーション本体はリポジトリ直下の `frontend/` と `backend/` をコンテナにマウントして編集します（現時点では各ディレクトリはプレースホルダーのみで、ここに Vite や ASP.NET プロジェクトを配置する想定です）。

## リポジトリ構成

```
sample/
├── frontend/           # フロントエンド（コンテナの /app にマウント）
├── backend/            # バックエンド（コンテナの /app にマウント）
├── .lazysql.toml       # ホストから DB に接続する LazySQL 用（任意）
└── .containers/            # Compose・Dockerfile・環境変数
    ├── compose.yaml
    ├── .env.local      # 環境変数テンプレート（git 管理）
    ├── .env            # 実際に使う設定（git 管理外。自分で作成）
    ├── base/Dockerfile
    ├── frontend/
    │   ├── Dockerfile
    │   └── entrypoint.sh
    └── backend/
        ├── Dockerfile
        └── entrypoint.sh
```

## サービス構成

| サービス | 説明 | ホストポート |
|----------|------|--------------|
| `frontend` | 共通ベース + [Vite+](https://vite.plus)（Node） | 3000 |
| `backend` | 共通ベース + .NET SDK 10 | 8080 |
| `db` | PostgreSQL 18 (bookworm) | 5432 |
| `base` | Ubuntu 24.04 共通開発ベース（ビルド専用） | — |

`base` イメージには、Neovim・ripgrep・fd・eza・tree-sitter CLI などが入ります。バージョンは `.env` の `NVIM_VERSION` / `EZA_VERSION` / `TREE_SITTER_CLI_VERSION` で指定します。

## 前提条件

- [Docker Engine](https://docs.docker.com/engine/install/) と Docker Compose v2
- ホスト上に dotfiles が `DOTFILES_HOST` で指定したパスに存在すること（エントリポイントで初回のみ `symlink.sh` を実行）
- （任意）コンテナ内から Git over SSH を使う場合は、ホストの `~/.ssh` と `SSH_AUTH_SOCK` の設定

## 初回セットアップ

### 1. 環境変数

`.containers` ディレクトリで `.env` を用意します。テンプレートをコピーして値を編集してください。

```bash
cd .containers
cp .env.local .env
```

主な変数（[`.containers/.env.local`](.containers/.env.local) 参照）:

| 変数 | 説明 |
|------|------|
| `PROJECT_NAME` | Compose プロジェクト名（DB ボリューム名 `${PROJECT_NAME}_pg_db` にも使用） |
| `DEV_BASE_IMAGE` | ベースイメージのタグ（例: `dev-base:ubuntu24.04`） |
| `UID` / `GID` | コンテナ内ユーザー ID（通常は `id -u` / `id -g`） |
| `USERNAME` | コンテナ内の Linux ユーザー名 |
| `DOTFILES_HOST` | ホスト側 dotfiles の絶対パス |
| `NVIM_VERSION` / `EZA_VERSION` / `TREE_SITTER_CLI_VERSION` | `base` ビルド時に使うツールのバージョン |
| `DATABASE_URL` | ホストから DB に接続する URL（アプリ・CLI 用。Compose の `db` と値を揃える） |
| `POSTGRES_*` | ホスト側アプリ向けの PostgreSQL 接続情報（`POSTGRES_HOST` など） |

`frontend` / `backend` サービスは `.containers/.env` を `env_file` として読み込みます。アプリ固有の変数があれば同じ `.env` に追記してください。

### 2. ベースイメージのビルド

`frontend` と `backend` は `DEV_BASE_IMAGE` を前提としています。先に `base` をビルドします（`build-only` プロファイル）。

```bash
cd .containers
docker compose --profile build-only build base
```

### 3. サービスの起動

```bash
docker compose up -d --build
```

`db` のヘルスチェックが通るまで待ってから `backend` が起動します。

## 日常的な操作

いずれも **`.containers` ディレクトリ** で実行してください。

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
# フロントエンド（Vite+ / Vite など、プロジェクトに合わせて調整）
docker compose exec frontend bash -lc 'cd /app && <your dev command>'

# バックエンド
docker compose exec backend bash -lc 'cd /app && dotnet run'
```

## データベース

Compose の `db` サービスは次の固定値で起動します（[`.containers/compose.yaml`](.containers/compose.yaml)）。

| 項目 | 値 |
|------|-----|
| ホストから接続 | `localhost:5432` |
| 接続 URL（例） | `postgres://user:password@localhost:5432/db?sslmode=disable` |
| コンテナ内から（.NET） | `Host=db;Port=5432;Database=db;Username=user;Password=password` |
| データ永続化 | Docker ボリューム `${PROJECT_NAME}_pg_db` |

`backend` サービスにはコンテナ内向けの接続文字列が `ConnectionStrings__PostgreSql` として設定されています。

ホストから [LazySQL](https://github.com/jorgerojas26/lazysql) などで接続する場合は、リポジトリ直下の [`.lazysql.toml`](.lazysql.toml) を参考にしてください（上記 URL と整合させます）。`.containers/.env` の `DATABASE_URL` / `POSTGRES_*` も同じ値に揃えると便利です。

## ボリュームとマウント

- `../frontend` → `/app`（frontend）
- `../backend` → `/app`（backend）
- ホストの dotfiles、Neovim データ（`~/.local/share/nvim` / `~/.local/state`）、`.ssh`（読み取り専用）を開発用にマウント

初回起動時、エントリポイントが `~/.config/dotfiles/scripts/symlink.sh` があれば一度だけ実行し、`~/.cache/container-init.done` で再実行を防ぎます。

## トラブルシューティング

**`DEV_BASE_IMAGE` が見つからない / frontend・backend のビルドが失敗する**

→ `docker compose --profile build-only build base` を実行し、`DEV_BASE_IMAGE` のタグが `.env` と一致しているか確認してください。

**ポートが既に使用中**

→ ホストで 3000 / 8080 / 5432 を使っているプロセスを止めるか、[`.containers/compose.yaml`](.containers/compose.yaml) の `ports` を変更してください。

**権限エラー（作成ファイルの所有者）**

→ `.env` の `UID` / `GID` をホストのユーザーと揃えてからイメージを再ビルドしてください。

```bash
docker compose --profile build-only build --no-cache base
docker compose build --no-cache
```

## 参考

- Compose 定義: [`.containers/compose.yaml`](.containers/compose.yaml)
- 環境変数テンプレート: [`.containers/.env.local`](.containers/.env.local)
- LazySQL 設定例: [`.lazysql.toml`](.lazysql.toml)
