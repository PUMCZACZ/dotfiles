#!/bin/bash
set -Eeuo pipefail
umask 077

test_dir="$(cd "$(dirname "$0")" && pwd -P)"
repo_root="$(cd "$test_dir/.." && pwd -P)"

# shellcheck source=scripts/lib/common.bash
. "$repo_root/scripts/lib/common.bash"
# shellcheck source=scripts/lib/shell-migration.bash
. "$repo_root/scripts/lib/shell-migration.bash"

fixture_root=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-shell-migration.XXXXXX")

cleanup_fixture() {
  case "$fixture_root" in
    "${TMPDIR:-/tmp}"/dotfiles-shell-migration.*) /bin/rm -R "$fixture_root" ;;
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

assert_content() {
  local path=$1
  local expected=$2
  assert_eq "$expected" "$(sed -n '1,$p' "$path")" "unexpected content: $path"
}

prepare_case() {
  case_name=$1
  HOME="$fixture_root/$case_name/home"
  XDG_STATE_HOME="$fixture_root/$case_name/state"
  export HOME XDG_STATE_HOME
  mkdir -p "$HOME"
  target="$HOME/.zshrc"
  backup_dir="$XDG_STATE_HOME/dotfiles/backups/run"
}

# The fixture must contain literal shell expressions, not expand them here.
# shellcheck disable=SC2016
pyenv_block='# pyenv
export PYENV_ROOT="$HOME/.pyenv"
[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"'

# One exact block is removed, while every foreign line remains byte-for-byte.
prepare_case exact
printf 'before\n%s\nafter\n' "$pyenv_block" > "$target"
assert_eq exact "$(shell_migration_classify "$target")" 'exact classification'
original_hash=$(dotfiles_hash_file "$target")
shell_migration_apply "$target" "$backup_dir" false
assert_content "$target" 'before
after'
assert_content "$SHELL_MIGRATION_BACKUP_PATH" "before
$pyenv_block
after"
assert_eq "$original_hash" "$SHELL_MIGRATION_ORIGINAL_HASH" 'original hash'
assert_eq "$(dotfiles_hash_file "$target")" "$SHELL_MIGRATION_CANDIDATE_HASH" 'candidate hash'
[ "$(stat -f '%Lp' "$SHELL_MIGRATION_BACKUP_PATH")" = 600 ] || fail 'backup mode is not 0600'
[ "$(stat -f '%Lp' "$SHELL_MIGRATION_MANIFEST")" = 600 ] || fail 'manifest mode is not 0600'

# Applying the migration again is an idempotent no-op.
after_first_hash=$(dotfiles_hash_file "$target")
shell_migration_apply "$target" "$backup_dir" false
assert_eq absent "$SHELL_MIGRATION_STATUS" 'second apply status'
assert_eq "$after_first_hash" "$(dotfiles_hash_file "$target")" 'second apply changed target'

# Dry-run classifies but writes neither target nor backup.
prepare_case dry_run
printf 'keep\n%s\n' "$pyenv_block" > "$target"
dry_hash=$(dotfiles_hash_file "$target")
shell_migration_apply "$target" "$backup_dir" true
assert_eq classified "$SHELL_MIGRATION_STATUS" 'dry-run status'
assert_eq "$dry_hash" "$(dotfiles_hash_file "$target")" 'dry-run changed target'
[ ! -e "$backup_dir" ] || fail 'dry-run created backup'

# Modified and duplicate pyenv blocks are refused without writes.
prepare_case modified
# shellcheck disable=SC2016
printf '%s\n' '# pyenv' 'export PYENV_ROOT="$HOME/.different-pyenv"' 'eval "$(pyenv init -)"' > "$target"
assert_eq modified "$(shell_migration_classify "$target")" 'modified classification'
modified_hash=$(dotfiles_hash_file "$target")
if shell_migration_apply "$target" "$backup_dir" false; then
  fail 'modified block was accepted'
fi
assert_eq "$modified_hash" "$(dotfiles_hash_file "$target")" 'modified target changed'
[ ! -e "$backup_dir" ] || fail 'modified block created backup'

prepare_case duplicate
printf '%s\n%s\n' "$pyenv_block" "$pyenv_block" > "$target"
assert_eq duplicate "$(shell_migration_classify "$target")" 'duplicate classification'
if shell_migration_apply "$target" "$backup_dir" false; then
  fail 'duplicate block was accepted'
fi
[ ! -e "$backup_dir" ] || fail 'duplicate block created backup'

# An absent file or absent markers are safe and do not create artifacts.
prepare_case absent_file
assert_eq absent "$(shell_migration_classify "$target")" 'absent file classification'
shell_migration_apply "$target" "$backup_dir" false
[ ! -e "$target" ] || fail 'absent file was created'

prepare_case absent_block
# shellcheck disable=SC2016
printf 'export NVM_DIR="$HOME/.nvm"\nexport JAVA_HOME=/jdk\n' > "$target"
assert_eq absent "$(shell_migration_classify "$target")" 'absent block classification'
absent_hash=$(dotfiles_hash_file "$target")
shell_migration_apply "$target" "$backup_dir" false
assert_eq "$absent_hash" "$(dotfiles_hash_file "$target")" 'foreign shell entries changed'

# Recovery is conditional on an unchanged candidate and a still-available pyenv.
prepare_case recovery
printf 'before\n%s\nafter\n' "$pyenv_block" > "$target"
mkdir -p "$fixture_root/bin"
printf '#!/bin/sh\nexit 0\n' > "$fixture_root/bin/pyenv"
chmod +x "$fixture_root/bin/pyenv"
PATH="$fixture_root/bin:$PATH"
export PATH
shell_migration_apply "$target" "$backup_dir" false
manifest=$SHELL_MIGRATION_MANIFEST
shell_migration_recover "$target" "$manifest"
assert_content "$target" "before
$pyenv_block
after"

prepare_case recovery_changed
printf 'before\n%s\nafter\n' "$pyenv_block" > "$target"
shell_migration_apply "$target" "$backup_dir" false
manifest=$SHELL_MIGRATION_MANIFEST
printf 'foreign\n' >> "$target"
if shell_migration_recover "$target" "$manifest"; then
  fail 'recovery overwrote a changed candidate'
fi

prepare_case recovery_without_pyenv
printf 'before\n%s\nafter\n' "$pyenv_block" > "$target"
shell_migration_apply "$target" "$backup_dir" false
manifest=$SHELL_MIGRATION_MANIFEST
PATH=/usr/bin:/bin
export PATH
if shell_migration_recover "$target" "$manifest"; then
  fail 'recovery restored a dead pyenv hook'
fi
assert_content "$target" 'before
after'

# A login shell is healthy only when startup succeeds without stderr output.
prepare_case login_clean
printf 'export TEST_LOGIN_CLEAN=1\n' > "$target"
shell_migration_login_is_clean || fail 'clean login shell was rejected'

prepare_case login_error
printf 'definitely-missing-login-hook\n' > "$target"
if shell_migration_login_is_clean; then
  fail 'login shell with a missing hook was accepted'
fi

printf 'PASS: shell migration fixture\n'
