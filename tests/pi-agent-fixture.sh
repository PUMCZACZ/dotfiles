#!/bin/bash
set -Eeuo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
export DOTFILES_USER=${DOTFILES_USER:-$(id -un)}
export DOTFILES_HOME=${DOTFILES_HOME:-$HOME}

fail() {
  printf 'FAIL %s\n' "$1" >&2
  exit 1
}

pi_path=$(nix build --impure --no-link --print-out-paths \
  --no-update-lock-file --no-write-lock-file \
  --expr '
    let
      flake = builtins.getFlake "path:'"$repo_root"'";
      profileUser = builtins.getEnv "DOTFILES_USER";
      packages = flake.darwinConfigurations.macos.config.home-manager.users.${profileUser}.home.packages;
      matches = builtins.filter (package: (package.pname or "") == "pi-coding-agent") packages;
    in
      if builtins.length matches == 1
      then builtins.head matches
      else throw "Home Manager must declare exactly one pi-coding-agent package"
  ') || fail "Home Manager nie udostępnia dokładnie jednego pakietu pi-coding-agent"

[ -x "$pi_path/bin/pi" ] || fail "pakiet PI nie udostępnia wykonywalnej binarki pi"
pi_version=$("$pi_path/bin/pi" --version 2>&1) || fail "pi --version zakończyło się błędem"
[ -n "$pi_version" ] || fail "pi --version zwróciło pusty wynik"

managed_agents_path=$(nix eval --impure --raw --no-update-lock-file --no-write-lock-file \
  --expr '
    let
      flake = builtins.getFlake "path:'"$repo_root"'";
      profileUser = builtins.getEnv "DOTFILES_USER";
      agents = flake.darwinConfigurations.macos.config.home-manager.users.${profileUser}.home.file.".pi/agent/AGENTS.md";
    in
      toString agents.source
  ') || fail "Home Manager nie udostępnia globalnego pliku AGENTS.md PI"

case "$managed_agents_path" in
  */home/pi/AGENTS.md) ;;
  *) fail "Home Manager wskazuje nieprawidłowe źródło globalnego pliku AGENTS.md PI" ;;
esac

agents_path="$repo_root/home/pi/AGENTS.md"
[ -f "$agents_path" ] || fail "źródło globalnego pliku AGENTS.md PI nie istnieje"
grep -Fq "prefer quality, simplicity, robustness, scalability, and long-term maintainability" "$agents_path" \
  || fail "globalny plik AGENTS.md PI nie zawiera zasad podejmowania decyzji technicznych"
grep -Fq "always start by reproducing the bug in an end-to-end setting" "$agents_path" \
  || fail "globalny plik AGENTS.md PI nie zawiera zasad reprodukcji błędów"

managed_work_modes_path=$(nix eval --impure --raw --no-update-lock-file --no-write-lock-file \
  --expr '
    let
      flake = builtins.getFlake "path:'"$repo_root"'";
      profileUser = builtins.getEnv "DOTFILES_USER";
      extension = flake.darwinConfigurations.macos.config.home-manager.users.${profileUser}.home.file.".pi/agent/extensions/work-modes.ts";
    in
      toString extension.source
  ') || fail "Home Manager nie udostępnia rozszerzenia trybów pracy PI"

case "$managed_work_modes_path" in
  */home/pi/extensions/work-modes.ts) ;;
  *) fail "Home Manager wskazuje nieprawidłowe źródło rozszerzenia trybów pracy PI" ;;
esac

work_modes_path="$repo_root/home/pi/extensions/work-modes.ts"
[ -f "$work_modes_path" ] || fail "źródło rozszerzenia trybów pracy PI nie istnieje"
PI_OFFLINE=1 "$pi_path/bin/pi" \
  --no-extensions --extension "$work_modes_path" \
  --no-skills --no-prompt-templates --no-themes --no-context-files \
  --work-mode research --list-models >/dev/null || fail "PI nie ładuje rozszerzenia trybów pracy"

firstmate_launcher=$(nix build --impure --no-link --print-out-paths \
  --no-update-lock-file --no-write-lock-file \
  "path:$repo_root#firstmate-pi") || fail "nie można zbudować launchera firstmate-pi"
launcher_script="$firstmate_launcher/bin/firstmate-pi"
[ -x "$launcher_script" ] || fail "pakiet firstmate-pi nie udostępnia launchera"
grep -Fq -- '--no-extensions' "$launcher_script" \
  || fail "launcher Firstmate nie wyłącza globalnego discovery rozszerzeń"
for extension in fm-calm.ts fm-primary-turnend-guard.ts fm-primary-pi-watch.ts; do
  grep -Fq -- "$extension" "$launcher_script" \
    || fail "launcher Firstmate nie ładuje przypiętego rozszerzenia $extension"
done
if grep -Fq -- 'work-modes.ts' "$launcher_script"; then
  fail "launcher Firstmate ładuje globalne work-modes.ts"
fi
if grep -Fq -- '--approve' "$launcher_script"; then
  fail "launcher Firstmate automatycznie zatwierdza projekt"
fi

firstmate_fixture=$(mktemp -d "${TMPDIR:-/tmp}/pi-firstmate-fixture.XXXXXX")
cleanup_firstmate_fixture() {
  case $firstmate_fixture in
    "${TMPDIR:-/tmp}"/pi-firstmate-fixture.*) rm -Rf "$firstmate_fixture" ;;
    *) fail "odmowa cleanup poza fixture" ;;
  esac
}
trap cleanup_firstmate_fixture EXIT HUP INT TERM
HOME="$firstmate_fixture/user" XDG_DATA_HOME="$firstmate_fixture/data" PI_OFFLINE=1 \
  "$launcher_script" --list-models >/dev/null \
  || fail "firstmate-pi nie ładuje jawnej allowlisty offline"

printf 'PASS: PI %s zachowuje globalny profil, a firstmate-pi ładuje wyłącznie przypiętą allowlistę\n' "$pi_version"
