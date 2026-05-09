#!/usr/bin/env bash

run_cmd() {
  if [[ "${OPARCH_VERBOSE:-0}" == "0" ]]; then
    if ! "$@" >/tmp/oparch-cmd.log 2>&1; then
      warn "Command failed: $*"
      tail -n 120 /tmp/oparch-cmd.log >&4 || true
      return 1
    fi
    return 0
  fi

  "$@"
}

run_cmd_with_input() {
  local title=""
  if [[ "${1:-}" == "--title" ]]; then
    title="$2"
    shift 2
  fi

  local input_value="$1"
  shift

  if [[ "${OPARCH_VERBOSE:-0}" == "0" ]]; then
    if [[ -n "${title}" ]]; then
      if ! printf '%s' "${input_value}" | run_with_spinner "${title}" "$@"; then
        warn "Command failed: $*"
        return 1
      fi
      return 0
    fi

    if ! printf '%s' "${input_value}" | "$@" >/tmp/oparch-cmd.log 2>&1; then
      warn "Command failed: $*"
      tail -n 120 /tmp/oparch-cmd.log >&4 || true
      return 1
    fi
    return 0
  fi

  printf '%s' "${input_value}" | "$@"
}

run_pkg_cmd() {
  local title="Running package command..."
  if [[ "${1:-}" == "--title" ]]; then
    title="$2"
    shift 2
  fi

  if [[ "${OPARCH_VERBOSE:-0}" == "2" ]]; then
    "$@"
    return 0
  fi

  working "${title}" "$@"
}
