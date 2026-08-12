#!/bin/bash

profile_path_install_regular() {
  profile_path_source=$1
  profile_path_target=$2
  profile_path_managed_link=$3

  if [ ! -f "$profile_path_source" ] || [ -L "$profile_path_source" ]; then
    printf '[profile-path] FAIL źródło nie jest zwykłym plikiem: %s\n' "$profile_path_source" >&2
    return 1
  fi

  if [ -L "$profile_path_target" ]; then
    profile_path_actual_link=$(/usr/bin/readlink "$profile_path_target") || return 1
    if [ "$profile_path_actual_link" != "$profile_path_managed_link" ]; then
      printf '[profile-path] FAIL odmowa zastąpienia obcego symlinka: %s\n' "$profile_path_target" >&2
      return 1
    fi
    /bin/rm "$profile_path_target" || return 1
  elif [ -e "$profile_path_target" ]; then
    if [ ! -f "$profile_path_target" ] ||
      ! /usr/bin/cmp -s "$profile_path_source" "$profile_path_target"; then
      printf '[profile-path] FAIL odmowa zastąpienia obcego pliku: %s\n' "$profile_path_target" >&2
      return 1
    fi
    /bin/chmod 0644 "$profile_path_target" || return 1
    return 0
  fi

  /usr/bin/install -m 0644 "$profile_path_source" "$profile_path_target" || return 1
  [ -f "$profile_path_target" ] && [ ! -L "$profile_path_target" ] &&
    /usr/bin/cmp -s "$profile_path_source" "$profile_path_target"
}
