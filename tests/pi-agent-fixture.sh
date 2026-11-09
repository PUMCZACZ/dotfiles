#!/bin/bash
# shellcheck disable=SC2016 # Nix expressions intentionally splice shell values between quoted segments.
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
[ "$pi_version" = "1.5.0" ] || fail "oczekiwano Pi 1.5.0, otrzymano: $pi_version"

codex_path=$(nix build --impure --no-link --print-out-paths \
  --no-update-lock-file --no-write-lock-file \
  --expr '
    let
      flake = builtins.getFlake "path:'"$repo_root"'";
      profileUser = builtins.getEnv "DOTFILES_USER";
      packages = flake.darwinConfigurations.macos.config.home-manager.users.${profileUser}.home.packages;
      matches = builtins.filter (package: (package.pname or "") == "codex") packages;
    in
      if builtins.length matches == 1
      then builtins.head matches
      else throw "Home Manager must declare exactly one codex package"
  ') || fail "Home Manager nie udostępnia dokładnie jednego pakietu codex"
codex_version=$("$codex_path/bin/codex" --version) || fail "codex --version zakończyło się błędem"
[ "$codex_version" = "codex-cli 0.167.0" ] || fail "oczekiwano Codex 0.167.0, otrzymano: $codex_version"

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

if nix eval --impure --json --no-update-lock-file --no-write-lock-file \
  --expr '
    let
      flake = builtins.getFlake "path:'"$repo_root"'";
      profileUser = builtins.getEnv "DOTFILES_USER";
      files = flake.darwinConfigurations.macos.config.home-manager.users.${profileUser}.home.file;
    in
      builtins.hasAttr ".pi/agent/extensions/auto-compaction.ts" files
  ' | grep -q true; then
  fail "Home Manager still registers the replaced auto-compaction extension"
fi

observational_memory=$(nix build --impure --no-link --print-out-paths \
  --no-update-lock-file --no-write-lock-file \
  --expr '
    let
      flake = builtins.getFlake "path:'"$repo_root"'";
      pkgs = flake.darwinConfigurations.macos.pkgs;
    in
      (import '"$repo_root"'/packages/agents { inherit pkgs; }).observationalMemory
  ') || fail "Cannot build pinned observational-memory package"
observational_memory_path="$observational_memory/share/pi-observational-memory"
managed_observational_memory_path=$(nix eval --impure --raw --no-update-lock-file --no-write-lock-file \
  --expr '
    let
      flake = builtins.getFlake "path:'"$repo_root"'";
      profileUser = builtins.getEnv "DOTFILES_USER";
    in
      toString flake.darwinConfigurations.macos.config.home-manager.users.${profileUser}.home.file.".pi/agent/extensions/observational-memory".source
  ') || fail "Home Manager does not register observational-memory"
[ "$managed_observational_memory_path" = "$observational_memory_path" ] \
  || fail "Home Manager does not point at the pinned observational-memory package"
[ -f "$observational_memory_path/index.ts" ] || fail "observational-memory root entrypoint is missing"
[ -f "$observational_memory_path/src/spawn/launch.ts" ] || fail "observational-memory spawn layout is missing"
[ "$(grep -c 'provider: "openai-codex", id: "gpt-6.1-sol", thinking: "low"' "$observational_memory_path/src/config.ts")" -eq 2 ] \
  || fail "observational-memory observer and consolidator must default to GPT-6.1 Sol / low"

om_rpc=$(printf '%s\n' '{"type":"get_commands"}' | PI_OFFLINE=1 "$pi_path/bin/pi" \
  --no-extensions --extension "$observational_memory_path/index.ts" \
  --no-skills --no-prompt-templates --no-themes --no-context-files \
  --mode rpc --no-session) || fail "Pi cannot load observational-memory in RPC mode"
printf '%s\n' "$om_rpc" | grep -Fq '"name":"om"' \
  || fail "observational-memory did not register /om"
printf '%s\n' "$om_rpc" | grep -Fq '"name":"om:status"' \
  || fail "observational-memory did not register /om:status"

python3 - "$pi_path/bin/pi" "$observational_memory_path/index.ts" <<'PY' || fail "observational-memory session gate RPC integration failed"
import json
import os
import subprocess
import sys
import tempfile

pi, extension = sys.argv[1:]
with tempfile.TemporaryDirectory(prefix="pi-om-gate.") as fixture:
    env = dict(os.environ, HOME=fixture, XDG_DATA_HOME=os.path.join(fixture, "data"), PI_OFFLINE="1")
    process = subprocess.Popen(
        [pi, "--no-extensions", "--extension", extension, "--no-skills", "--no-prompt-templates",
         "--no-themes", "--no-context-files", "--mode", "rpc", "--session-dir", os.path.join(fixture, "sessions")],
        cwd=fixture, env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True,
    )
    def command(request_id, kind, **fields):
        process.stdin.write(json.dumps(dict(id=request_id, type=kind, **fields)) + "\n")
        process.stdin.flush()
        while True:
            line = process.stdout.readline()
            if not line:
                raise RuntimeError("Pi RPC exited before response")
            record = json.loads(line)
            if record.get("id") == request_id and record.get("type") == "response":
                if not record.get("success"):
                    raise RuntimeError(record)
                return record
    def gate():
        entries = command("entries", "get_entries")["data"]["entries"]
        markers = [entry for entry in entries if entry.get("customType") == "om.enabled"]
        if not markers:
            raise RuntimeError("missing persisted OM gate marker")
        return markers[-1].get("data", {}).get("enabled")
    try:
        if gate() is not True:
            raise RuntimeError("empty startup session did not persist OM enabled")
        command("status", "prompt", message="/om:status")
        command("off", "prompt", message="/om off")
        if gate() is not False:
            raise RuntimeError("/om off did not persist disabled state")
        command("new", "new_session")
        if gate() is not True:
            raise RuntimeError("/new did not enable and persist OM")
    finally:
        process.stdin.close()
        process.wait(timeout=15)
PY

herdr_extension=$(nix build --impure --no-link --print-out-paths \
  --no-update-lock-file --no-write-lock-file \
  --expr '
    let
      flake = builtins.getFlake "path:'"$repo_root"'";
      pkgs = flake.darwinConfigurations.macos.pkgs;
    in
      (import '"$repo_root"'/packages/agents { inherit pkgs; }).interactiveSubagents
  ') || fail "Nie można zbudować portu subagentów Herdr"
herdr_extension_path="$herdr_extension/share/pi-herdr-interactive-subagents/pi-extension/subagents"
for role in scout researcher worker; do
  grep -Fxq 'model: openai-codex/gpt-6.1-sol' "$herdr_extension_path/agents/$role.md" \
    || fail "$role must default to GPT-6.1 Sol"
  grep -Fxq 'thinking: low' "$herdr_extension_path/agents/$role.md" \
    || fail "$role must default to low reasoning"
done
managed_herdr_extension_path=$(nix eval --impure --raw --no-update-lock-file --no-write-lock-file \
  --expr '
    let
      flake = builtins.getFlake "path:'"$repo_root"'";
      profileUser = builtins.getEnv "DOTFILES_USER";
    in
      toString flake.darwinConfigurations.macos.config.home-manager.users.${profileUser}.home.file.".pi/agent/extensions/herdr-interactive-subagents".source
  ') || fail "Home Manager nie udostępnia rozszerzenia Herdr"
[ "$managed_herdr_extension_path" = "$herdr_extension_path" ] \
  || fail "Home Manager nie wskazuje przypiętej wersji rozszerzenia Herdr"
herdr_rpc=$(printf '%s\n' '{"type":"get_commands"}' | PI_OFFLINE=1 "$pi_path/bin/pi" \
  --no-extensions --extension "$herdr_extension_path/index.ts" \
  --no-skills --no-prompt-templates --no-themes --no-context-files \
  --mode rpc --no-session) || fail "PI nie ładuje portu Herdr w trybie RPC"
printf '%s\n' "$herdr_rpc" | grep -Fq '"name":"herdr-subagent"' \
  || fail "PI nie rejestruje komendy interaktywnych subagentów Herdr"

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
