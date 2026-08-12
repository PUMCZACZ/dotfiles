#!/bin/bash
set -Eeuo pipefail
umask 077

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
export DOTFILES_USER=${DOTFILES_USER:-$(id -un)}
export DOTFILES_HOME=${DOTFILES_HOME:-$HOME}
fixture_root=$(mktemp -d "${TMPDIR:-/tmp}/firstmate-toolchain.XXXXXX")

cleanup() {
  case "$fixture_root" in
    "${TMPDIR:-/tmp}"/firstmate-toolchain.*) /bin/rm -Rf "$fixture_root" ;;
    *) printf 'REFUSE cleanup outside fixture root: %s\n' "$fixture_root" >&2 ;;
  esac
}
trap cleanup EXIT HUP INT TERM

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

# Nix excludes untracked files from a Git-backed path flake. This repository is
# intentionally not staged by the fixture, so an untracked initial checkout is
# evaluated through a private non-Git snapshot.
flake_root=$repo_root
if ! git -C "$repo_root" ls-files --error-unmatch flake.nix >/dev/null 2>&1; then
  flake_root="$fixture_root/source"
  mkdir -p "$flake_root"
  COPYFILE_DISABLE=1 tar -C "$repo_root" --exclude=.git -cf - . | tar -C "$flake_root" -xf -
fi
flake_ref="path:$flake_root"

build_package() {
  nix build --impure --no-link --print-out-paths \
    --no-update-lock-file --no-write-lock-file \
    "$flake_ref#$1"
}

expected='pi-coding-agent	0.84.1
firstmate-snapshot	76355e20b4f44d968ca43c14e1bb21c100ac90d7
herdr	0.8.0
treehouse	2.1.1
no-mistakes	1.46.0
gh-axi	0.1.30
chrome-devtools-axi	0.1.29
lavish-axi	0.1.50
tasks-axi	0.2.5
quota-axi	0.1.21
chrome-devtools-mcp	1.7.0
firstmate-pi	76355e20b4f44d968ca43c14e1bb21c100ac90d7'

inventory=$(nix eval --impure --raw --no-update-lock-file --no-write-lock-file --expr '
  let
    flake = builtins.getFlake "'"$flake_ref"'";
    profileUser = builtins.getEnv "DOTFILES_USER";
  in
    flake.darwinConfigurations.macos.config.home-manager.users.${profileUser}.dotfiles.firstmate.desiredInventory
') || fail 'declarative Firstmate inventory is unavailable'
[ "$inventory" = "$expected" ] || fail 'declarative Firstmate inventory differs from the pinned contract'

for source_file in \
  "$flake_root/packages/agents/default.nix" \
  "$flake_root/packages/agents/mk-pnpm-cli.nix" \
  "$flake_root/modules/home/agents.nix"; do
  [ -f "$source_file" ] || fail "missing source file: $source_file"
done

if grep -E '(refs/heads/|@latest|/latest/|npx[[:space:]]+-y|npm[[:space:]]+install[[:space:]]+-g)' \
  "$flake_root/packages/agents/default.nix" "$flake_root/packages/agents/mk-pnpm-cli.nix"; then
  fail 'mutable source or runtime installer found in managed package definitions'
fi

grep -Fq 'CHROME_DEVTOOLS_AXI_MCP_PATH' "$flake_root/packages/agents/default.nix" \
  || fail 'pinned browser MCP path is absent from launcher'
grep -Fq 'fm-calm.ts' "$flake_root/packages/agents/default.nix" \
  || fail 'Firstmate Calm extension is absent from launcher allowlist'
grep -Fq 'fm-primary-turnend-guard.ts' "$flake_root/packages/agents/default.nix" \
  || fail 'Firstmate turn-end guard is absent from launcher allowlist'
grep -Fq 'fm-primary-pi-watch.ts' "$flake_root/packages/agents/default.nix" \
  || fail 'Firstmate watcher is absent from launcher allowlist'

for attr in pi firstmate herdr treehouse no-mistakes gh-axi chrome-devtools-axi lavish-axi tasks-axi quota-axi chrome-devtools-mcp firstmate-pi; do
  out=$(build_package "$attr") || fail "package failed to build: $attr"
  [ -d "$out" ] || fail "package output is not a directory: $attr"
done

firstmate_path=$(build_package firstmate)
for extension in fm-calm.ts fm-primary-turnend-guard.ts fm-primary-pi-watch.ts; do
  [ -f "$firstmate_path/share/firstmate/.pi/extensions/$extension" ] \
    || fail "Firstmate extension missing: $extension"
done
[ ! -w "$firstmate_path/share/firstmate" ] || fail 'Firstmate root is writable'

launcher_path=$(build_package firstmate-pi)
private_home="$fixture_root/home-a"
mkdir -p "$private_home"
launcher_output=$(HOME="$fixture_root/user" XDG_DATA_HOME="$fixture_root/data" FM_HOME="$private_home" \
  PI_OFFLINE=1 "$launcher_path/bin/firstmate-pi" --list-models 2>&1) \
  || fail "offline launcher smoke failed: $launcher_output"
[ -d "$private_home" ] || fail 'launcher did not preserve the external FM_HOME'

runtime_path=$(sed -n 's/^export PATH="\(.*\):\$PATH"$/\1/p' "$launcher_path/bin/firstmate-pi")
[ -n "$runtime_path" ] || fail 'launcher does not expose a pinned closure PATH'
bootstrap_output=$(HOME="$fixture_root/user" FM_HOME="$private_home" \
  FM_ROOT_OVERRIDE="$firstmate_path/share/firstmate" FM_BACKEND=herdr \
  FM_BOOTSTRAP_DETECT_ONLY=1 FM_BOOTSTRAP_NETWORK=skip \
  PATH="$runtime_path:/usr/bin:/bin" \
  "$firstmate_path/share/firstmate/bin/fm-bootstrap.sh" 2>&1) \
  || fail "Firstmate detect-only bootstrap failed: $bootstrap_output"
if printf '%s\n' "$bootstrap_output" | grep -q '^MISSING'; then
  fail "Firstmate detect-only bootstrap reported a missing tool: $bootstrap_output"
fi

printf 'PASS: pinned Firstmate toolchain builds and runs from immutable sources\n'
