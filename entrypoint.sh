#!/usr/bin/env bash
set -euo pipefail

HOME_DIR="${HOME:?entrypoint: HOME is not set}"
if [[ -d "${HOME_DIR}/.config/dotfiles" ]]; then
  /usr/local/bin/symlink.sh
fi
exec "$@"
