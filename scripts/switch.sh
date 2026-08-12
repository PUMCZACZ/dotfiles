#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
export DOTFILES_USER=${DOTFILES_USER:-$(id -un)}
export DOTFILES_HOME=${DOTFILES_HOME:-$HOME}

case ${1:-} in
  '') exec "$repo_dir/rebuild.sh" ;;
  --dry-run)
    exec /run/current-system/sw/bin/darwin-rebuild build \
      --impure --flake "path:$repo_dir#macos" \
      --dry-run --no-update-lock-file --no-write-lock-file
    ;;
  --help)
    printf 'Użycie: ./rebuild.sh | ./scripts/switch.sh [--dry-run]\n'
    ;;
  *)
    printf 'Użycie: ./rebuild.sh | ./scripts/switch.sh [--dry-run]\n' >&2
    exit 2
    ;;
esac
