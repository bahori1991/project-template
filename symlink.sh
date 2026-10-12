#!/usr/bin/env bash
set -euo pipefail

HOME_DIR="${HOME:?}"
DOTFILES_DIR="$HOME_DIR/.config/dotfiles"

if [[ ! -d "$DOTFILES_DIR" ]]; then
  echo "symlink: skip (no $DOTFILES_DIR)" >&2
  exit 0
fi

warn_missing() {
  if [[ ! -e "$1" ]]; then
    echo "symlink: warning - missing source: $1" >&2
  fi
}

link() {
  warn_missing "$1"
  ln -snf "$1" "$2"
}

# bash
link "$DOTFILES_DIR/bash/.bashrc" "$HOME_DIR/.bashrc"
link "$DOTFILES_DIR/bash/.bash_logout" "$HOME_DIR/.bash_logout"
link "$DOTFILES_DIR/bash/.profile" "$HOME_DIR/.profile"
link "$DOTFILES_DIR/nvim" "$HOME_DIR/.config/nvim"

