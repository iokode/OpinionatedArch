#!/usr/bin/env bash

chroot_run_pacman() {
  if [[ "${OPARCH_VERBOSE:-0}" == "2" ]]; then
    pacman "$@"
  else
    if ! pacman "$@" >/var/log/oparch-pacman.log 2>&1; then
      echo "[ERROR] pacman command failed: pacman $*" >&2
      echo "[ERROR] Last 120 lines from /var/log/oparch-pacman.log:" >&2
      tail -n 120 /var/log/oparch-pacman.log >&2 || true
      return 1
    fi
  fi
}

chroot_prepare_vconsole() {
  printf 'KEYMAP=%s\n' "${CONSOLE_KEYMAP}" > /etc/vconsole.conf
}

chroot_install_base_packages() {
  echo "[INFO] Installing packages..."
  chroot_run_pacman -Sy --noconfirm --needed \
    btrfs-progs \
    cryptsetup \
    grub \
    efibootmgr \
    gum \
    plymouth \
    sudo \
    networkmanager \
    snapper
}

chroot_install_snap_pac() {
  echo "[INFO] Installing packages..."
  chroot_run_pacman -S --noconfirm --needed snap-pac
}
