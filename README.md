# sample — Podman 開発環境

このリポジトリは、フロントエンド・バックエンド・PostgreSQL を Podman Compose で動かすための開発用セットアップです。アプリケーション本体はリポジトリ直下の `frontend/` と `backend/` をコンテナにマウントして編集します（リポジトリ clone 時点ではこれらのディレクトリは含まれないため、初回に自分で作成するか、Compose が空ディレクトリを作るのを利用してください。ここに Vite や ASP.NET プロジェクトを配置する想定です）。

## リポジトリ構成

```
sample/
├── frontend/              # フロントエンド（コンテナの /app にマウント。各自作成）
├── backend/               # バックエンド（コンテナの /app にマウント。各自作成）
├── .lazysql.toml          # ホストから DB に接続する LazySQL 用（任意・git 管理外）
└── .containers/           # Compose・ビルド定義・環境変数
    ├── compose.yaml
    ├── base.Dockerfile    # 共通開発ベース（build-only）
    ├── frontend.Dockerfile
    ├── backend.Dockerfile
    ├── .env.local         # 環境変数テンプレート（git 管理）
    └── .env               # 実際に使う設定（git 管理外。自分で作成）
```

ビルド定義は `.containers/*.Dockerfile` です。Podman / Compose からそのままビルドします（`Containerfile` という名前でも同様に指定可能）。

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
- ホスト上に dotfiles が `DOTFILES_HOST` で指定したパスに存在すること（コンテナ内では `/home/${USERNAME}/.config/dotfiles` に read-only マウント）
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

`frontend` / `backend` サービスは `.containers/.env` を `env_file` として読み込みます。アプリ固有の変数があれば同じ `.env` に追記してください。

DB 接続は **バックエンド（コンテナ内）のみ** を想定しており、接続文字列は [compose.yaml](.containers/compose.yaml) の `ConnectionStrings__PostgreSql` で渡します（`.env` に `DATABASE_URL` 等は不要です）。

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

アプリから PostgreSQL に触るのは **バックエンドのみ** です。フロントエンドは API 経由とし、DB 用の環境変数は Compose / `.env` では用意しません。

Compose の `db` サービスは次の固定値で起動します（[`.containers/compose.yaml`](.containers/compose.yaml)）。

| 項目 | 値 |
|------|-----|
| コンテナ内から（.NET・`backend`） | `Host=db;Port=5432;Database=db;Username=user;Password=password` |
| データ永続化 | Podman ボリューム `${PROJECT_NAME}_pg_db` |

`backend` では上記が環境変数 `ConnectionStrings__PostgreSql` として注入されます。ASP.NET Core では `GetConnectionString("PostgreSql")` で参照できます（`appsettings.Development.json` に同名の接続文字列を書いておき、コンテナ内では compose の値が上書きする形が一般的です）。

EF Core のマイグレーションなども **`backend` コンテナ内** で実行する想定です（`Host=db` のまま使えます）。

```bash
podman compose exec backend bash -lc 'cd /app && dotnet ef database update'
```

（プロジェクトに EF ツールを入れている場合。コマンドはプロジェクトに合わせて読み替えてください。）

`db` の認証情報を変える場合は、compose の `db` サービスと `backend` の `ConnectionStrings__PostgreSql` を**両方**揃えて変更してください。

### LazySQL（任意・ホスト）

DB を直接覗く必要があるときだけ、ホストから [LazySQL](https://github.com/jorgerojas26/lazysql) を使えます。**リポジトリ直下**に `.lazysql.toml` を置きます（`.gitignore` 対象）。接続先は公開ポート `localhost:5432` です（バックエンドのランタイム設定とは独立）。

```toml
[[database]]
Name = "sample (podman db)"
Provider = "postgres"
URL = "postgres://user:password@localhost:5432/db?sslmode=disable"
DBName = "db"
Schemas = ["public"]
ReadOnly = false
```

## ボリュームとマウント

- `../frontend` → `/app`（frontend）
- `../backend` → `/app`（backend）
- ホストの dotfiles（`DOTFILES_HOST`）→ コンテナ内 `/home/${USERNAME}/.config/dotfiles`（read-only）
- Neovim データ（`~/.local/share/nvim` / `~/.local/state`）、`.ssh`（read-only）

アプリコンテナは上記の `user` / `keep-id` 設定のため、`.env` の `UID` / `GID` をホストと揃えてから起動してください。

`frontend` / `backend` では `XDG_CONFIG_HOME` を dotfiles マウント先に合わせています。シェルは `base` イメージ構築時に、マウントされた dotfiles の `bash/.profile` / `bash/.bashrc` を source するよう設定されています。dotfiles 側で `scripts/symlink.sh` などを使う場合は、**必要に応じてコンテナ内で手動実行**してください（Compose による自動実行はありません）。

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
- Podman: [Installation](https://podman.io/docs/installation)
