#!/usr/bin/env bash

prompt_input() {
  local prompt="$1"

  gum input --header "${prompt}" --header.foreground "99"
}

prompt_secret() {
  local prompt="$1"

  gum input --header "${prompt}" --header.foreground "99" --password
}

prompt_choose() {
  local prompt="${1:-}"

  if [[ -n "${prompt}" ]]; then
    gum choose --header "${prompt}"
    return 0
  fi

  gum choose
}

prompt_filter() {
  local prompt="$1"

  gum filter --header "${prompt}"
}

run_with_spinner() {
  local title="$1"
  shift

  gum spin --spinner line --show-error --title "${title}" --title.foreground "99" -- "$@"
}

ask_non_empty() {
  local prompt="$1"
  local value=""

  while true; do
    value="$(prompt_input "${prompt}")"
    value="$(trim "${value}")"
    if [[ -n "${value}" ]]; then
      printf '%s' "${value}"
      return 0
    fi
    warn "Value cannot be empty."
  done
}

ask_uint() {
  local prompt="$1"
  local value=""

  while true; do
    value="$(prompt_input "${prompt}")"
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
    first="$(prompt_secret "${prompt}")"
    if [[ -z "${first}" ]]; then
      warn "Secret cannot be empty."
      continue
    fi

    second="$(prompt_secret "Confirm secret: ")"
    if [[ "${first}" != "${second}" ]]; then
      warn "Values do not match."
      continue
    fi

    printf '%s' "${first}"
    return 0
  done
}
