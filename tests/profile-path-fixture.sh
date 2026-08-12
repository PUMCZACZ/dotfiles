#!/bin/bash
set -Eeuo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
helper="$repo_root/scripts/lib/profile-path.bash"

fail() {
  printf 'FAIL %s\n' "$1" >&2
  exit 1
}

[ -f "$helper" ] || fail "brak helpera profile-path"
# shellcheck source=scripts/lib/profile-path.bash
. "$helper"

fixture_root=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-profile-path.XXXXXX")
cleanup() {
  case "$fixture_root" in
    "${TMPDIR:-/tmp}"/dotfiles-profile-path.*) /bin/rm -R "$fixture_root" ;;
    *) fail "odmowa cleanup poza katalogiem fixture" ;;
  esac
}
trap cleanup EXIT HUP INT TERM

source_file="$fixture_root/source"
static_file="$fixture_root/static"
target_file="$fixture_root/50-nix-user"
foreign_file="$fixture_root/foreign"

profile_user=${DOTFILES_USER:-$(id -un)}
printf '/etc/profiles/per-user/%s/bin\n' "$profile_user" > "$source_file"
printf '/etc/profiles/per-user/%s/bin\n' "$profile_user" > "$static_file"
ln -s "$static_file" "$target_file"

profile_path_install_regular "$source_file" "$target_file" "$static_file" ||
  fail "zarządzany symlink nie został zastąpiony"
[ -f "$target_file" ] && [ ! -L "$target_file" ] ||
  fail "wynik nie jest zwykłym plikiem"
/usr/bin/cmp -s "$source_file" "$target_file" || fail "wynik ma złą treść"

profile_path_install_regular "$source_file" "$target_file" "$static_file" ||
  fail "drugi przebieg nie jest idempotentny"

printf '%s\n' '/foreign/bin' > "$foreign_file"
if profile_path_install_regular "$source_file" "$foreign_file" "$static_file" 2>/dev/null; then
  fail "obcy zwykły plik został nadpisany"
fi
[ "$(sed -n '1p' "$foreign_file")" = '/foreign/bin' ] ||
  fail "obcy zwykły plik nie został zachowany"

printf 'PASS: profile path fixture\n'
