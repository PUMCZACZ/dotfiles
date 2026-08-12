#!/bin/bash

# Targeted removal of the one accepted pyenv block. Compatible with macOS Bash 3.2.

SHELL_MIGRATION_STATUS=""
SHELL_MIGRATION_ORIGINAL_HASH=""
SHELL_MIGRATION_CANDIDATE_HASH=""
SHELL_MIGRATION_BACKUP_PATH=""
SHELL_MIGRATION_MANIFEST=""

shell_migration_validate_target() {
  shell_migration_target=$1
  [ "$shell_migration_target" = "$HOME/.zshrc" ] || return 1
  case "$shell_migration_target" in
    *'/../'*|*'/./'*|*$'\t'*|*$'\n'*) return 1 ;;
  esac
  [ ! -L "$shell_migration_target" ] || return 1
  [ ! -e "$shell_migration_target" ] || [ -f "$shell_migration_target" ]
}

shell_migration_exact_count() {
  shell_migration_count_target=$1
  [ -f "$shell_migration_count_target" ] || {
    printf '0\n'
    return 0
  }

  awk '
    { lines[NR] = $0 }
    END {
      count = 0
      for (i = 1; i <= NR - 3; i++) {
        if (lines[i] == "# pyenv" &&
            lines[i + 1] == "export PYENV_ROOT=\"$HOME/.pyenv\"" &&
            lines[i + 2] == "[[ -d $PYENV_ROOT/bin ]] && export PATH=\"$PYENV_ROOT/bin:$PATH\"" &&
            lines[i + 3] == "eval \"$(pyenv init -)\"") {
          count++
          i += 3
        }
      }
      print count
    }
  ' "$shell_migration_count_target"
}

shell_migration_classify() {
  shell_migration_classify_target=$1
  shell_migration_validate_target "$shell_migration_classify_target" || {
    printf 'refused\n'
    return 1
  }

  [ -f "$shell_migration_classify_target" ] || {
    printf 'absent\n'
    return 0
  }

  shell_migration_match_count=$(shell_migration_exact_count "$shell_migration_classify_target") || return 1
  if [ "$shell_migration_match_count" -gt 1 ]; then
    printf 'duplicate\n'
    return 0
  fi
  if [ "$shell_migration_match_count" -eq 1 ]; then
    shell_migration_marker_count=$(grep -Ec '^# pyenv$|PYENV_ROOT|pyenv init' "$shell_migration_classify_target" || true)
    if [ "$shell_migration_marker_count" -eq 4 ]; then
      printf 'exact\n'
    else
      printf 'modified\n'
    fi
    return 0
  fi

  if grep -Eq '^# pyenv$|PYENV_ROOT|pyenv init' "$shell_migration_classify_target"; then
    printf 'modified\n'
  else
    printf 'absent\n'
  fi
}

shell_migration_write_candidate() {
  shell_migration_source=$1
  shell_migration_candidate=$2
  awk '
    { lines[NR] = $0 }
    END {
      for (i = 1; i <= NR; i++) {
        if (i <= NR - 3 &&
            lines[i] == "# pyenv" &&
            lines[i + 1] == "export PYENV_ROOT=\"$HOME/.pyenv\"" &&
            lines[i + 2] == "[[ -d $PYENV_ROOT/bin ]] && export PATH=\"$PYENV_ROOT/bin:$PATH\"" &&
            lines[i + 3] == "eval \"$(pyenv init -)\"") {
          i += 3
        } else {
          print lines[i]
        }
      }
    }
  ' "$shell_migration_source" > "$shell_migration_candidate"
}

shell_migration_apply() {
  shell_migration_apply_target=$1
  shell_migration_backup_dir=$2
  shell_migration_dry_run=${3:-false}

  SHELL_MIGRATION_STATUS=""
  SHELL_MIGRATION_ORIGINAL_HASH=""
  SHELL_MIGRATION_CANDIDATE_HASH=""
  SHELL_MIGRATION_BACKUP_PATH=""
  SHELL_MIGRATION_MANIFEST=""

  shell_migration_validate_target "$shell_migration_apply_target" || {
    SHELL_MIGRATION_STATUS=refused
    return 1
  }
  shell_migration_state=$(shell_migration_classify "$shell_migration_apply_target") || {
    SHELL_MIGRATION_STATUS=refused
    return 1
  }
  case "$shell_migration_state" in
    absent)
      SHELL_MIGRATION_STATUS=absent
      return 0
      ;;
    modified|duplicate|refused)
      SHELL_MIGRATION_STATUS=refused
      return 1
      ;;
    exact) ;;
    *)
      SHELL_MIGRATION_STATUS=refused
      return 1
      ;;
  esac

  SHELL_MIGRATION_ORIGINAL_HASH=$(dotfiles_hash_file "$shell_migration_apply_target") || return 1
  if [ "$shell_migration_dry_run" = true ]; then
    SHELL_MIGRATION_STATUS=classified
    return 0
  fi

  shell_migration_parent=$(dirname "$shell_migration_apply_target")
  shell_migration_name=$(basename "$shell_migration_apply_target")
  shell_migration_tmp="$shell_migration_parent/.$shell_migration_name.migrate.$$.$RANDOM"
  shell_migration_mode=$(stat -f '%Lp' "$shell_migration_apply_target") || return 1
  shell_migration_write_candidate "$shell_migration_apply_target" "$shell_migration_tmp" || {
    /bin/rm -f "$shell_migration_tmp"
    return 1
  }
  chmod "$shell_migration_mode" "$shell_migration_tmp" || {
    /bin/rm -f "$shell_migration_tmp"
    return 1
  }
  SHELL_MIGRATION_CANDIDATE_HASH=$(dotfiles_hash_file "$shell_migration_tmp") || {
    /bin/rm -f "$shell_migration_tmp"
    return 1
  }

  SHELL_MIGRATION_BACKUP_PATH="$shell_migration_backup_dir/.zshrc.original"
  SHELL_MIGRATION_MANIFEST="$shell_migration_backup_dir/manifest"
  dotfiles_path_is_in_state "$SHELL_MIGRATION_BACKUP_PATH" || return 1
  dotfiles_path_is_in_state "$SHELL_MIGRATION_MANIFEST" || return 1
  [ ! -e "$SHELL_MIGRATION_BACKUP_PATH" ] || return 1
  [ ! -e "$SHELL_MIGRATION_MANIFEST" ] || return 1
  dotfiles_write_private_file "$SHELL_MIGRATION_BACKUP_PATH" < "$shell_migration_apply_target" || return 1
  {
    printf 'source=%s\n' "$shell_migration_apply_target"
    printf 'backupPath=%s\n' "$SHELL_MIGRATION_BACKUP_PATH"
    printf 'originalHash=%s\n' "$SHELL_MIGRATION_ORIGINAL_HASH"
    printf 'candidateHash=%s\n' "$SHELL_MIGRATION_CANDIDATE_HASH"
    printf 'status=transformed\n'
  } | dotfiles_write_private_file "$SHELL_MIGRATION_MANIFEST" || return 1

  if [ "$(dotfiles_hash_file "$shell_migration_apply_target")" != "$SHELL_MIGRATION_ORIGINAL_HASH" ]; then
    return 1
  fi
  mv -f "$shell_migration_tmp" "$shell_migration_apply_target"
  SHELL_MIGRATION_STATUS=transformed
}

shell_migration_manifest_value() {
  shell_migration_manifest=$1
  shell_migration_key=$2
  awk -F= -v key="$shell_migration_key" '
    $1 == key { count++; sub(/^[^=]*=/, ""); value = $0 }
    END { if (count == 1) print value; else exit 1 }
  ' "$shell_migration_manifest"
}

shell_migration_recover() {
  shell_migration_recover_target=$1
  shell_migration_recover_manifest=$2
  shell_migration_validate_target "$shell_migration_recover_target" || return 1
  dotfiles_is_private_regular_file "$shell_migration_recover_manifest" || return 1
  [ -f "$shell_migration_recover_target" ] || return 1
  command -v pyenv >/dev/null 2>&1 || return 1

  shell_migration_recorded_source=$(shell_migration_manifest_value "$shell_migration_recover_manifest" source) || return 1
  shell_migration_recorded_backup=$(shell_migration_manifest_value "$shell_migration_recover_manifest" backupPath) || return 1
  shell_migration_recorded_candidate=$(shell_migration_manifest_value "$shell_migration_recover_manifest" candidateHash) || return 1
  [ "$shell_migration_recorded_source" = "$shell_migration_recover_target" ] || return 1
  dotfiles_is_private_regular_file "$shell_migration_recorded_backup" || return 1
  [ "$(dotfiles_hash_file "$shell_migration_recover_target")" = "$shell_migration_recorded_candidate" ] || return 1

  shell_migration_recover_parent=$(dirname "$shell_migration_recover_target")
  shell_migration_recover_name=$(basename "$shell_migration_recover_target")
  shell_migration_recover_tmp="$shell_migration_recover_parent/.$shell_migration_recover_name.recover.$$.$RANDOM"
  shell_migration_recover_mode=$(stat -f '%Lp' "$shell_migration_recover_target") || return 1
  cp -p "$shell_migration_recorded_backup" "$shell_migration_recover_tmp" || return 1
  chmod "$shell_migration_recover_mode" "$shell_migration_recover_tmp" || {
    /bin/rm -f "$shell_migration_recover_tmp"
    return 1
  }
  mv -f "$shell_migration_recover_tmp" "$shell_migration_recover_target"
  # Public result consumed by switch.sh and the fixture.
  # shellcheck disable=SC2034
  SHELL_MIGRATION_STATUS=recovered
}

shell_migration_login_is_clean() {
  if shell_migration_login_output=$(/bin/zsh -lic 'exit 0' 2>&1); then
    [ -z "$shell_migration_login_output" ]
  else
    return 1
  fi
}
