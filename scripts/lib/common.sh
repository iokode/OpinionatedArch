#!/usr/bin/env bash

if [[ -n "${OPARCH_COMMON_SH_LOADED:-}" ]]; then
  return 0
fi
OPARCH_COMMON_SH_LOADED=1

log() {
  printf '[INFO] %s\n' "$*"
}

warn() {
  printf '[WARN] %s\n' "$*" >&2
}

die() {
  printf '[ERROR] %s\n' "$*" >&2
  exit 1
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    die "This installer must run as root."
  fi
}

require_command() {
  local command_name="$1"
  command -v "${command_name}" >/dev/null 2>&1 || die "Missing required command: ${command_name}"
}

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "${value}"
}

ask_non_empty() {
  local prompt="$1"
  local value=""

  while true; do
    read -r -p "${prompt}" value
    value="$(trim "${value}")"
    if [[ -n "${value}" ]]; then
      printf '%s' "${value}"
      return 0
    fi
    warn "Value cannot be empty."
  done
}

ask_choice() {
  local prompt="$1"
  shift
  local -a choices=("$@")
  local value=""
  local choice=""

  while true; do
    read -r -p "${prompt}" value
    value="$(trim "${value}")"
    for choice in "${choices[@]}"; do
      if [[ "${value}" == "${choice}" ]]; then
        printf '%s' "${value}"
        return 0
      fi
    done
    warn "Invalid choice. Valid options: ${choices[*]}"
  done
}

ask_yes_no() {
  local prompt="$1"
  local answer=""

  while true; do
    read -r -p "${prompt} [y/n]: " answer
    answer="$(trim "${answer}")"
    case "${answer}" in
      y|Y|yes|YES)
        printf 'yes'
        return 0
        ;;
      n|N|no|NO)
        printf 'no'
        return 0
        ;;
      *)
        warn "Please answer y or n."
        ;;
    esac
  done
}

ask_uint() {
  local prompt="$1"
  local value=""

  while true; do
    read -r -p "${prompt}" value
    value="$(trim "${value}")"
    if [[ "${value}" =~ ^[0-9]+$ ]]; then
      printf '%s' "${value}"
      return 0
    fi
    warn "Please enter a non-negative integer."
  done
}

read_secret_with_confirmation() {
  local prompt="$1"
  local first=""
  local second=""

  while true; do
    read -r -s -p "${prompt}" first
    printf '\n' >&2
    read -r -s -p "Confirm secret: " second
    printf '\n' >&2

    if [[ -z "${first}" ]]; then
      warn "Secret cannot be empty."
      continue
    fi

    if [[ "${first}" != "${second}" ]]; then
      warn "Values do not match."
      continue
    fi

    printf '%s' "${first}"
    return 0
  done
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
