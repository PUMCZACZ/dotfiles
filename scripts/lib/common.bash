#!/bin/bash

# Shared invariants for public dotfiles commands. Compatible with macOS Bash 3.2.

# Public constants are consumed by scripts sourcing this library.
# shellcheck disable=SC2034
DOTFILES_EXIT_ERROR=1
# shellcheck disable=SC2034
DOTFILES_EXIT_USAGE=2
# shellcheck disable=SC2034
DOTFILES_EXIT_UNSUPPORTED=3
# shellcheck disable=SC2034
DOTFILES_EXIT_DECLINED=4
# shellcheck disable=SC2034
DOTFILES_EXIT_LOCKED=75
DOTFILES_SUPPORTED_USER=${DOTFILES_USER:-$(id -un)}
DOTFILES_PROFILE_HOME=${DOTFILES_HOME:-$HOME}
export DOTFILES_USER="$DOTFILES_SUPPORTED_USER"
export DOTFILES_HOME="$DOTFILES_PROFILE_HOME"
DOTFILES_SUPPORTED_ARCH="arm64"
DOTFILES_SUPPORTED_MACOS_MAJOR="26"
DOTFILES_CANARY_RELATIVE_FALLBACK=".config/dotfiles-managed/foundation"
DOTFILES_LOCK_TOKEN=""

dotfiles_common_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
DOTFILES_REPO_ROOT="$(cd "$dotfiles_common_dir/../.." && pwd -P)"
unset dotfiles_common_dir

dotfiles_now_utc() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

dotfiles_run_id() {
  date -u '+%Y%m%dT%H%M%SZ'
}

dotfiles_log() {
  dotfiles_log_stage=$1
  shift
  printf '[%s] %s\n' "$dotfiles_log_stage" "$*"
}

dotfiles_error() {
  dotfiles_error_stage=$1
  dotfiles_error_cause=$2
  dotfiles_error_next=$3
  dotfiles_error_artifact=${4:-brak}
  printf '[%s] BŁĄD: %s\n' "$dotfiles_error_stage" "$dotfiles_error_cause" >&2
  printf '[%s] Następna bezpieczna czynność: %s\n' "$dotfiles_error_stage" "$dotfiles_error_next" >&2
  printf '[%s] Artefakt diagnostyczny: %s\n' "$dotfiles_error_stage" "$dotfiles_error_artifact" >&2
}

dotfiles_die() {
  dotfiles_die_code=$1
  shift
  dotfiles_error "$@"
  exit "$dotfiles_die_code"
}

dotfiles_state_root() {
  printf '%s\n' "${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles"
}

dotfiles_ensure_private_dir() {
  dotfiles_private_dir=$1
  mkdir -p "$dotfiles_private_dir"
  chmod 700 "$dotfiles_private_dir"

  dotfiles_private_owner=$(stat -f '%Su' "$dotfiles_private_dir")
  if [ "$dotfiles_private_owner" != "$(id -un)" ]; then
    return 1
  fi

  dotfiles_private_mode=$(stat -f '%Lp' "$dotfiles_private_dir")
  case "$dotfiles_private_mode" in
    700|600) return 0 ;;
    *) return 1 ;;
  esac
}

dotfiles_prepare_state() {
  dotfiles_state_dir=$(dotfiles_state_root)
  dotfiles_ensure_private_dir "$dotfiles_state_dir"
  printf '%s\n' "$dotfiles_state_dir"
}

dotfiles_path_is_in_state() {
  dotfiles_state_path=$1
  dotfiles_expected_state=$(dotfiles_state_root)
  case "$dotfiles_state_path" in
    "$dotfiles_expected_state"/*) ;;
    *) return 1 ;;
  esac
  case "$dotfiles_state_path" in
    *'/../'*|*'/./'*|*$'\t'*|*$'\n'*) return 1 ;;
  esac
}

dotfiles_is_private_regular_file() {
  dotfiles_private_file=$1
  [ -f "$dotfiles_private_file" ] || return 1
  [ ! -L "$dotfiles_private_file" ] || return 1
  [ "$(stat -f '%Su' "$dotfiles_private_file")" = "$(id -un)" ] || return 1
  [ "$(stat -f '%Lp' "$dotfiles_private_file")" = 600 ] || return 1
}

dotfiles_write_private_file() {
  dotfiles_private_target=$1
  dotfiles_path_is_in_state "$dotfiles_private_target" || return 1
  [ ! -L "$dotfiles_private_target" ] || return 1

  dotfiles_private_parent=$(dirname "$dotfiles_private_target")
  dotfiles_ensure_private_dir "$dotfiles_private_parent" || return 1
  dotfiles_private_name=$(basename "$dotfiles_private_target")
  dotfiles_private_tmp="$dotfiles_private_parent/.$dotfiles_private_name.tmp.$$.$RANDOM"

  if ! /bin/cat > "$dotfiles_private_tmp"; then
    /bin/rm -f "$dotfiles_private_tmp"
    return 1
  fi
  chmod 600 "$dotfiles_private_tmp" || {
    /bin/rm -f "$dotfiles_private_tmp"
    return 1
  }
  mv -f "$dotfiles_private_tmp" "$dotfiles_private_target"
}

dotfiles_remove_private_file() {
  dotfiles_private_remove=$1
  dotfiles_path_is_in_state "$dotfiles_private_remove" || return 1
  [ ! -d "$dotfiles_private_remove" ] || return 1
  /bin/rm -f "$dotfiles_private_remove"
}

dotfiles_assert_supported_host() {
  dotfiles_host_stage=$1
  dotfiles_actual_arch=$(uname -m)
  dotfiles_actual_macos=$(sw_vers -productVersion)
  dotfiles_actual_major=${dotfiles_actual_macos%%.*}
  dotfiles_actual_user=$(id -un)

  if [ "$dotfiles_actual_arch" != "$DOTFILES_SUPPORTED_ARCH" ] ||
    [ "$dotfiles_actual_major" != "$DOTFILES_SUPPORTED_MACOS_MAJOR" ] ||
    [ "$dotfiles_actual_user" != "$DOTFILES_SUPPORTED_USER" ]; then
    dotfiles_error "$dotfiles_host_stage" \
      "Niewspierany host: arch=$dotfiles_actual_arch macOS=$dotfiles_actual_macos user=$dotfiles_actual_user" \
      "Uruchom tylko na profilu macos: arm64, macOS 26, użytkownik $DOTFILES_SUPPORTED_USER" \
      "brak"
    return "$DOTFILES_EXIT_UNSUPPORTED"
  fi
}

dotfiles_refuse_root() {
  dotfiles_root_stage=$1
  if [ "$(id -u)" -eq 0 ]; then
    dotfiles_error "$dotfiles_root_stage" \
      "Cały mutator nie może działać jako root" \
      "Uruchom skrypt jako $DOTFILES_SUPPORTED_USER; zaakceptuj wyłącznie pokazane sudo" \
      "brak"
    return "$DOTFILES_EXIT_UNSUPPORTED"
  fi
}

dotfiles_acquire_lock() {
  dotfiles_lock_stage=$1
  dotfiles_lock_state=$(dotfiles_prepare_state) || {
    dotfiles_error "$dotfiles_lock_stage" \
      "Lokalny katalog stanu nie jest prywatny albo nie należy do użytkownika" \
      "Sprawdź właściciela i ustaw uprawnienia 0700" \
      "$(dotfiles_state_root)"
    return "$DOTFILES_EXIT_ERROR"
  }
  DOTFILES_LOCK_DIR="$dotfiles_lock_state/operation.lock"

  if ! mkdir "$DOTFILES_LOCK_DIR" 2>/dev/null; then
    dotfiles_error "$dotfiles_lock_stage" \
      "Inna operacja mutująca posiada blokadę" \
      "Sprawdź ręcznie metadane blokady; nie usuwaj jej bez potwierdzenia, że proces zakończył pracę" \
      "$DOTFILES_LOCK_DIR/metadata"
    return "$DOTFILES_EXIT_LOCKED"
  fi

  chmod 700 "$DOTFILES_LOCK_DIR"
  DOTFILES_LOCK_TOKEN="$$.$RANDOM.$(date +%s)"
  {
    printf 'pid=%s\n' "$$"
    printf 'user=%s\n' "$(id -un)"
    printf 'host=%s\n' "$(hostname)"
    printf 'started_at=%s\n' "$(dotfiles_now_utc)"
    printf 'token=%s\n' "$DOTFILES_LOCK_TOKEN"
  } > "$DOTFILES_LOCK_DIR/metadata"
  chmod 600 "$DOTFILES_LOCK_DIR/metadata"
}

dotfiles_release_lock() {
  if [ -z "${DOTFILES_LOCK_DIR:-}" ] || [ -z "$DOTFILES_LOCK_TOKEN" ]; then
    return 0
  fi
  if [ ! -f "$DOTFILES_LOCK_DIR/metadata" ]; then
    return 0
  fi

  dotfiles_lock_recorded_token=$(awk -F= '$1 == "token" { print $2 }' "$DOTFILES_LOCK_DIR/metadata")
  if [ "$dotfiles_lock_recorded_token" != "$DOTFILES_LOCK_TOKEN" ]; then
    return "$DOTFILES_EXIT_ERROR"
  fi

  /bin/rm "$DOTFILES_LOCK_DIR/metadata"
  rmdir "$DOTFILES_LOCK_DIR"
  DOTFILES_LOCK_DIR=""
  DOTFILES_LOCK_TOKEN=""
}

dotfiles_hash_file() {
  shasum -a 256 "$1" | awk '{ print $1 }'
}

dotfiles_declaration_hash() {
  (
    cd "$DOTFILES_REPO_ROOT" || exit 1
    find flake.nix flake.lock hosts modules -type f -print | LC_ALL=C sort |
      while IFS= read -r dotfiles_declaration_file; do
        shasum -a 256 "$dotfiles_declaration_file"
      done
  ) | shasum -a 256 | awk '{ print $1 }'
}

dotfiles_profile_value() {
  dotfiles_profile_key=$1
  nix eval --impure --raw --no-write-lock-file \
    "path:$DOTFILES_REPO_ROOT#darwinConfigurations.macos.config.dotfiles.foundation.$dotfiles_profile_key"
}

dotfiles_homebrew_value() {
  dotfiles_homebrew_key=$1
  nix eval --impure --raw --no-write-lock-file \
    "path:$DOTFILES_REPO_ROOT#darwinConfigurations.macos.config.dotfiles.homebrew.$dotfiles_homebrew_key"
}

dotfiles_load_nix() {
  if command -v nix >/dev/null 2>&1; then
    return 0
  fi
  if [ -r /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
    # shellcheck disable=SC1091
    . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
  fi
  command -v nix >/dev/null 2>&1
}
