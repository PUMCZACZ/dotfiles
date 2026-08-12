#!/bin/bash
set -Eeuo pipefail
umask 077

script_dir="$(cd "$(dirname "$0")" && pwd -P)"
# shellcheck source=scripts/lib/common.bash
. "$script_dir/lib/common.bash"
# shellcheck source=scripts/lib/adoption.bash
. "$script_dir/lib/adoption.bash"
# shellcheck source=scripts/lib/shell-migration.bash
. "$script_dir/lib/shell-migration.bash"

usage() {
  printf 'Użycie: ./scripts/audit.sh [--help]\n'
}

case ${1:-} in
  --help) usage; exit 0 ;;
  '') ;;
  *) usage >&2; exit "$DOTFILES_EXIT_USAGE" ;;
esac
[ "$#" -le 1 ] || { usage >&2; exit "$DOTFILES_EXIT_USAGE"; }

dotfiles_assert_supported_host audit || exit $?

state_root=$(dotfiles_prepare_state) ||
  dotfiles_die "$DOTFILES_EXIT_ERROR" audit \
    "Nie można przygotować prywatnego katalogu stanu" \
    "Sprawdź właściciela i uprawnienia ${XDG_STATE_HOME:-$HOME/.local/state}" \
    "$(dotfiles_state_root)"
audit_dir="$state_root/audits"
dotfiles_ensure_private_dir "$audit_dir" ||
  dotfiles_die "$DOTFILES_EXIT_ERROR" audit \
    "Katalog audytów nie jest prywatny" \
    "Ustaw właściciela na $(id -un) i uprawnienia 0700" \
    "$audit_dir"

report_path="$audit_dir/$(dotfiles_run_id)-$$.txt"
canary_relative=$DOTFILES_CANARY_RELATIVE_FALLBACK
if dotfiles_load_nix; then
  canary_relative=$(dotfiles_profile_value canaryTarget)
fi
canary_target="$HOME/$canary_relative"
canary_kind=$(adoption_classify "$canary_target") || canary_kind=unsupported
zshrc_target="$HOME/.zshrc"
zshrc_kind=$(shell_migration_classify "$zshrc_target") || zshrc_kind=refused
if [ -f "$zshrc_target" ] && [ ! -L "$zshrc_target" ]; then
  zshrc_hash=$(dotfiles_hash_file "$zshrc_target")
else
  zshrc_hash=absent
fi

audit_command_path() {
  /bin/zsh -lic 'whence -p -- "$1"' audit-login-shell "$1" 2>/dev/null
}

audit_path_owner() {
  case $1 in
    /nix/store/*|/run/current-system/*|/etc/profiles/per-user/*|/nix/var/nix/profiles/*) printf nix ;;
    /opt/homebrew/*) printf homebrew ;;
    "$HOME"/.nvm/*) printf nvm ;;
    /Applications/*) printf application ;;
    /usr/bin/*|/bin/*) printf system ;;
    *) printf user ;;
  esac
}

audit_tool_version() {
  "$1" --version 2>&1 | sed -n '1p' | tr '\t\n' '  '
}

audit_firstmate_home_kind() {
  audit_home=$1
  if [ -L "$audit_home" ]; then
    audit_resolved=$(python3 - "$audit_home" <<'PY' 2>/dev/null || true
import os
import sys
print(os.path.realpath(sys.argv[1]))
PY
    )
    case $audit_resolved in /nix/store/*) printf unsafe ;; *) printf symlink ;; esac
  elif [ -d "$audit_home" ]; then
    printf directory
  elif [ -e "$audit_home" ]; then
    printf unsafe
  else
    printf absent
  fi
}

{
  printf 'stage=audit-complete\n'
  printf 'run_id=%s-%s\n' "$(dotfiles_run_id)" "$$"
  printf 'created_at=%s\n' "$(dotfiles_now_utc)"
  printf 'architecture=%s\n' "$(uname -m)"
  printf 'macos=%s\n' "$(sw_vers -productVersion)"
  printf 'user=%s\n' "$(id -un)"
  printf 'canary_target=%s\n' "$canary_target"
  printf 'canary_kind=%s\n' "$canary_kind"
  printf 'zshrc_hash=%s\n' "$zshrc_hash"
  printf 'pyenv_block=%s\n' "$zshrc_kind"
  printf '\n[binaries]\n'
  for binary in nix brew codex claude node python3 go gh java herdr wezterm \
    docker-mac-net-connect pyenv tmux nvim ghostty dotnet docker; do
    if binary_path=$(audit_command_path "$binary"); then
      printf '%s\t%s\towner=%s\n' \
        "$binary" "$binary_path" "$(stat -f '%Su' "$binary_path" 2>/dev/null || printf unknown)"
    else
      printf '%s\tabsent\n' "$binary"
    fi
  done

  if [ -d /Applications/Ghostty.app ]; then
    printf 'ghostty-app\t/Applications/Ghostty.app\towner=%s\n' \
      "$(stat -f '%Su' /Applications/Ghostty.app 2>/dev/null || printf unknown)"
  else
    printf 'ghostty-app\tabsent\n'
  fi

  printf '\n[firstmate-toolchain]\n'
  for binary in pi firstmate-pi herdr treehouse no-mistakes gh-axi \
    chrome-devtools-axi lavish-axi tasks-axi quota-axi gh node jq python3; do
    if binary_path=$(audit_command_path "$binary"); then
      binary_version=$(audit_tool_version "$binary_path" || printf unknown)
      [ -n "$binary_version" ] || binary_version=unknown
      printf '%s\t%s\tversion=%s\towner=%s\n' \
        "$binary" "$binary_path" "$binary_version" "$(audit_path_owner "$binary_path")"
    else
      printf '%s\tabsent\tversion=unknown\towner=absent\n' "$binary"
    fi
  done

  if herdr_path=$(audit_command_path herdr) && herdr_status=$($herdr_path status --json 2>/dev/null); then
    printf '%s' "$herdr_status" | python3 -c '
import json, sys
server = json.load(sys.stdin).get("server") or {}
print("herdr-server\tversion={}\tprotocol={}\tcompatible={}\trestart_needed={}".format(
    server.get("version", "unknown"), server.get("protocol", "unknown"),
    str(server.get("compatible", False)).lower(),
    str(server.get("restart_needed", False)).lower()))
' 2>/dev/null || printf 'herdr-server\tversion=unknown\tprotocol=unknown\tcompatible=false\trestart_needed=unknown\n'
  else
    printf 'herdr-server\tversion=unknown\tprotocol=unknown\tcompatible=false\trestart_needed=unknown\n'
  fi

  if gh_path=$(audit_command_path gh) && gh_status=$($gh_path auth status --active --json hosts 2>/dev/null); then
    gh_login=$(printf '%s' "$gh_status" | python3 -c '
import json, sys
hosts = json.load(sys.stdin).get("hosts", {})
active = [a for accounts in hosts.values() for a in accounts if a.get("active")]
print(active[0].get("login", "none") if active else "none")
' 2>/dev/null || printf none)
  else
    gh_login=none
  fi
  printf 'gh-active-account\t%s\n' "$gh_login"

  firstmate_home=${FM_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/firstmate}
  printf 'firstmate-home\t%s\tkind=%s\n' "$firstmate_home" "$(audit_firstmate_home_kind "$firstmate_home")"

  chrome_app='/Applications/Google Chrome.app'
  if [ -d "$chrome_app" ]; then
    if codesign --verify --deep --strict "$chrome_app" >/dev/null 2>&1; then chrome_signed=true; else chrome_signed=false; fi
    printf 'chrome-app\t%s\tsigned=%s\n' "$chrome_app" "$chrome_signed"
  else
    printf 'chrome-app\tabsent\tsigned=unknown\n'
  fi

  for migrated_tool in gh herdr; do
    if migrated_path=$(audit_command_path "$migrated_tool") && [ "$(audit_path_owner "$migrated_path")" = homebrew ]; then
      printf 'BLOCKING_OWNER_COLLISION\t%s\tactive=%s\tdesired=nix\n' "$migrated_tool" "$migrated_path"
    fi
  done

  printf '\n[nix]\n'
  if dotfiles_load_nix; then
    nix --version
  else
    printf 'absent\n'
  fi

  printf '\n[homebrew]\n'
  if brew_path=$(audit_command_path brew); then
    "$brew_path" --version | sed -n '1p' || printf 'ERROR: brew --version failed\n'
    brew_prefix=$("$brew_path" --prefix) || brew_prefix=unknown
    printf 'prefix=%s\n' "$brew_prefix"
    if [ -d "$brew_prefix" ]; then
      printf 'prefix_owner=%s\n' "$(stat -f '%Su' "$brew_prefix" 2>/dev/null || printf unknown)"
    else
      printf 'prefix_owner=absent\n'
    fi
    printf '\n[homebrew-taps]\n'
    "$brew_path" tap || printf 'ERROR: brew tap failed\n'
    printf '\n[homebrew-leaves]\n'
    "$brew_path" leaves || printf 'ERROR: brew leaves failed\n'
    printf '\n[homebrew-formulae]\n'
    "$brew_path" list --formula || printf 'ERROR: brew list --formula failed\n'
    printf '\n[homebrew-casks]\n'
    "$brew_path" list --cask || printf 'ERROR: brew list --cask failed\n'
  else
    printf 'absent\n'
  fi

  printf '\n[declared-homebrew-inventory]\n'
  if dotfiles_load_nix; then
    nix eval --impure --raw --no-write-lock-file \
      "path:$DOTFILES_REPO_ROOT#darwinConfigurations.macos.config.dotfiles.homebrew.desiredInventory" ||
      printf 'ERROR: declaration eval failed\n'
  else
    printf 'unavailable\n'
  fi
} > "$report_path"
chmod 600 "$report_path"

dotfiles_log audit "Zakończono etap odczytu; arch=$(uname -m), macOS=$(sw_vers -productVersion), user=$(id -un)"
dotfiles_log audit "Canary: $canary_kind ($canary_target)"
dotfiles_log audit "Raport: $report_path"
