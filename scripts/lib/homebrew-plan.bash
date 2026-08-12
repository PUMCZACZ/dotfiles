#!/bin/bash

# Homebrew preview normalization and one-time activation tickets. Bash 3.2.

homebrew_cleanup_classify() {
  homebrew_cleanup_code=$1
  case "$homebrew_cleanup_code" in
    0) printf 'no-removals\n' ;;
    1) printf 'removals\n' ;;
    *) return 1 ;;
  esac
}

homebrew_inventory_validate() {
  homebrew_inventory_file=$1
  [ -f "$homebrew_inventory_file" ] || return 1
  awk -F '\t' '
    NF != 2 { exit 1 }
    $1 != "formula" && $1 != "cask" && $1 != "tap" { exit 1 }
    $2 == "" { exit 1 }
  ' "$homebrew_inventory_file"
}

homebrew_inventory_names() {
  homebrew_names_file=$1
  homebrew_names_kind=$2
  case "$homebrew_names_kind" in
    formula|cask|tap) ;;
    *) return 1 ;;
  esac
  if [ "$homebrew_names_file" != - ]; then
    homebrew_inventory_validate "$homebrew_names_file" || return 1
  fi
  awk -F '\t' -v kind="$homebrew_names_kind" '$1 == kind { print $2 }' "$homebrew_names_file" |
    LC_ALL=C sort -u
}

homebrew_plan_normalize() {
  homebrew_desired_file=$1
  homebrew_actual_file=$2
  homebrew_inventory_validate "$homebrew_desired_file" || return 1
  homebrew_inventory_validate "$homebrew_actual_file" || return 1

  awk -F '\t' '
    FILENAME == ARGV[1] { desired[$1 "\t" $2] = 1; next }
    { actual[$1 "\t" $2] = 1 }
    END {
      for (key in desired) {
        if (key in actual) print "KEEP\t" key
        else print "INSTALL\t" key
      }
      for (key in actual) {
        if (!(key in desired)) print "REMOVE\t" key
      }
    }
  ' "$homebrew_desired_file" "$homebrew_actual_file" | LC_ALL=C sort
}

homebrew_cleanup_removals() {
  homebrew_cleanup_output=$1
  awk '
    /^Would uninstall casks:$/ { kind = "cask"; next }
    /^Would uninstall formulae:$/ { kind = "formula"; next }
    /^Would untap:$/ { kind = "tap"; next }
    /^Warning:/ || /^Would `brew cleanup`:/ || /^Run `brew bundle cleanup/ { kind = ""; next }
    kind != "" && NF { print "REMOVE\t" kind "\t" $0 }
  ' "$homebrew_cleanup_output" | LC_ALL=C sort -u
}

homebrew_plan_hash() {
  dotfiles_hash_file "$1"
}

homebrew_brewfile_write() {
  homebrew_brewfile_path=$1
  dotfiles_write_private_file "$homebrew_brewfile_path"
}

homebrew_brewfile_from_flake() {
  homebrew_brewfile_path=$1
  nix eval --impure --raw --no-write-lock-file \
    "path:$DOTFILES_REPO_ROOT#darwinConfigurations.macos.config.homebrew.brewfile" |
    homebrew_brewfile_write "$homebrew_brewfile_path"
}

homebrew_preview_create() {
  homebrew_preview_brewfile=$1
  homebrew_preview_desired=$2
  homebrew_preview_output=$3
  homebrew_preview_work_dir=$4
  homebrew_preview_brew=${HOMEBREW_BREW_COMMAND:-brew}

  dotfiles_path_is_in_state "$homebrew_preview_output" || return 1
  dotfiles_path_is_in_state "$homebrew_preview_work_dir/work" || return 1
  dotfiles_ensure_private_dir "$homebrew_preview_work_dir" || return 1
  [ -f "$homebrew_preview_brewfile" ] || return 1
  homebrew_inventory_validate "$homebrew_preview_desired" || return 1

  homebrew_preview_check="$homebrew_preview_work_dir/check.txt"
  homebrew_preview_cleanup="$homebrew_preview_work_dir/cleanup.txt"
  homebrew_preview_actual="$homebrew_preview_work_dir/actual.tsv"
  homebrew_preview_direct_sets="$homebrew_preview_work_dir/direct-sets.tsv"
  homebrew_preview_bundle_removals="$homebrew_preview_work_dir/bundle-removals.tsv"
  homebrew_preview_sets="$homebrew_preview_work_dir/sets.tsv"

  if HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_COLOR=1 CI=1 \
    "$homebrew_preview_brew" bundle check --file="$homebrew_preview_brewfile" \
      > "$homebrew_preview_check" 2>&1; then
    HOMEBREW_PREVIEW_CHECK_RC=0
  else
    HOMEBREW_PREVIEW_CHECK_RC=$?
  fi
  case "$HOMEBREW_PREVIEW_CHECK_RC" in
    0|1) ;;
    *) return 1 ;;
  esac

  if HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_COLOR=1 CI=1 \
    "$homebrew_preview_brew" bundle cleanup --file="$homebrew_preview_brewfile" \
      > "$homebrew_preview_cleanup" 2>&1; then
    HOMEBREW_PREVIEW_CLEANUP_RC=0
  else
    HOMEBREW_PREVIEW_CLEANUP_RC=$?
  fi
  homebrew_cleanup_classify "$HOMEBREW_PREVIEW_CLEANUP_RC" >/dev/null || return 1

  : > "$homebrew_preview_actual"
  "$homebrew_preview_brew" leaves |
    awk 'NF { print "formula\t" $0 }' >> "$homebrew_preview_actual" || return 1
  "$homebrew_preview_brew" list --cask |
    awk 'NF { print "cask\t" $0 }' >> "$homebrew_preview_actual" || return 1
  "$homebrew_preview_brew" tap |
    awk 'NF { print "tap\t" $0 }' >> "$homebrew_preview_actual" || return 1
  chmod 600 "$homebrew_preview_check" "$homebrew_preview_cleanup" "$homebrew_preview_actual"
  homebrew_plan_normalize "$homebrew_preview_desired" "$homebrew_preview_actual" > "$homebrew_preview_direct_sets" || return 1
  homebrew_cleanup_removals "$homebrew_preview_cleanup" > "$homebrew_preview_bundle_removals" || return 1
  LC_ALL=C sort -u "$homebrew_preview_direct_sets" "$homebrew_preview_bundle_removals" > "$homebrew_preview_sets" || return 1
  chmod 600 \
    "$homebrew_preview_direct_sets" \
    "$homebrew_preview_bundle_removals" \
    "$homebrew_preview_sets"

  {
    printf 'CHECK_RC\t%s\n' "$HOMEBREW_PREVIEW_CHECK_RC"
    printf 'CLEANUP_RC\t%s\n' "$HOMEBREW_PREVIEW_CLEANUP_RC"
    sed -n '1,$p' "$homebrew_preview_sets"
    awk 'NF { gsub(/\t/, " "); sub(/^[[:space:]]*/, ""); sub(/[[:space:]]*$/, ""); print "CHECK\t" $0 }' \
      "$homebrew_preview_check" | LC_ALL=C sort
    awk 'NF { gsub(/\t/, " "); sub(/^[[:space:]]*/, ""); sub(/[[:space:]]*$/, ""); print "CLEANUP\t" $0 }' \
      "$homebrew_preview_cleanup" | LC_ALL=C sort
  } | dotfiles_write_private_file "$homebrew_preview_output"
}

homebrew_plan_requires_cleanup() {
  grep -Eq '^REMOVE[[:space:]]|^CLEANUP_RC[[:space:]]+1$' "$1"
}

homebrew_hashes_match() {
  [ "$#" -eq 8 ] || return 1
  [ "$1" = "$2" ] &&
    [ "$3" = "$4" ] &&
    [ "$5" = "$6" ] &&
    [ "$7" = "$8" ]
}

homebrew_ticket_value() {
  homebrew_ticket_file=$1
  homebrew_ticket_key=$2
  awk -F= -v key="$homebrew_ticket_key" '
    $1 == key { count++; sub(/^[^=]*=/, ""); value = $0 }
    END { if (count == 1) print value; else exit 1 }
  ' "$homebrew_ticket_file"
}

homebrew_ticket_read_plan_hash() {
  homebrew_ticket_path=$1
  homebrew_ticket_expected_owner=$2
  [ -f "$homebrew_ticket_path" ] || return 1
  [ ! -L "$homebrew_ticket_path" ] || return 1
  [ "$(stat -f '%Su' "$homebrew_ticket_path")" = "$homebrew_ticket_expected_owner" ] || return 1
  [ "$(stat -f '%Lp' "$homebrew_ticket_path")" = 600 ] || return 1
  homebrew_ticket_value "$homebrew_ticket_path" activationPlanHash
}

homebrew_ticket_write() {
  homebrew_ticket_path=$1
  homebrew_ticket_run_id=$2
  homebrew_ticket_mode=$3
  homebrew_ticket_lock_hash=$4
  homebrew_ticket_declaration_hash=$5
  homebrew_ticket_brewfile_hash=$6
  homebrew_ticket_plan_hash=$7
  homebrew_ticket_expires=$8

  case "$homebrew_ticket_mode" in
    ZAP|NO_CLEANUP) ;;
    *) return 1 ;;
  esac
  case "$homebrew_ticket_expires" in
    ''|*[!0-9]*) return 1 ;;
  esac

  homebrew_ticket_owner=$(id -un)
  homebrew_ticket_created=$(date +%s)
  {
    printf 'runId=%s\n' "$homebrew_ticket_run_id"
    printf 'mode=%s\n' "$homebrew_ticket_mode"
    printf 'lockHash=%s\n' "$homebrew_ticket_lock_hash"
    printf 'declarationHash=%s\n' "$homebrew_ticket_declaration_hash"
    printf 'brewfileHash=%s\n' "$homebrew_ticket_brewfile_hash"
    printf 'activationPlanHash=%s\n' "$homebrew_ticket_plan_hash"
    printf 'owner=%s\n' "$homebrew_ticket_owner"
    printf 'createdAt=%s\n' "$homebrew_ticket_created"
    printf 'expiresAt=%s\n' "$homebrew_ticket_expires"
  } | dotfiles_write_private_file "$homebrew_ticket_path"
}

homebrew_ticket_validate() {
  homebrew_ticket_path=$1
  homebrew_ticket_expected_owner=$2
  homebrew_ticket_expected_mode=$3
  homebrew_ticket_expected_lock=$4
  homebrew_ticket_expected_declaration=$5
  homebrew_ticket_expected_brewfile=$6
  homebrew_ticket_expected_plan=$7
  homebrew_ticket_now=$8

  [ -f "$homebrew_ticket_path" ] || return 1
  [ ! -L "$homebrew_ticket_path" ] || return 1
  [ "$(stat -f '%Su' "$homebrew_ticket_path")" = "$homebrew_ticket_expected_owner" ] || return 1
  [ "$(stat -f '%Lp' "$homebrew_ticket_path")" = 600 ] || return 1
  awk -F= '
    $1 != "runId" && $1 != "mode" && $1 != "lockHash" &&
      $1 != "declarationHash" && $1 != "brewfileHash" &&
      $1 != "activationPlanHash" && $1 != "owner" &&
      $1 != "createdAt" && $1 != "expiresAt" { exit 1 }
    END { if (NR != 9) exit 1 }
  ' "$homebrew_ticket_path" || return 1
  case "$homebrew_ticket_now" in
    ''|*[!0-9]*) return 1 ;;
  esac

  homebrew_ticket_run=$(homebrew_ticket_value "$homebrew_ticket_path" runId) || return 1
  homebrew_ticket_mode=$(homebrew_ticket_value "$homebrew_ticket_path" mode) || return 1
  homebrew_ticket_lock=$(homebrew_ticket_value "$homebrew_ticket_path" lockHash) || return 1
  homebrew_ticket_declaration=$(homebrew_ticket_value "$homebrew_ticket_path" declarationHash) || return 1
  homebrew_ticket_brewfile=$(homebrew_ticket_value "$homebrew_ticket_path" brewfileHash) || return 1
  homebrew_ticket_plan=$(homebrew_ticket_value "$homebrew_ticket_path" activationPlanHash) || return 1
  homebrew_ticket_owner=$(homebrew_ticket_value "$homebrew_ticket_path" owner) || return 1
  homebrew_ticket_created=$(homebrew_ticket_value "$homebrew_ticket_path" createdAt) || return 1
  homebrew_ticket_expires=$(homebrew_ticket_value "$homebrew_ticket_path" expiresAt) || return 1

  [ -n "$homebrew_ticket_run" ] || return 1
  [ "$homebrew_ticket_mode" = "$homebrew_ticket_expected_mode" ] || return 1
  [ "$homebrew_ticket_owner" = "$homebrew_ticket_expected_owner" ] || return 1
  [ "$homebrew_ticket_lock" = "$homebrew_ticket_expected_lock" ] || return 1
  [ "$homebrew_ticket_declaration" = "$homebrew_ticket_expected_declaration" ] || return 1
  [ "$homebrew_ticket_brewfile" = "$homebrew_ticket_expected_brewfile" ] || return 1
  [ "$homebrew_ticket_plan" = "$homebrew_ticket_expected_plan" ] || return 1
  case "$homebrew_ticket_created:$homebrew_ticket_expires" in
    *[!0-9:]*) return 1 ;;
  esac
  [ "$homebrew_ticket_created" -le "$homebrew_ticket_now" ] || return 1
  [ "$homebrew_ticket_expires" -gt "$homebrew_ticket_now" ] || return 1
  [ $((homebrew_ticket_expires - homebrew_ticket_created)) -le 300 ] || return 1
}

homebrew_ticket_consume() {
  homebrew_ticket_path=$1
  homebrew_ticket_validate "$@" || return 1
  /bin/rm "$homebrew_ticket_path"
}
