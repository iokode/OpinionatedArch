#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/prompts.sh
source "${SCRIPT_DIR}/lib/prompts.sh"
# shellcheck source=lib/disk.sh
source "${SCRIPT_DIR}/lib/disk.sh"
# shellcheck source=lib/bootstrap.sh
source "${SCRIPT_DIR}/lib/bootstrap.sh"
# shellcheck source=lib/chroot.sh
source "${SCRIPT_DIR}/lib/chroot.sh"

parse_args() {
  OPARCH_VERBOSE="${OPARCH_VERBOSE:-0}"
  OPARCH_CONFIG_FILE="${OPARCH_CONFIG_FILE:-}"

  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      -verbose)
        OPARCH_VERBOSE=1
        shift
        ;;
      -configfile)
        [[ "$#" -ge 2 ]] || die "Missing value for -configfile"
        OPARCH_CONFIG_FILE="$2"
        shift 2
        ;;
      *)
        die "Unknown argument: $1"
        ;;
    esac
  done

  export OPARCH_VERBOSE
  export OPARCH_CONFIG_FILE
}

require_live_dependencies() {
  local live_dependencies=(
    lsblk
    wipefs
    sgdisk
    partprobe
    udevadm
    mkfs.fat
    cryptsetup
    mkfs.btrfs
    mount
    btrfs
    pacstrap
    genfstab
    arch-chroot
    blkid
    curl
  )

  local dep
  for dep in "${live_dependencies[@]}"; do
    require_command "${dep}"
  done
}

main() {
  parse_args "$@"

  require_root
  require_live_dependencies

  collect_install_inputs
  summarize_install_plan
  prepare_disk_layout
  bootstrap_base_system
  configure_installed_system

  log "Installation flow completed."
  log "Review /mnt and reboot when ready."
}

main "$@"
