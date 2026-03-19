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

require_dependencies() {
  local dependencies=(
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
  for dep in "${dependencies[@]}"; do
    require_command "${dep}"
  done
}

main() {
  require_root
  require_dependencies

  collect_install_inputs
  summarize_install_plan
  prepare_disk_layout
  install_base_system
  run_chroot_configuration

  log "Installation flow completed."
  log "Review /mnt and reboot when ready."
}

main "$@"
