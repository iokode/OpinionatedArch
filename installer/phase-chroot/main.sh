#!/usr/bin/env bash

run_phase_chroot() {
  log "Running chroot configuration..."

  run_cmd arch-chroot /mnt /bin/bash -s <<'CHROOT_EOF'
set -euo pipefail

source /root/oparch-install.env
source /oparch/installer/phase-chroot/packages.sh
source /oparch/installer/phase-chroot/identity.sh
source /oparch/installer/phase-chroot/users.sh
source /oparch/installer/phase-chroot/network.sh
source /oparch/installer/phase-chroot/snapshots.sh
source /oparch/installer/phase-chroot/boot.sh

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

chmod ugo+x /oparch/bin/*
rm -rf /oparch/tmp
rm /root/oparch-install.env
CHROOT_EOF

  log "Chroot configuration finished."
}
