#!/bin/bash
set -Eeuo pipefail
umask 077

test_dir="$(cd "$(dirname "$0")" && pwd -P)"
repo_root="$(cd "$test_dir/.." && pwd -P)"

# shellcheck source=scripts/lib/common.bash
. "$repo_root/scripts/lib/common.bash"
# shellcheck source=scripts/lib/homebrew-plan.bash
. "$repo_root/scripts/lib/homebrew-plan.bash"

fixture_root=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-homebrew-plan.XXXXXX")
HOME="$fixture_root/home"
XDG_STATE_HOME="$fixture_root/state"
export HOME XDG_STATE_HOME
mkdir -p "$HOME"

cleanup_fixture() {
  case "$fixture_root" in
    "${TMPDIR:-/tmp}"/dotfiles-homebrew-plan.*) /bin/rm -R "$fixture_root" ;;
    *) printf 'REFUSE cleanup outside fixture root: %s\n' "$fixture_root" >&2 ;;
  esac
}
trap cleanup_fixture EXIT HUP INT TERM

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_eq() {
  local expected=$1
  local actual=$2
  local message=$3
  [ "$expected" = "$actual" ] ||
    fail "$message (expected=$expected actual=$actual)"
}

# Bundle cleanup codes have a deliberately narrow contract.
assert_eq no-removals "$(homebrew_cleanup_classify 0)" 'cleanup code 0'
assert_eq removals "$(homebrew_cleanup_classify 1)" 'cleanup code 1'
if homebrew_cleanup_classify 2 >/dev/null; then
  fail 'cleanup code 2 was accepted'
fi

# Stable set comparison emits exact KEEP/INSTALL/REMOVE records by kind.
desired="$fixture_root/desired.tsv"
actual="$fixture_root/actual.tsv"
plan="$fixture_root/plan.tsv"
printf '%s\n' \
  $'formula\tgo' \
  $'formula\tgh' \
  $'formula\tchipmk/tap/docker-mac-net-connect' \
  $'cask\twezterm' \
  $'tap\tchipmk/tap' > "$desired"
printf '%s\n' \
  $'formula\tgo' \
  $'formula\tpyenv' \
  $'cask\tghostty' \
  $'tap\thomebrew/core' > "$actual"
homebrew_plan_normalize "$desired" "$actual" > "$plan"
expected_plan='INSTALL	cask	wezterm
INSTALL	formula	chipmk/tap/docker-mac-net-connect
INSTALL	formula	gh
INSTALL	tap	chipmk/tap
KEEP	formula	go
REMOVE	cask	ghostty
REMOVE	formula	pyenv
REMOVE	tap	homebrew/core'
assert_eq "$(printf '%b' "$expected_plan")" "$(sed -n '1,$p' "$plan")" 'normalized plan'
expected_formulae='chipmk/tap/docker-mac-net-connect
gh
go'
assert_eq "$expected_formulae" "$(homebrew_inventory_names "$desired" formula)" 'declared formula names'
plan_hash=$(homebrew_plan_hash "$plan")
[ "${#plan_hash}" -eq 64 ] || fail 'plan hash is not SHA-256'
printf '%s\n' $'formula\tnew-drift' >> "$actual"
drifted="$fixture_root/drifted.tsv"
homebrew_plan_normalize "$desired" "$actual" > "$drifted"
if homebrew_hashes_match lock lock declaration declaration brewfile brewfile "$plan_hash" "$(homebrew_plan_hash "$drifted")"; then
  fail 'activation plan drift was accepted'
fi
if homebrew_hashes_match lock lock declaration changed brewfile brewfile "$plan_hash" "$plan_hash"; then
  fail 'declaration drift was accepted'
fi
homebrew_hashes_match lock lock declaration declaration brewfile brewfile "$plan_hash" "$plan_hash" ||
  fail 'matching four hashes were rejected'

# The Firstmate owner migration is deliberately narrow: only gh and herdr move
# out of Homebrew, while every unrelated declared formula remains present.
migration_desired="$fixture_root/migration-desired.tsv"
migration_actual="$fixture_root/migration-actual.tsv"
migration_plan="$fixture_root/migration-plan.tsv"
printf '%s\n' \
  $'formula\tgo' \
  $'formula\topenjdk@21' \
  $'formula\tchipmk/tap/docker-mac-net-connect' > "$migration_desired"
printf '%s\n' \
  $'formula\tgo' \
  $'formula\tgh' \
  $'formula\therdr' \
  $'formula\topenjdk@21' \
  $'formula\tchipmk/tap/docker-mac-net-connect' > "$migration_actual"
homebrew_plan_normalize "$migration_desired" "$migration_actual" > "$migration_plan"
migration_removals=$(awk -F '\t' '$1 == "REMOVE" { print $2 "\t" $3 }' "$migration_plan")
assert_eq "$(printf '%s\n' $'formula\tgh' $'formula\therdr')" "$migration_removals" \
  'Firstmate migration removal set'
if grep -Eq $'^REMOVE\t(formula|cask|tap)\t(go|openjdk@21|chipmk/tap/docker-mac-net-connect)$' "$migration_plan"; then
  fail 'Firstmate migration removes an unrelated Homebrew item'
fi

brewfile="$XDG_STATE_HOME/dotfiles/plans/Brewfile"
printf '%s\n' 'tap "chipmk/tap"' 'brew "go"' | homebrew_brewfile_write "$brewfile"
assert_eq 600 "$(stat -f '%Lp' "$brewfile")" 'private Brewfile mode'
assert_eq "$(printf '%s\n' 'tap "chipmk/tap"' 'brew "go"')" "$(sed -n '1,$p' "$brewfile")" 'private Brewfile content'

fake_brew="$fixture_root/fake-brew"
# The fake executable must receive literal positional-parameter expressions.
# shellcheck disable=SC2016
printf '%s\n' \
  '#!/bin/bash' \
  'if [ "$1 $2" = "bundle check" ]; then printf "missing gh\\n"; exit 1; fi' \
  'if [ "$1 $2" = "bundle cleanup" ]; then printf "Would uninstall formulae:\\npyenv\\ndependency-x\\nWould untap:\\nold/tap\\n"; exit 1; fi' \
  'if [ "$1" = leaves ]; then printf "go\\npyenv\\n"; exit 0; fi' \
  'if [ "$1 $2" = "list --cask" ]; then printf "ghostty\\n"; exit 0; fi' \
  'if [ "$1" = tap ]; then printf "homebrew/core\\n"; exit 0; fi' \
  'exit 2' > "$fake_brew"
chmod +x "$fake_brew"
preview_dir="$XDG_STATE_HOME/dotfiles/previews/run"
preview="$preview_dir/activation-plan.tsv"
HOMEBREW_BREW_COMMAND="$fake_brew"
export HOMEBREW_BREW_COMMAND
homebrew_preview_create "$brewfile" "$desired" "$preview" "$preview_dir"
grep -q $'^CHECK_RC\t1$' "$preview" || fail 'Bundle check code missing from preview'
grep -q $'^CLEANUP_RC\t1$' "$preview" || fail 'Bundle cleanup code missing from preview'
grep -q $'^REMOVE\tformula\tdependency-x$' "$preview" || fail 'orphaned formula missing from REMOVE'
grep -q $'^REMOVE\ttap\told/tap$' "$preview" || fail 'Bundle tap missing from REMOVE'
homebrew_plan_requires_cleanup "$preview" || fail 'preview removals were not detected'

# Ticket records all four hashes, expires, rejects symlinks/wrong data and is one-shot.
ticket_dir="$XDG_STATE_HOME/dotfiles/tickets"
ticket="$ticket_dir/activation.ticket"
now=$(date +%s)
expires=$((now + 120))
homebrew_ticket_write "$ticket" run-1 ZAP lock-hash declaration-hash brewfile-hash plan-hash "$expires"
[ "$(stat -f '%Lp' "$ticket")" = 600 ] || fail 'ticket mode is not 0600'
grep -q '^lockHash=lock-hash$' "$ticket" || fail 'lock hash absent from ticket'
grep -q '^declarationHash=declaration-hash$' "$ticket" || fail 'declaration hash absent from ticket'
grep -q '^brewfileHash=brewfile-hash$' "$ticket" || fail 'brewfile hash absent from ticket'
grep -q '^activationPlanHash=plan-hash$' "$ticket" || fail 'plan hash absent from ticket'
homebrew_ticket_validate "$ticket" "$(id -un)" ZAP lock-hash declaration-hash brewfile-hash plan-hash "$now" ||
  fail 'valid ticket rejected'

wrong="$ticket_dir/wrong.ticket"
homebrew_ticket_write "$wrong" run-2 ZAP lock-hash declaration-hash brewfile-hash wrong-plan "$expires"
if homebrew_ticket_validate "$wrong" "$(id -un)" ZAP lock-hash declaration-hash brewfile-hash plan-hash "$now"; then
  fail 'wrong ticket hash accepted'
fi

expired="$ticket_dir/expired.ticket"
homebrew_ticket_write "$expired" run-3 ZAP lock-hash declaration-hash brewfile-hash plan-hash "$((now - 1))"
if homebrew_ticket_validate "$expired" "$(id -un)" ZAP lock-hash declaration-hash brewfile-hash plan-hash "$now"; then
  fail 'expired ticket accepted'
fi

link="$ticket_dir/link.ticket"
ln -s "$ticket" "$link"
if homebrew_ticket_validate "$link" "$(id -un)" ZAP lock-hash declaration-hash brewfile-hash plan-hash "$now"; then
  fail 'symlink ticket accepted'
fi

missing="$ticket_dir/missing.ticket"
if homebrew_ticket_validate "$missing" "$(id -un)" ZAP lock-hash declaration-hash brewfile-hash plan-hash "$now"; then
  fail 'missing ticket accepted'
fi

homebrew_ticket_consume "$ticket" "$(id -un)" ZAP lock-hash declaration-hash brewfile-hash plan-hash "$now" ||
  fail 'valid ticket was not consumed'
[ ! -e "$ticket" ] || fail 'consumed ticket remains on disk'
if homebrew_ticket_consume "$ticket" "$(id -un)" ZAP lock-hash declaration-hash brewfile-hash plan-hash "$now"; then
  fail 'ticket was reusable'
fi

printf 'PASS: homebrew plan fixture\n'
