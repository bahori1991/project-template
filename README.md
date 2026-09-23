# sample — Docker 開発環境

このリポジトリは、フロントエンド・バックエンド・PostgreSQL を Docker Compose で動かすための開発用セットアップです。アプリケーション本体はリポジトリ直下の `frontend/` と `backend/` をコンテナにマウントして編集します。

## 構成

| サービス | 説明 | ホストポート |
|----------|------|--------------|
| `frontend` | Ubuntu ベース + Vite+（Node） | 3000 |
| `backend` | Ubuntu ベース + .NET SDK 10 | 8080 |
| `db` | PostgreSQL 18 (bookworm) | 5432 |
| `base` | 共通ベースイメージ（ビルド専用） | — |

Docker 関連のファイルはすべて [`.docker/`](.docker/) 以下にあります。

```
.docker/
├── compose.yaml
├── .env.local          # 環境変数のテンプレート（リポジトリに含まれる）
├── .env                # 実際に使う設定（git 管理外。自分で作成）
├── base/Dockerfile     # 共通開発ベース（Neovim, ripgrep など）
├── frontend/Dockerfile
└── backend/Dockerfile
```

## 前提条件

- [Docker Engine](https://docs.docker.com/engine/install/) と Docker Compose v2
- ホスト上に dotfiles が `DOTFILES_HOST` で指定したパスに存在すること（エントリポイントで初回のみ `symlink.sh` を実行）
- （任意）コンテナ内から Git over SSH を使う場合は、ホストの `~/.ssh` と `SSH_AUTH_SOCK` の設定

## 初回セットアップ

### 1. 環境変数

`.docker` ディレクトリで `.env` を用意します。テンプレートをコピーして値を編集してください。

```bash
cd .docker
cp .env.local .env
```

主な変数（[`.docker/.env.local`](.docker/.env.local) 参照）:

| 変数 | 説明 |
|------|------|
| `UID` / `GID` | コンテナ内ユーザー ID（通常は `id -u` / `id -g`） |
| `USERNAME` | コンテナ内の Linux ユーザー名 |
| `PROJECT_NAME` | Compose プロジェクト名 |
| `DOTFILES_HOST` | ホスト側 dotfiles の絶対パス |
| `DEV_BASE_IMAGE` | ベースイメージのタグ（例: `dev-base:ubuntu24.04`） |

`frontend` / `backend` サービスは追加で `.docker/.env` を `env_file` として読み込みます。アプリ固有の変数があれば同じ `.env` に追記してください。

### 2. ベースイメージのビルド

`frontend` と `backend` は `DEV_BASE_IMAGE` を前提としています。先に `base` をビルドします（`build-only` プロファイル）。

```bash
cd .docker
docker compose --profile build-only build base
```

### 3. サービスの起動

```bash
docker compose up -d --build
```

`db` のヘルスチェックが通るまで待ってから `backend` が起動します。

## 日常的な操作

いずれも **`.docker` ディレクトリ** で実行してください。

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
# フロントエンド（プロジェクトに合わせてコマンドは調整）
docker compose exec frontend bash -lc 'cd /app && <your dev command>'

# バックエンド
docker compose exec backend bash -lc 'cd /app && dotnet run'
```

## データベース

| 項目 | 値 |
|------|-----|
| ホストから接続 | `localhost:5432` |
| コンテナ内から | `Host=db;Port=5432;Database=db;Username=user;Password=password` |
| データ永続化 | Docker ボリューム `pg_db` |

`backend` サービスには上記接続文字列が `ConnectionStrings__PostgreSql` として既に設定されています。

## ボリュームとマウント

- `../frontend` → `/app`（frontend）
- `../backend` → `/app`（backend）
- ホストの dotfiles、Neovim データ、`.ssh`（読み取り専用）を開発用にマウント

初回起動時、エントリポイントが `~/.config/dotfiles/scripts/symlink.sh` があれば一度だけ実行し、`~/.cache/container-init.done` で再実行を防ぎます。

## トラブルシューティング

**`DEV_BASE_IMAGE` が見つからない / frontend・backend のビルドが失敗する**

→ `docker compose --profile build-only build base` を実行し、`DEV_BASE_IMAGE` のタグが `.env` と一致しているか確認してください。

**ポートが既に使用中**

→ ホストで 3000 / 8080 / 5432 を使っているプロセスを止めるか、[`.docker/compose.yaml`](.docker/compose.yaml) の `ports` を変更してください。

**権限エラー（作成ファイルの所有者）**

→ `.env` の `UID` / `GID` をホストのユーザーと揃えてからイメージを再ビルドしてください。

```bash
docker compose --profile build-only build --no-cache base
docker compose build --no-cache
```

## 参考

- Compose 定義: [`.docker/compose.yaml`](.docker/compose.yaml)
- 環境変数テンプレート: [`.docker/.env.local`](.docker/.env.local)
