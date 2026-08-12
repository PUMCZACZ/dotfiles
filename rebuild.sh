#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
export DOTFILES_USER=${DOTFILES_USER:-$(id -un)}
export DOTFILES_HOME=${DOTFILES_HOME:-$HOME}
exec sudo --preserve-env=DOTFILES_USER,DOTFILES_HOME /run/current-system/sw/bin/darwin-rebuild switch \
  --impure --flake "path:$repo_dir#macos" \
  --no-update-lock-file --no-write-lock-file
