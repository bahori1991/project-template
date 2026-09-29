# sample — Podman 開発環境

このリポジトリは、フロントエンド・バックエンド・PostgreSQL を Podman Compose で動かすための開発用セットアップです。アプリケーション本体はリポジトリ直下の `frontend/` と `backend/` をコンテナにマウントして編集します（現時点では各ディレクトリはプレースホルダーのみで、ここに Vite や ASP.NET プロジェクトを配置する想定です）。

## リポジトリ構成

```
sample/
├── frontend/           # フロントエンド（コンテナの /app にマウント）
├── backend/            # バックエンド（コンテナの /app にマウント）
├── .lazysql.toml       # ホストから DB に接続する LazySQL 用（任意）
└── .containers/            # Compose・ビルド定義・環境変数
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

ビルド定義のファイル名は `Dockerfile` ですが、Podman からそのままビルドします（`Containerfile` でも可）。

## サービス構成

| サービス | 説明 | ホストポート |
|----------|------|--------------|
| `frontend` | 共通ベース + [Vite+](https://vite.plus)（Node） | 3000 |
| `backend` | 共通ベース + .NET SDK 10 | 8080 |
| `db` | PostgreSQL 18 (bookworm) | 5432 |
| `base` | Ubuntu 24.04 共通開発ベース（ビルド専用） | — |

`frontend` と `backend` は Compose で `user: "${UID}:${GID}"` と `userns_mode: keep-id` を指定し、ホストのユーザー ID と揃えた状態で動かします。bind mount した `frontend/` / `backend/` に作成したファイルの所有者がホスト側と一致しやすくなります（Podman の rootless 実行を想定）。

`base` イメージには、Neovim・ripgrep・fd・eza・tree-sitter CLI などが入ります。バージョンは `.env` の `NVIM_VERSION` / `EZA_VERSION` / `TREE_SITTER_CLI_VERSION` で指定します。

## 前提条件

- [Podman](https://podman.io/docs/installation) と [Podman Compose](https://github.com/containers/podman-compose)（または Podman 4.7+ 付属の `podman compose` サブコマンド）
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
| `UID` / `GID` | ホストと同じユーザー / グループ ID（`id -u` / `id -g`）。`frontend` / `backend` の実行ユーザーと `base` ビルド時の ID に使う |
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
podman compose --profile build-only build base
```

### 3. サービスの起動

```bash
podman compose up -d --build
```

`db` のヘルスチェックが通るまで待ってから `backend` が起動します。

## 日常的な操作

いずれも **`.containers` ディレクトリ** で実行してください。

```bash
# 起動
podman compose up -d

# 停止
podman compose down

# 停止（DB ボリュームも削除）
podman compose down -v

# ログ
podman compose logs -f
podman compose logs -f backend

# イメージの再ビルド
podman compose build
podman compose up -d --build

# コンテナに入る（対話シェル）
podman compose exec frontend bash
podman compose exec backend bash
```

各アプリコンテナのデフォルト CMD は `sleep infinity` です。開発サーバーや `dotnet run` はコンテナ内で手動実行する想定です。

### 例: 開発サーバー

```bash
# フロントエンド（Vite+ / Vite など、プロジェクトに合わせて調整）
podman compose exec frontend bash -lc 'cd /app && <your dev command>'

# バックエンド
podman compose exec backend bash -lc 'cd /app && dotnet run'
```

## データベース

Compose の `db` サービスは次の固定値で起動します（[`.containers/compose.yaml`](.containers/compose.yaml)）。

| 項目 | 値 |
|------|-----|
| ホストから接続 | `localhost:5432` |
| 接続 URL（例） | `postgres://user:password@localhost:5432/db?sslmode=disable` |
| コンテナ内から（.NET） | `Host=db;Port=5432;Database=db;Username=user;Password=password` |
| データ永続化 | Podman ボリューム `${PROJECT_NAME}_pg_db` |

`backend` サービスにはコンテナ内向けの接続文字列が `ConnectionStrings__PostgreSql` として設定されています。

ホストから [LazySQL](https://github.com/jorgerojas26/lazysql) などで接続する場合は、リポジトリ直下の [`.lazysql.toml`](.lazysql.toml) を参考にしてください（上記 URL と整合させます）。`.containers/.env` の `DATABASE_URL` / `POSTGRES_*` も同じ値に揃えると便利です。

## ボリュームとマウント

- `../frontend` → `/app`（frontend）
- `../backend` → `/app`（backend）
- ホストの dotfiles、Neovim データ（`~/.local/share/nvim` / `~/.local/state`）、`.ssh`（読み取り専用）を開発用にマウント

アプリコンテナは上記の `user` / `keep-id` 設定のため、`.env` の `UID` / `GID` をホストと揃えてから起動してください。

初回起動時、エントリポイントが `~/.config/dotfiles/scripts/symlink.sh` があれば一度だけ実行し、`~/.cache/container-init.done` で再実行を防ぎます。

## トラブルシューティング

**`DEV_BASE_IMAGE` が見つからない / frontend・backend のビルドが失敗する**

→ `podman compose --profile build-only build base` を実行し、`DEV_BASE_IMAGE` のタグが `.env` と一致しているか確認してください。

**ポートが既に使用中**

→ ホストで 3000 / 8080 / 5432 を使っているプロセスを止めるか、[`.containers/compose.yaml`](.containers/compose.yaml) の `ports` を変更してください。

**権限エラー（作成ファイルの所有者）**

→ `.env` の `UID` / `GID` がホストの `id -u` / `id -g` と一致しているか確認し、変更した場合は `base` とアプリイメージを再ビルドしてから再起動してください。

```bash
podman compose --profile build-only build --no-cache base
podman compose build --no-cache
podman compose up -d
```

**`podman compose` が見つからない**

→ 配布パッケージの `podman-compose` をインストールするか、Podman を新しいバージョンに更新してください。外部ツール `podman-compose`（Python）を使う場合は、README のコマンドを `podman-compose` に読み替えてください。

## 参考

- Compose 定義: [`.containers/compose.yaml`](.containers/compose.yaml)
- 環境変数テンプレート: [`.containers/.env.local`](.containers/.env.local)
- LazySQL 設定例: [`.lazysql.toml`](.lazysql.toml)
- Podman: [Installation](https://podman.io/docs/installation)
