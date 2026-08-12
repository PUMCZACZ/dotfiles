#!/bin/bash

# Safe adoption of the single Home Manager canary. Compatible with Bash 3.2.

ADOPTION_MANIFEST=""
ADOPTION_BACKUP_PATH=""
ADOPTION_KIND=""

adoption_validate_target() {
  local target=$1
  local allowed_target=$2
  local tab
  local newline
  tab=$(printf '\t')
  newline=$(printf '\nX')
  newline=${newline%X}

  [ -n "${HOME:-}" ] || return 1
  [ "$target" = "$allowed_target" ] || return 1

  case "$target" in
    "$HOME"/*) ;;
    *) return 1 ;;
  esac

  case "/${target#/}/" in
    */../*) return 1 ;;
  esac

  case "$target" in
    *"$tab"*|*"$newline"*) return 1 ;;
  esac
}

adoption_classify() {
  local target=$1

  if [ -L "$target" ]; then
    if [ -e "$target" ]; then
      printf 'symlink\n'
    else
      printf 'broken-symlink\n'
    fi
  elif [ -f "$target" ]; then
    printf 'file\n'
  elif [ -d "$target" ]; then
    printf 'directory\n'
  elif [ -e "$target" ]; then
    return 1
  else
    printf 'absent\n'
  fi
}

adoption_is_managed() {
  local target=$1
  local expected_content=$2
  local link_target
  local actual_content

  [ -L "$target" ] || return 1
  [ -f "$target" ] || return 1
  link_target=$(readlink "$target")
  case "$link_target" in
    /nix/store/*) ;;
    *) return 1 ;;
  esac

  actual_content=$(sed -n '1,$p' "$target")
  [ "$actual_content" = "$expected_content" ]
}

adoption_append_manifest() {
  local manifest=$1
  local target=$2
  local kind=$3
  local backup_path=$4
  local status=$5

  printf '%s\t%s\t%s\t%s\t%s\n' \
    "$target" "$kind" "$backup_path" "$status" "$(dotfiles_now_utc)" >> "$manifest"
  chmod 600 "$manifest"
}

adoption_adopt() {
  local target=$1
  local allowed_target=$2
  local backup_dir=$3
  local expected_content=$4
  local dry_run=$5

  ADOPTION_MANIFEST=""
  ADOPTION_BACKUP_PATH=""
  ADOPTION_KIND=""

  adoption_validate_target "$target" "$allowed_target" || return 1
  ADOPTION_KIND=$(adoption_classify "$target") || return 1

  if [ "$ADOPTION_KIND" = symlink ] && adoption_is_managed "$target" "$expected_content"; then
    ADOPTION_KIND=managed
    return 0
  fi

  if [ "$ADOPTION_KIND" = absent ] || [ "$dry_run" = true ]; then
    return 0
  fi

  dotfiles_ensure_private_dir "$backup_dir" || return 1
  ADOPTION_MANIFEST="$backup_dir/manifest.tsv"
  ADOPTION_BACKUP_PATH="$backup_dir/original"

  if [ -e "$ADOPTION_BACKUP_PATH" ] || [ -L "$ADOPTION_BACKUP_PATH" ]; then
    return 1
  fi

  adoption_append_manifest \
    "$ADOPTION_MANIFEST" "$target" "$ADOPTION_KIND" "$ADOPTION_BACKUP_PATH" planned

  if /bin/mv "$target" "$ADOPTION_BACKUP_PATH"; then
    adoption_append_manifest \
      "$ADOPTION_MANIFEST" "$target" "$ADOPTION_KIND" "$ADOPTION_BACKUP_PATH" moved
  else
    adoption_append_manifest \
      "$ADOPTION_MANIFEST" "$target" "$ADOPTION_KIND" "$ADOPTION_BACKUP_PATH" failed
    return 1
  fi
}

adoption_mark_managed() {
  local manifest=$1
  local record
  local target
  local kind
  local backup_path

  record=$(awk -F '\t' '$4 == "moved" { record=$0 } END { print record }' "$manifest")
  [ -n "$record" ] || return 0
  IFS=$'\t' read -r target kind backup_path _status _timestamp <<EOF
$record
EOF
  adoption_append_manifest "$manifest" "$target" "$kind" "$backup_path" managed
}

adoption_recover() {
  local target=$1
  local allowed_target=$2
  local manifest=$3
  local record
  local recorded_target
  local kind
  local backup_path

  adoption_validate_target "$target" "$allowed_target" || return 1
  [ -f "$manifest" ] || return 1

  record=$(awk -F '\t' '$4 == "moved" { record=$0 } END { print record }' "$manifest")
  [ -n "$record" ] || return 1
  IFS=$'\t' read -r recorded_target kind backup_path _status _timestamp <<EOF
$record
EOF

  [ "$recorded_target" = "$target" ] || return 1
  if [ -e "$target" ] || [ -L "$target" ]; then
    return 1
  fi
  if [ ! -e "$backup_path" ] && [ ! -L "$backup_path" ]; then
    return 1
  fi

  if /bin/mv "$backup_path" "$target"; then
    adoption_append_manifest "$manifest" "$target" "$kind" "$backup_path" restored
  else
    adoption_append_manifest "$manifest" "$target" "$kind" "$backup_path" failed
    return 1
  fi
}
