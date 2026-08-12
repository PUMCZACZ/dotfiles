#!/bin/bash
set -Eeuo pipefail
umask 077

test_dir="$(cd "$(dirname "$0")" && pwd -P)"
repo_root="$(cd "$test_dir/.." && pwd -P)"

# shellcheck source=scripts/lib/common.bash
. "$repo_root/scripts/lib/common.bash"
# shellcheck source=scripts/lib/adoption.bash
. "$repo_root/scripts/lib/adoption.bash"

fixture_root=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-adoption.XXXXXX")
expected_content='managed-by=home-manager
profile=macos
foundation-version=1'

cleanup_fixture() {
  case "$fixture_root" in
    "${TMPDIR:-/tmp}"/dotfiles-adoption.*) /bin/rm -R "$fixture_root" ;;
    *) printf 'REFUSE cleanup outside fixture root: %s\n' "$fixture_root" >&2 ;;
  esac
}
trap cleanup_fixture EXIT HUP INT TERM

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_eq() {
  assert_expected=$1
  assert_actual=$2
  assert_message=$3
  [ "$assert_expected" = "$assert_actual" ] ||
    fail "$assert_message (expected=$assert_expected actual=$assert_actual)"
}

assert_file_content() {
  assert_path=$1
  assert_content=$2
  assert_eq "$assert_content" "$(sed -n '1,$p' "$assert_path")" "unexpected content: $assert_path"
}

prepare_case() {
  case_name=$1
  HOME="$fixture_root/$case_name/home"
  XDG_STATE_HOME="$fixture_root/$case_name/state"
  export HOME XDG_STATE_HOME
  mkdir -p "$HOME/.config/dotfiles-managed"
  target="$HOME/.config/dotfiles-managed/foundation"
  backup_dir="$XDG_STATE_HOME/dotfiles/backups/run"
}

assert_manifest_shape() {
  manifest_path=$1
  awk -F '\t' 'NF != 5 { exit 1 } END { if (NR == 0) exit 1 }' "$manifest_path" ||
    fail "invalid manifest shape: $manifest_path"
  assert_eq 600 "$(stat -f '%Lp' "$manifest_path")" "manifest mode"
}

# A regular file must be moved, recorded and restored without data loss.
prepare_case file
printf 'local-file\n' > "$target"
assert_eq file "$(adoption_classify "$target")" 'regular file classification'
adoption_adopt "$target" "$target" "$backup_dir" "$expected_content" false
[ ! -e "$target" ] || fail 'file target still exists after adoption'
assert_file_content "$ADOPTION_BACKUP_PATH" 'local-file'
assert_manifest_shape "$ADOPTION_MANIFEST"
grep -q $'\tfile\t.*\tmoved\t' "$ADOPTION_MANIFEST" || fail 'file moved status missing'
adoption_recover "$target" "$target" "$ADOPTION_MANIFEST"
assert_file_content "$target" 'local-file'
grep -q $'\trestored\t' "$ADOPTION_MANIFEST" || fail 'restored status missing'

# A directory must move as one element and recover with its contents.
prepare_case directory
mkdir "$target"
printf 'nested\n' > "$target/value"
assert_eq directory "$(adoption_classify "$target")" 'directory classification'
adoption_adopt "$target" "$target" "$backup_dir" "$expected_content" false
[ -d "$ADOPTION_BACKUP_PATH" ] || fail 'directory backup missing'
assert_file_content "$ADOPTION_BACKUP_PATH/value" 'nested'
adoption_recover "$target" "$target" "$ADOPTION_MANIFEST"
assert_file_content "$target/value" 'nested'

# A matching Nix-store symlink is already managed and creates no backup.
prepare_case managed_symlink
source_file="$fixture_root/managed-source"
printf '%s\n' "$expected_content" > "$source_file"
store_source=$(nix store add-file "$source_file")
ln -s "$store_source" "$target"
assert_eq symlink "$(adoption_classify "$target")" 'managed symlink classification'
adoption_adopt "$target" "$target" "$backup_dir" "$expected_content" false
adoption_adopt "$target" "$target" "$backup_dir" "$expected_content" false
[ -L "$target" ] || fail 'managed symlink changed'
[ ! -e "$backup_dir" ] || fail 'managed symlink created backup'

# Wrong and broken symlinks must move as symlinks, never dereference.
prepare_case wrong_symlink
wrong_source="$fixture_root/wrong-source"
printf 'wrong\n' > "$wrong_source"
ln -s "$wrong_source" "$target"
adoption_adopt "$target" "$target" "$backup_dir" "$expected_content" false
[ -L "$ADOPTION_BACKUP_PATH" ] || fail 'wrong symlink backup is not symlink'
assert_eq "$wrong_source" "$(readlink "$ADOPTION_BACKUP_PATH")" 'wrong symlink target changed'

prepare_case broken_symlink
broken_source="$fixture_root/does-not-exist"
ln -s "$broken_source" "$target"
assert_eq broken-symlink "$(adoption_classify "$target")" 'broken symlink classification'
adoption_adopt "$target" "$target" "$backup_dir" "$expected_content" false
[ -L "$ADOPTION_BACKUP_PATH" ] || fail 'broken symlink backup is not symlink'
assert_eq "$broken_source" "$(readlink "$ADOPTION_BACKUP_PATH")" 'broken symlink target changed'

# Spaces and a basename starting with dash remain safe because paths are absolute.
prepare_case special_name
target="$HOME/path with spaces/-foundation"
mkdir -p "$(dirname "$target")"
printf 'special\n' > "$target"
adoption_adopt "$target" "$target" "$backup_dir" "$expected_content" false
assert_file_content "$ADOPTION_BACKUP_PATH" 'special'

# Dry-run must not create backup, manifest or mutate target.
prepare_case dry_run
printf 'dry\n' > "$target"
adoption_adopt "$target" "$target" "$backup_dir" "$expected_content" true
assert_file_content "$target" 'dry'
[ ! -e "$backup_dir" ] || fail 'dry-run created backup directory'

# Paths outside HOME, with dot segments, tabs or newlines must be rejected.
prepare_case validation
outside_target="$fixture_root/outside"
if adoption_validate_target "$outside_target" "$outside_target"; then
  fail 'outside HOME accepted'
fi
dotdot_target="$HOME/safe/../foundation"
if adoption_validate_target "$dotdot_target" "$dotdot_target"; then
  fail 'dotdot target accepted'
fi
tab_target="$HOME/tab"$'\t'"foundation"
if adoption_validate_target "$tab_target" "$tab_target"; then
  fail 'tab target accepted'
fi
newline_target="$HOME/newline"$'\n'"foundation"
if adoption_validate_target "$newline_target" "$newline_target"; then
  fail 'newline target accepted'
fi

# Recovery must refuse to overwrite state created after failed activation.
prepare_case recovery_refuses_overwrite
printf 'original\n' > "$target"
adoption_adopt "$target" "$target" "$backup_dir" "$expected_content" false
printf 'foreign\n' > "$target"
if adoption_recover "$target" "$target" "$ADOPTION_MANIFEST"; then
  fail 'recovery overwrote foreign target'
fi
assert_file_content "$target" 'foreign'
assert_file_content "$ADOPTION_BACKUP_PATH" 'original'

# A held operation lock must make a second mutator return 75.
prepare_case lock
dotfiles_acquire_lock fixture
if DOTFILES_TEST_REPO_ROOT="$repo_root" XDG_STATE_HOME="$XDG_STATE_HOME" HOME="$HOME" \
  /bin/bash -c '. "$DOTFILES_TEST_REPO_ROOT/scripts/lib/common.bash"; dotfiles_acquire_lock fixture'; then
  fail 'second mutator acquired held lock'
else
  second_lock_status=$?
  assert_eq 75 "$second_lock_status" 'second mutator exit code'
fi
dotfiles_release_lock

# Private runtime artifacts must be atomic regular files and removable only
# from the configured state root.
prepare_case private_artifacts
private_file="$XDG_STATE_HOME/dotfiles/plans/plan.txt"
if ! printf 'private-plan\n' | dotfiles_write_private_file "$private_file"; then
  fail 'private atomic write failed'
fi
assert_file_content "$private_file" 'private-plan'
assert_eq 600 "$(stat -f '%Lp' "$private_file")" 'private file mode'
dotfiles_is_private_regular_file "$private_file" || fail 'private regular file rejected'

private_link="$XDG_STATE_HOME/dotfiles/plans/link.txt"
ln -s "$private_file" "$private_link"
if dotfiles_is_private_regular_file "$private_link"; then
  fail 'private symlink accepted as regular file'
fi

dotfiles_remove_private_file "$private_file"
[ ! -e "$private_file" ] || fail 'private file was not removed'
outside_private="$fixture_root/outside-private"
printf 'outside\n' > "$outside_private"
if dotfiles_remove_private_file "$outside_private"; then
  fail 'private cleanup escaped state root'
fi
assert_file_content "$outside_private" 'outside'

printf 'PASS: adoption fixture\n'
