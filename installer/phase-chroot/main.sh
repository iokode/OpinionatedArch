#!/usr/bin/env bash

run_phase_chroot() {
  log "Running chroot configuration"

  run_cmd arch-chroot /mnt /bin/bash -s <<'CHROOT_EOF'
set -euo pipefail

source /root/oparch-install.env
source /oparch/scripts/phase-chroot/packages.sh
source /oparch/scripts/phase-chroot/identity.sh
source /oparch/scripts/phase-chroot/users.sh
source /oparch/scripts/phase-chroot/network.sh
source /oparch/scripts/phase-chroot/snapshots.sh
source /oparch/scripts/phase-chroot/boot.sh

chroot_prepare_vconsole
chroot_install_base_packages
chroot_configure_locale_and_time
chroot_configure_identity
chroot_configure_users_and_groups
chroot_configure_network_stack
chroot_configure_snapshots
chroot_configure_swap_encryption
chroot_configure_plymouth_defaults
chroot_configure_initramfs
chroot_configure_grub
chroot_install_snap_pac

rm -rf /oparch/tmp
rm /root/oparch-install.env
CHROOT_EOF

  log "Chroot configuration finished."
}
