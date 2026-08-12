#!/bin/bash
set -Eeuo pipefail
umask 077

script_dir="$(cd "$(dirname "$0")" && pwd -P)"
# shellcheck source=scripts/lib/common.bash
. "$script_dir/lib/common.bash"
# shellcheck source=scripts/lib/homebrew-plan.bash
. "$script_dir/lib/homebrew-plan.bash"
# shellcheck source=scripts/lib/shell-migration.bash
. "$script_dir/lib/shell-migration.bash"

usage() {
  printf 'Użycie: ./scripts/doctor.sh [--help]\n'
}

case ${1:-} in
  --help) usage; exit 0 ;;
  '') ;;
  *) usage >&2; exit "$DOTFILES_EXIT_USAGE" ;;
esac
[ "$#" -le 1 ] || { usage >&2; exit "$DOTFILES_EXIT_USAGE"; }

critical_fail=0

doctor_status() {
  doctor_layer=$1
  doctor_result=$2
  doctor_message=$3
  doctor_next=${4:-}
  printf '[doctor] %-12s %-6s %s\n' "$doctor_layer" "$doctor_result" "$doctor_message"
  if [ "$doctor_result" = FAIL ]; then
    critical_fail=1
  fi
  if [ -n "$doctor_next" ] && { [ "$doctor_result" = FAIL ] || [ "$doctor_result" = MANUAL ]; }; then
    printf '[doctor] %-12s NEXT   %s\n' "$doctor_layer" "$doctor_next"
  fi
}

doctor_command_path() {
  /bin/zsh -lic 'whence -p -- "$1"' doctor-login "$1" 2>/dev/null
}

doctor_nix_owned_path() {
  case $1 in
    /nix/store/*|/run/current-system/*|/etc/profiles/per-user/*|/nix/var/nix/profiles/*) return 0 ;;
    *) return 1 ;;
  esac
}

doctor_version_contains() {
  "$1" --version 2>&1 | sed -n '1p' | grep -Fq -- "$2"
}

actual_macos=$(sw_vers -productVersion)
if [ "$(uname -m)" = "$DOTFILES_SUPPORTED_ARCH" ] &&
  [ "${actual_macos%%.*}" = "$DOTFILES_SUPPORTED_MACOS_MAJOR" ] &&
  [ "$(id -un)" = "$DOTFILES_SUPPORTED_USER" ]; then
  doctor_status platform PASS "arm64, macOS $actual_macos, użytkownik $(id -un)"
else
  doctor_status platform FAIL "Niewspierany host" "Uruchom na profilu macos: arm64, macOS 26, użytkownik $DOTFILES_SUPPORTED_USER"
fi

if dotfiles_load_nix; then
  doctor_status nix PASS "$(nix --version)"
  if nix store info --store daemon >/dev/null 2>&1; then
    doctor_status daemon PASS "daemon odpowiada"
  else
    doctor_status daemon FAIL "Daemon nie odpowiada" "Uruchom ponownie usługę Determinate Nix i powtórz doctor"
  fi
else
  doctor_status nix FAIL "Nix jest niedostępny" "Zainstaluj przypięty Determinate Nix przez bootstrap"
  doctor_status daemon FAIL "Nix jest niedostępny" "Najpierw napraw warstwę Nix"
fi

if [ -e /run/current-system ]; then
  doctor_status generation PASS "$(readlink /run/current-system 2>/dev/null || printf /run/current-system)"
else
  doctor_status generation FAIL "Brak aktywnej generacji nix-darwin" "Wykonaj najpierw switch --dry-run"
fi

if dotfiles_load_nix; then
  canary_relative=$(dotfiles_profile_value canaryTarget)
  expected_content=$(dotfiles_profile_value canaryContent)
else
  canary_relative=$DOTFILES_CANARY_RELATIVE_FALLBACK
  expected_content=''
fi
canary_target="$HOME/$canary_relative"
if [ -L "$canary_target" ] && [ -f "$canary_target" ]; then
  canary_owner=$(stat -f '%Su' "$canary_target")
  if [ "$canary_owner" = "$(id -un)" ]; then
    doctor_status canary-owner PASS "$canary_owner"
  else
    doctor_status canary-owner FAIL "Właściciel=$canary_owner; oczekiwano $(id -un)" "Nie zmieniaj właściciela automatycznie; sprawdź aktywną generację i receipt"
  fi
  actual_content=$(sed -n '1,$p' "$canary_target")
  if [ -n "$expected_content" ] && [ "$actual_content" = "$expected_content" ]; then
    doctor_status canary PASS "$canary_target jest zgodny z deklaracją"
  else
    doctor_status canary FAIL "Treść nie odpowiada bieżącej deklaracji" "Wykonaj check i switch --dry-run"
  fi
else
  doctor_status canary FAIL "Brak zarządzanego symlinka $canary_target" "Sprawdź manifest backupu, potem wykonaj check i switch --dry-run"
fi

doctor_compare_set() {
  doctor_set_layer=$1
  doctor_set_expected=$2
  doctor_set_actual=$3
  if [ "$doctor_set_actual" = "$doctor_set_expected" ]; then
    doctor_status "$doctor_set_layer" PASS "dokładny zestaw zgodny z deklaracją"
  else
    doctor_status "$doctor_set_layer" FAIL \
      "niezgodny zestaw: $(printf '%s' "$doctor_set_actual" | tr '\n' ' ')" \
      "Porównaj scripts/switch.sh --dry-run z deklaracją Homebrew"
  fi
}

if brew_path=$(/bin/zsh -lic 'whence -p brew' 2>/dev/null); then
  brew_prefix=$("$brew_path" --prefix 2>/dev/null || printf unknown)
  brew_owner=$(stat -f '%Su' "$brew_prefix" 2>/dev/null || printf unknown)
  if [ "$brew_prefix" = /opt/homebrew ] && [ "$brew_owner" = "$DOTFILES_SUPPORTED_USER" ]; then
    doctor_status homebrew PASS "prefix=/opt/homebrew owner=$brew_owner"
  else
    doctor_status homebrew FAIL "prefix=$brew_prefix owner=$brew_owner" "Ten profil wymaga /opt/homebrew należącego do $DOTFILES_SUPPORTED_USER"
  fi

  declared_inventory=$(nix eval --impure --raw --no-write-lock-file \
    "path:$DOTFILES_REPO_ROOT#darwinConfigurations.macos.config.dotfiles.homebrew.desiredInventory")
  expected_taps=$(printf '%s\n' "$declared_inventory" | homebrew_inventory_names - tap)
  expected_leaves=$(printf '%s\n' "$declared_inventory" | homebrew_inventory_names - formula)
  expected_casks=$(printf '%s\n' "$declared_inventory" | homebrew_inventory_names - cask)
  actual_taps=$(HOMEBREW_NO_AUTO_UPDATE=1 "$brew_path" tap 2>/dev/null | LC_ALL=C sort)
  actual_leaves=$(HOMEBREW_NO_AUTO_UPDATE=1 "$brew_path" leaves 2>/dev/null | LC_ALL=C sort)
  actual_casks=$(HOMEBREW_NO_AUTO_UPDATE=1 "$brew_path" list --cask 2>/dev/null | LC_ALL=C sort)
  doctor_compare_set brew-taps "$expected_taps" "$actual_taps"
  doctor_compare_set brew-leaves "$expected_leaves" "$actual_leaves"
  doctor_compare_set brew-casks "$expected_casks" "$actual_casks"
else
  brew_path=""
  doctor_status homebrew FAIL "Homebrew jest niedostępny" "Sprawdź /opt/homebrew i receipt aktywacji"
fi

for required_tool in go docker-mac-net-connect; do
  if tool_path=$(/bin/zsh -lic 'whence -p -- "$1"' doctor-login "$required_tool" 2>/dev/null); then
    doctor_status "tool-$required_tool" PASS "$tool_path"
  else
    doctor_status "tool-$required_tool" FAIL "brak w login shell" "Sprawdź deklarację Homebrew i aktywną generację"
  fi
done

for required_nix_tool in nvim rg fd; do
  if tool_path=$(/bin/zsh -lic 'whence -p -- "$1"' doctor-login "$required_nix_tool" 2>/dev/null); then
    doctor_status "tool-$required_nix_tool" PASS "$tool_path"
  else
    doctor_status "tool-$required_nix_tool" FAIL "brak w login shell" "Sprawdź aktywną generację Home Managera"
  fi
done

firstmate_inventory=''
if dotfiles_load_nix && firstmate_inventory=$(nix eval --impure --raw --no-write-lock-file --expr '
  let
    flake = builtins.getFlake "path:'"$DOTFILES_REPO_ROOT"'";
    profileUser = builtins.getEnv "DOTFILES_USER";
  in
    flake.darwinConfigurations.macos.config.home-manager.users.${profileUser}.dotfiles.firstmate.desiredInventory
' 2>/dev/null); then
  doctor_status fm-inventory PASS "deklaratywny inventory jest dostępny"
else
  doctor_status fm-inventory FAIL "nie można odczytać inventory Firstmate" "Sprawdź ewaluację modules/home/agents.nix"
fi

while IFS="$(printf '\t')" read -r component expected_version; do
  [ -n "$component" ] || continue
  case $component in
    pi-coding-agent) component_command=pi ;;
    firstmate-snapshot|chrome-devtools-mcp|firstmate-pi) continue ;;
    *) component_command=$component ;;
  esac
  if component_path=$(doctor_command_path "$component_command") && \
    doctor_version_contains "$component_path" "$expected_version"; then
    doctor_status "fm-$component_command" PASS "$component_path version=$expected_version"
  else
    doctor_status "fm-$component_command" FAIL "brak albo wersja inna niż $expected_version" "Aktywuj przypięty profil agentów po zatwierdzonym preview"
  fi
done <<EOF
$firstmate_inventory
EOF

for migrated_tool in gh herdr; do
  if migrated_path=$(doctor_command_path "$migrated_tool") && doctor_nix_owned_path "$migrated_path"; then
    doctor_status "owner-$migrated_tool" PASS "$migrated_path należy do profilu Nix"
  else
    doctor_status "owner-$migrated_tool" FAIL "${migrated_path:-absent} nie należy do profilu Nix" "Usuń poprzedniego ownera wyłącznie zatwierdzoną migracją Homebrew"
  fi
done

if herdr_path=$(doctor_command_path herdr) && herdr_json=$($herdr_path status --json 2>/dev/null); then
  herdr_summary=$(printf '%s' "$herdr_json" | python3 -c '
import json, sys
s = json.load(sys.stdin).get("server") or {}
ok = (not s.get("running")) or (
    tuple(map(int, str(s.get("version", "0.0.0")).split(".")[:3])) >= (0, 8, 0)
    and int(s.get("protocol", 0)) >= 16
    and s.get("compatible") is True
    and s.get("restart_needed") is False)
print("{}|running={} version={} protocol={} compatible={} restart_needed={}".format(
    "PASS" if ok else "FAIL", str(s.get("running", False)).lower(),
    s.get("version", "unknown"), s.get("protocol", "unknown"),
    str(s.get("compatible", False)).lower(), str(s.get("restart_needed", False)).lower()))
' 2>/dev/null || printf 'FAIL|nie można sparsować statusu')
  herdr_result=${herdr_summary%%|*}
  herdr_message=${herdr_summary#*|}
  if printf '%s' "$herdr_message" | grep -q 'running=false'; then
    doctor_status herdr-server MANUAL "$herdr_message" "Uruchom Herdr ręcznie przed runtime smoke"
  else
    doctor_status herdr-server "$herdr_result" "$herdr_message" "Zrestartuj kompatybilny Herdr przed uruchomieniem taska"
  fi
else
  doctor_status herdr-server MANUAL "serwer Herdr nie raportuje statusu" "Uruchom Herdr ręcznie przed runtime smoke"
fi

firstmate_launcher=$(doctor_command_path firstmate-pi || true)
if [ -n "$firstmate_launcher" ] && doctor_nix_owned_path "$firstmate_launcher"; then
  launcher_root=$(sed -n 's/^[[:space:]]*fm_root=\([^[:space:]]*\)$/\1/p' "$firstmate_launcher" | head -1)
  launcher_mcp=$(sed -n 's/^[[:space:]]*export CHROME_DEVTOOLS_AXI_MCP_PATH=\([^[:space:]]*\)$/\1/p' "$firstmate_launcher" | head -1)
  launcher_runtime_path=$(sed -n 's/^export PATH="\(.*\):\$PATH"$/\1/p' "$firstmate_launcher" | head -1)
  if [ -d "$launcher_root" ] && [ -f "$launcher_root/.pi/extensions/fm-calm.ts" ] && \
    [ -f "$launcher_root/.pi/extensions/fm-primary-turnend-guard.ts" ] && \
    [ -f "$launcher_root/.pi/extensions/fm-primary-pi-watch.ts" ]; then
    doctor_status fm-root PASS "$launcher_root z trzema przypiętymi rozszerzeniami"
  else
    doctor_status fm-root FAIL "launcher nie wskazuje kompletnego immutable root" "Przebuduj packages/agents/default.nix"
  fi
  case $launcher_mcp in
    /nix/store/*/lib/chrome-devtools-mcp/build/src/bin/chrome-devtools-mcp.js)
      if [ -f "$launcher_mcp" ]; then
        doctor_status fm-mcp PASS "$launcher_mcp"
      else
        doctor_status fm-mcp FAIL "przypięty MCP nie istnieje" "Przebuduj chrome-devtools-mcp"
      fi
      ;;
    *) doctor_status fm-mcp FAIL "launcher nie ma przypiętego MCP" "Nie używaj fallbacku @latest" ;;
  esac

  fm_doctor_tmp=$(mktemp -d "${TMPDIR:-/tmp}/firstmate-doctor.XXXXXX")
  if HOME="$fm_doctor_tmp/user" XDG_DATA_HOME="$fm_doctor_tmp/data" PI_OFFLINE=1 \
    "$firstmate_launcher" --list-models >/dev/null 2>&1; then
    doctor_status fm-pi-load PASS "offline allowlista rozszerzeń Pi ładuje się poprawnie"
  else
    doctor_status fm-pi-load FAIL "offline load rozszerzeń Pi nie przeszedł" "Uruchom tests/firstmate-toolchain-fixture.sh"
  fi
  if [ -n "$launcher_runtime_path" ] && \
    bootstrap_output=$(HOME="$fm_doctor_tmp/user" FM_HOME="$fm_doctor_tmp/home" \
      FM_ROOT_OVERRIDE="$launcher_root" FM_BACKEND=herdr FM_BOOTSTRAP_DETECT_ONLY=1 \
      FM_BOOTSTRAP_NETWORK=skip PATH="$launcher_runtime_path:/usr/bin:/bin" \
      "$launcher_root/bin/fm-bootstrap.sh" 2>&1) && \
    ! printf '%s\n' "$bootstrap_output" | grep -q '^MISSING'; then
    doctor_status fm-bootstrap PASS "detect-only nie raportuje MISSING"
  else
    doctor_status fm-bootstrap FAIL "detect-only nie przeszedł" "Sprawdź closure PATH i minima toolchainu"
  fi
  rm -Rf "$fm_doctor_tmp"
else
  doctor_status firstmate FAIL "firstmate-pi nie należy do aktywnego profilu Nix" "Aktywuj konfigurację po zatwierdzonym preview"
fi

firstmate_home=${FM_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/firstmate}
if [ -L "$firstmate_home" ]; then
  firstmate_resolved=$(python3 - "$firstmate_home" <<'PY' 2>/dev/null || true
import os
import sys
print(os.path.realpath(sys.argv[1]))
PY
  )
  case $firstmate_resolved in
    /nix/store/*) doctor_status fm-home FAIL "$firstmate_home wskazuje do Nix store" "Przenieś stan dopiero po osobnej zgodzie" ;;
    *) doctor_status fm-home MANUAL "$firstmate_home jest symlinkiem" "Potwierdź prywatnego ownera i zapisywalny target" ;;
  esac
elif [ -d "$firstmate_home" ] && [ -w "$firstmate_home" ]; then
  doctor_status fm-home PASS "$firstmate_home jest lokalny i zapisywalny"
elif [ ! -e "$firstmate_home" ]; then
  doctor_status fm-home MANUAL "$firstmate_home jeszcze nie istnieje" "Pierwszy świadomy start firstmate-pi utworzy prywatny home"
else
  doctor_status fm-home FAIL "$firstmate_home nie jest bezpiecznym zapisywalnym katalogiem" "Nie naprawiaj ani nie usuwaj automatycznie"
fi

if gh_path=$(doctor_command_path gh) && $gh_path auth status --active >/dev/null 2>&1; then
  doctor_status gh-auth PASS "aktywne lokalne uwierzytelnienie gh"
else
  doctor_status gh-auth MANUAL "brak aktywnego auth gh" "Zaloguj się lokalnie przed projektem remote-backed"
fi

if jdk17_home=$(/usr/libexec/java_home -v 17 2>/dev/null) &&
  [ -x "$jdk17_home/bin/java" ] && printf '%s' "$jdk17_home" | grep -qi zulu; then
  doctor_status jdk17 PASS "$jdk17_home"
else
  doctor_status jdk17 FAIL "Zulu JDK 17 jest niedostępny" "Sprawdź cask zulu@17 i /usr/libexec/java_home -v 17"
fi

if [ -n "$brew_path" ] && jdk21_prefix=$("$brew_path" --prefix openjdk@21 2>/dev/null) &&
  [ -x "$jdk21_prefix/bin/java" ]; then
  doctor_status jdk21 PASS "$jdk21_prefix/bin/java"
else
  doctor_status jdk21 FAIL "openjdk@21 jest niedostępny" "Sprawdź brew --prefix openjdk@21"
fi

service_state=$(launchctl print "gui/$(id -u)" 2>/dev/null || true)
if printf '%s\n' "$service_state" | grep -Eq 'docker-mac-net-connect|herdr'; then
  doctor_status autostart FAIL "Herdr albo docker-mac-net-connect ma wpis launchd" "Usuń autostart; oba narzędzia mają być uruchamiane ręcznie"
else
  doctor_status autostart PASS "brak launchd dla Herdr i docker-mac-net-connect"
fi

if shell_migration_login_is_clean && shell_state=$(/bin/zsh -lic '
  command -v pyenv >/dev/null 2>&1 && exit 1
  [ -n "$NVM_DIR" ] || exit 2
  [ -n "$JAVA_HOME" ] || exit 3
  [ -n "$ANDROID_HOME" ] || exit 4
  command -v dotnet >/dev/null 2>&1 || exit 5
  printf "NVM,JAVA_HOME,ANDROID_HOME,dotnet; bez pyenv"
' 2>/dev/null); then
  doctor_status shell PASS "$shell_state"
else
  doctor_status shell FAIL "login Zsh ma pyenv albo utracił wymagane środowisko" "Sprawdź wyłącznie blok pyenv oraz NVM, JAVA_HOME, ANDROID_HOME i .NET"
fi

nix_user_path_file=/etc/paths.d/50-nix-user
expected_nix_user_path="/etc/profiles/per-user/$DOTFILES_SUPPORTED_USER/bin"
if [ -f "$nix_user_path_file" ] && [ ! -L "$nix_user_path_file" ] &&
  [ "$(sed -n '1p' "$nix_user_path_file")" = "$expected_nix_user_path" ]; then
  doctor_status nix-user-path PASS "$nix_user_path_file jest zwykłym plikiem dla path_helper"
else
  doctor_status nix-user-path FAIL "path_helper nie widzi profilu użytkownika Nix" "Wykonaj check i switch"
fi

wezterm_config="$HOME/.config/wezterm/wezterm.lua"
if [ -L "$wezterm_config" ] && [ -f "$wezterm_config" ] &&
  grep -Fq 'config.color_scheme = "rose-pine-moon"' "$wezterm_config" &&
  grep -Fq 'config.font = wezterm.font("JetBrainsMono Nerd Font")' "$wezterm_config"; then
  doctor_status wezterm PASS "$wezterm_config jest zarządzany przez Home Manager"
else
  doctor_status wezterm FAIL "brak aktywnego zarządzanego configu" "Wykonaj check i switch"
fi

nvim_init="$HOME/.config/nvim/init.lua"
nvim_lock="$HOME/.config/nvim/lazy-lock.json"
if [ -L "$nvim_init" ] && [ -f "$nvim_init" ] && [ -L "$nvim_lock" ] && [ -f "$nvim_lock" ]; then
  doctor_status neovim PASS "$nvim_init i lazy-lock.json są zarządzane przez Home Manager"
  doctor_status nvim-plugins MANUAL "Pierwszy start pobierze przypięte pluginy lazy.nvim" "Uruchom nvim przy dostępie do internetu i sprawdź :Lazy"
else
  doctor_status neovim FAIL "brak aktywnego zarządzanego configu" "Wykonaj check i switch"
fi

doctor_status logowania MANUAL "Brak logowania nie jest błędem fundamentu" "Wykonaj ręczne kroki z docs/manual-login-checklist.md"

if [ "$critical_fail" -ne 0 ]; then
  exit "$DOTFILES_EXIT_ERROR"
fi
