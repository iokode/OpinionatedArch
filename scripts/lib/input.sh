#!/usr/bin/env bash

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
