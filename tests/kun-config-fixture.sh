#!/usr/bin/env bash
set -Eeuo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

fail() {
  printf 'FAIL %s\n' "$1" >&2
  exit 1
}

assert_file() {
  [ -f "$repo_root/$1" ] || fail "brak pliku $1"
}

assert_contains() {
  local file=$1
  local expected=$2
  grep -Fq "$expected" "$repo_root/$file" || fail "$file nie zawiera: $expected"
}

assert_file home/wezterm/wezterm.lua
assert_contains home/wezterm/wezterm.lua 'config.color_scheme = "rose-pine-moon"'
assert_contains home/wezterm/wezterm.lua 'config.font = wezterm.font("JetBrainsMono Nerd Font")'
assert_contains home/wezterm/wezterm.lua 'config.font_size = 15.0'
assert_contains home/wezterm/wezterm.lua 'wezterm.on("window-focus-changed"'

assert_file home/nvim/init.lua
assert_file home/nvim/lazy-lock.json
assert_contains home/nvim/lua/plugin.lua "require('lazy').setup('plugins')"
assert_contains home/nvim/lua/plugins/colorscheme.lua "dark_variant = 'moon'"
assert_contains home/nvim/lua/plugins/navigation.lua "'folke/snacks.nvim'"
assert_contains home/nvim/lua/plugins/git.lua "'NeogitOrg/neogit'"
assert_file home/nvim/lua/plugins/lsp.lua

assert_file modules/home/terminal.nix
assert_contains modules/home/terminal.nix 'home.file.".config/wezterm/wezterm.lua"'
assert_file modules/home/editor.nix
assert_contains modules/home/editor.nix 'neovim'
assert_contains modules/home/editor.nix 'EDITOR = "nvim";'
assert_contains modules/home/editor.nix '".config/nvim/lua/plugins/lsp.lua".source = ../../home/nvim/lua/plugins/lsp.lua;'

printf 'PASS konfiguracja WezTerm i Neovim spełnia kontrakt\n'
