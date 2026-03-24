#!/usr/bin/env bash

if [[ -z "${OPARCH_LOG_FDS_READY:-}" ]]; then
  exec 3>&1
  exec 4>&2
  OPARCH_LOG_FDS_READY=1
fi

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
