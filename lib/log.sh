#!/usr/bin/env bash

if [[ -z "${OPARCH_LOG_FDS_READY:-}" ]]; then
  exec 3>&1
  exec 4>&2
  OPARCH_LOG_FDS_READY=1
fi

working() {
  local title="$1"
  shift
  if [[ "${OPARCH_VERBOSE:-0}" == "0" ]]; then
    if ! run_with_spinner "${title}" "$@"; then
      warn "Command failed: $*"
      return 1
    fi
  else
    printf '[INFO] > %s\n' "$*" >&3
    "$@"
  fi
}

log() {
  printf '[INFO] %s\n' "$*" >&3
}

warn() {
  printf '[WARN] %s\n' "$*" >&4
}

die() {
  printf '[ERROR] %s\n' "$*" >&4
  exit 1
}

require_root_or_warn_exit() {
  local message="${1:-This command must run as root.}"
  if [[ "${EUID}" -ne 0 ]]; then
    warn "${message}"
    exit 1
  fi
}
