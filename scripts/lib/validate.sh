#!/usr/bin/env bash

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "${value}"
}

validate_hostname() {
  local hostname="$1"
  [[ "${hostname}" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]{0,62}$ ]]
}

validate_username() {
  local username="$1"
  [[ "${username}" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]
}

join_by() {
  local delimiter="$1"
  shift
  local first=1
  local item=""

  for item in "$@"; do
    if [[ "${first}" -eq 1 ]]; then
      printf '%s' "${item}"
      first=0
    else
      printf '%s%s' "${delimiter}" "${item}"
    fi
  done
}
