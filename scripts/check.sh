#!/bin/bash
set -Eeuo pipefail
umask 077

script_dir="$(cd "$(dirname "$0")" && pwd -P)"
# shellcheck source=scripts/lib/common.bash
. "$script_dir/lib/common.bash"

usage() {
  printf 'Użycie: ./scripts/check.sh [--help]\n'
}

case ${1:-} in
  --help) usage; exit 0 ;;
  '') ;;
  *) usage >&2; exit "$DOTFILES_EXIT_USAGE" ;;
esac
[ "$#" -le 1 ] || { usage >&2; exit "$DOTFILES_EXIT_USAGE"; }

dotfiles_assert_supported_host check || exit $?
dotfiles_load_nix ||
  dotfiles_die "$DOTFILES_EXIT_ERROR" check \
    "Nix jest niedostępny" \
    "Uruchom przypięty instalator przez scripts/bootstrap.sh" \
    "brak"

cd "$DOTFILES_REPO_ROOT"
lock_before=$(dotfiles_hash_file flake.lock)
check_tmp=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-check.XXXXXX")
check_cleanup() {
  case "$check_tmp" in
    "${TMPDIR:-/tmp}"/dotfiles-check.*) /bin/rm -R "$check_tmp" ;;
    *) dotfiles_log check "WARN odmowa cleanup poza katalogiem tymczasowym: $check_tmp" ;;
  esac
}
trap check_cleanup EXIT HUP INT TERM

declaration_status=$(git status --short -- flake.nix flake.lock hosts modules)
if [ -n "$declaration_status" ]; then
  dotfiles_log check "INFO niezacommitowane deklaracje widoczne przed walidacją:"
  printf '%s\n' "$declaration_status"
else
  dotfiles_log check "PASS brak niezacommitowanych zmian deklaracji"
fi

check_step() {
  check_step_name=$1
  shift
  dotfiles_log check "START $check_step_name"
  if "$@"; then
    dotfiles_log check "PASS $check_step_name"
  else
    check_status=$?
    dotfiles_error check \
      "Etap $check_step_name zakończył się kodem $check_status" \
      "Napraw wskazany etap i uruchom scripts/check.sh ponownie" \
      "brak (pełny log pozostaje w terminalu)"
    return "$check_status"
  fi
}

check_homebrew_contract() {
  check_brewfile="$check_tmp/Brewfile"
  check_inventory="$check_tmp/inventory.tsv"
  check_expected="$check_tmp/expected.tsv"
  nix eval --impure --raw --no-write-lock-file \
    "path:$DOTFILES_REPO_ROOT#darwinConfigurations.macos.config.homebrew.brewfile" > "$check_brewfile" || return 1
  sed -nE 's/^(tap|brew|cask) "([^"]+)".*/\1\t\2/p' "$check_brewfile" > "$check_inventory"
  printf '%s\n' \
    $'tap\tchipmk/tap' \
    $'brew\tgo' \
    $'brew\tgh' \
    $'brew\topenjdk@21' \
    $'brew\therdr' \
    $'brew\tchipmk/tap/docker-mac-net-connect' \
    $'cask\twezterm' \
    $'cask\tzulu@17' \
    $'cask\tfont-jetbrains-mono-nerd-font' > "$check_expected"
  diff -u "$check_expected" "$check_inventory" || return 1

  check_expected_brewfile_hash=$(nix eval --impure --raw --no-write-lock-file \
    "path:$DOTFILES_REPO_ROOT#darwinConfigurations.macos.config.dotfiles.homebrew.brewfileHash") || return 1
  [ "$(dotfiles_hash_file "$check_brewfile")" = "$check_expected_brewfile_hash" ] || return 1
  [ "$(nix eval --impure --raw --no-write-lock-file \
    "path:$DOTFILES_REPO_ROOT#darwinConfigurations.macos.config.homebrew.onActivation.cleanup")" = zap ] || return 1
  [ "$(nix eval --impure --raw --no-write-lock-file \
    "path:$DOTFILES_REPO_ROOT#darwinConfigurations.macos.config.homebrew.prefix")" = /opt/homebrew ] || return 1
}

check_full_build() {
  CHECK_SYSTEM_PATH=$(nix build --impure --no-link --print-out-paths \
    --no-update-lock-file --no-write-lock-file \
    "path:$DOTFILES_REPO_ROOT#darwinConfigurations.macos.system")
  [ -x "$CHECK_SYSTEM_PATH/activate" ]
}

check_direct_rebuild_contract() {
  ! grep -q 'dotfiles-homebrew-activation-guard' "$CHECK_SYSTEM_PATH/activate" || return 1
  grep -q -- '--zap --force-cleanup' "$CHECK_SYSTEM_PATH/activate"
}

check_profile_path_activation_contract() {
  [ ! -e "$CHECK_SYSTEM_PATH/etc/paths.d/50-nix-user" ] &&
    [ ! -L "$CHECK_SYSTEM_PATH/etc/paths.d/50-nix-user" ] || return 1
  grep -q 'profile_path_install_regular' "$CHECK_SYSTEM_PATH/activate" || return 1
  grep -q '/etc/paths.d/50-nix-user' "$CHECK_SYSTEM_PATH/activate"
}

check_nvim_lua() {
  find home/nvim -type f -name '*.lua' -print0 |
    while IFS= read -r -d '' check_lua_file; do
      luac -p "$check_lua_file" || return 1
    done
  lua tests/nvim-lsp-fixture.lua
}

check_wezterm_runtime() {
  wezterm --config-file home/wezterm/wezterm.lua show-keys >/dev/null || return 1
  wezterm ls-fonts --list-system |
    grep -F 'wezterm.font("JetBrainsMono Nerd Font"' >/dev/null
}

check_step bash-parse /bin/bash -n rebuild.sh scripts/*.sh scripts/lib/*.bash tests/*.sh
check_step shellcheck nix develop --impure "path:$DOTFILES_REPO_ROOT" --command \
  shellcheck -x rebuild.sh scripts/*.sh scripts/lib/*.bash tests/*.sh
check_step adoption-fixture ./tests/adoption-fixture.sh
check_step shell-migration-fixture ./tests/shell-migration-fixture.sh
check_step homebrew-plan-fixture ./tests/homebrew-plan-fixture.sh
check_step profile-path-fixture ./tests/profile-path-fixture.sh
check_step kun-config-fixture ./tests/kun-config-fixture.sh
check_step pi-agent-fixture ./tests/pi-agent-fixture.sh
check_step rebuild-fixture ./tests/rebuild-fixture.sh
check_step gitleaks-tree nix develop --impure "path:$DOTFILES_REPO_ROOT" --command \
  gitleaks dir --no-banner --redact .

if git rev-parse --verify HEAD >/dev/null 2>&1; then
  check_step gitleaks-history nix develop --impure "path:$DOTFILES_REPO_ROOT" --command \
    gitleaks git --no-banner --redact .
else
  dotfiles_log check "SKIP gitleaks-history: repo nie ma pierwszego commita"
fi

check_step flake-eval nix flake check --impure --no-build \
  --no-update-lock-file --no-write-lock-file "path:$DOTFILES_REPO_ROOT"
check_step homebrew-contract check_homebrew_contract
if [ -f home/herdr/config.toml ]; then
  check_step herdr-toml nix develop --impure "path:$DOTFILES_REPO_ROOT" --command taplo check home/herdr/config.toml
fi
if [ -f home/wezterm/wezterm.lua ]; then
  check_step wezterm-lua nix develop --impure "path:$DOTFILES_REPO_ROOT" --command lua -e \
    'assert(loadfile("home/wezterm/wezterm.lua"))'
  check_step wezterm-runtime check_wezterm_runtime
fi
if [ -d home/nvim ]; then
  check_step nvim-lua nix develop --impure "path:$DOTFILES_REPO_ROOT" --command bash -c \
    "$(declare -f check_nvim_lua); check_nvim_lua"
fi
check_step full-build check_full_build
check_step direct-rebuild-contract check_direct_rebuild_contract
check_step profile-path-activation-contract check_profile_path_activation_contract

lock_after=$(dotfiles_hash_file flake.lock)
if [ "$lock_before" != "$lock_after" ]; then
  dotfiles_die "$DOTFILES_EXIT_ERROR" check \
    "flake.lock zmienił się podczas walidacji" \
    "Przejrzyj diff locka i przywróć zatwierdzony stan przed aktywacją" \
    "$DOTFILES_REPO_ROOT/flake.lock"
fi

dotfiles_log check "Zakończono wszystkie etapy; flake.lock=$lock_after"
