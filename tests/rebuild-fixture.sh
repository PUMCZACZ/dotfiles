#!/bin/bash
set -Eeuo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
rebuild_script="$repo_root/rebuild.sh"

fail() {
  printf 'FAIL %s\n' "$1" >&2
  exit 1
}

[ -x "$rebuild_script" ] || fail "brak wykonywalnego rebuild.sh"

fixture_root=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-rebuild.XXXXXX")
cleanup() {
  case "$fixture_root" in
    "${TMPDIR:-/tmp}"/dotfiles-rebuild.*) /bin/rm -R "$fixture_root" ;;
    *) fail "odmowa cleanup poza katalogiem fixture" ;;
  esac
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$fixture_root/bin"
capture="$fixture_root/sudo-args"
expected="$fixture_root/expected"
fake_sudo="$fixture_root/bin/sudo"

# shellcheck disable=SC2016
printf '%s\n' \
  '#!/bin/bash' \
  'printf "%s\n" "$@" > "$REBUILD_CAPTURE"' > "$fake_sudo"
chmod 755 "$fake_sudo"

printf '%s\n' \
  --preserve-env=DOTFILES_USER,DOTFILES_HOME \
  /run/current-system/sw/bin/darwin-rebuild \
  switch \
  --impure \
  --flake \
  "path:$repo_root#macos" \
  --no-update-lock-file \
  --no-write-lock-file > "$expected"

lock_before=$(/usr/bin/shasum -a 256 "$repo_root/flake.lock" | awk '{ print $1 }')
PATH="$fixture_root/bin:/usr/bin:/bin" REBUILD_CAPTURE="$capture" "$rebuild_script" ||
  fail "rebuild.sh nie przekazał sterowania do sudo"
lock_after=$(/usr/bin/shasum -a 256 "$repo_root/flake.lock" | awk '{ print $1 }')

/usr/bin/diff -u "$expected" "$capture" || fail "sudo otrzymało nieprawidłowe argumenty"
[ "$lock_before" = "$lock_after" ] || fail "rebuild.sh zmienił flake.lock"

rm -f "$capture"
PATH="$fixture_root/bin:/usr/bin:/bin" REBUILD_CAPTURE="$capture" \
  "$repo_root/scripts/switch.sh" </dev/null ||
  fail "scripts/switch.sh nie deleguje do krótkiego rebuild.sh"
/usr/bin/diff -u "$expected" "$capture" ||
  fail "scripts/switch.sh przekazał inne argumenty niż rebuild.sh"

printf 'PASS: rebuild fixture\n'
