#!/usr/bin/env bash

# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

stage_logo_asset_if_present() {
  mkdir -p /mnt/tmp
  if [[ "${INCLUDE_LOGO}" == "yes" && -f "${LOGO_LOCAL_PATH}" ]]; then
    cp -f "${LOGO_LOCAL_PATH}" /mnt/tmp/oparch-logo.png
    log "Staged logo asset into target system."
  fi
}

stage_netboot_binary_if_present() {
  mkdir -p /mnt/boot/EFI/OpinionatedArch
  if [[ -f "/tmp/netbootx64.efi" ]]; then
    cp -f /tmp/netbootx64.efi /mnt/boot/EFI/OpinionatedArch/netbootx64.efi
    log "Staged /tmp/netbootx64.efi to ESP."
  else
    warn "Netboot binary not found at /tmp/netbootx64.efi. GRUB entry will exist but file is missing."
  fi
}

write_install_state() {
  local login_users_csv
  login_users_csv="$(join_by ',' "${LOGIN_USERS[@]}")"

  {
    printf 'MACHINE_ROLE=%q\n' "${MACHINE_ROLE}"
    printf 'CPU_VENDOR=%q\n' "${CPU_VENDOR}"
    printf 'ZRAM_SWAP_GB=%q\n' "${ZRAM_SWAP_GB}"
    printf 'SWAP_PARTITION_GB=%q\n' "${SWAP_PARTITION_GB}"
    printf 'LOGIN_USERS_CSV=%q\n' "${login_users_csv}"
    printf 'SHARED_SECRET=%q\n' "${SHARED_SECRET}"
    printf 'CONSOLE_KEYMAP=%q\n' "${CONSOLE_KEYMAP}"
    printf 'TIMEZONE=%q\n' "${TIMEZONE}"
    printf 'HOSTNAME_VALUE=%q\n' "${HOSTNAME_VALUE}"
    printf 'OWNER_NAME=%q\n' "${OWNER_NAME}"
    printf 'OWNER_PHONE=%q\n' "${OWNER_PHONE}"
    printf 'OWNER_EMAIL=%q\n' "${OWNER_EMAIL}"
    printf 'OWNER_RETURN_ADDRESS=%q\n' "${OWNER_RETURN_ADDRESS}"
    printf 'INCLUDE_LOGO=%q\n' "${INCLUDE_LOGO}"
    printf 'ROOT_PART_UUID=%q\n' "${ROOT_PART_UUID}"
    printf 'SWAP_PART_UUID=%q\n' "${SWAP_PART_UUID}"
    printf 'OPARCH_VERBOSE=%q\n' "${OPARCH_VERBOSE:-0}"
  } > /mnt/root/oparch-install.env
  chmod 600 /mnt/root/oparch-install.env
}

bootstrap_base_system() {
  local microcode_package=""
  if [[ "${CPU_VENDOR}" == "Intel" ]]; then
    microcode_package="intel-ucode"
  else
    microcode_package="amd-ucode"
  fi

  # Pre-create vconsole to avoid mkinitcpio hook errors during package hooks.
  mkdir -p /mnt/etc
  printf 'KEYMAP=%s\n' "${CONSOLE_KEYMAP}" > /mnt/etc/vconsole.conf

  log "Installing packages..."
  if [[ "${OPARCH_VERBOSE:-0}" == "1" ]]; then
    pacstrap -K /mnt \
      base \
      linux \
      linux-headers \
      linux-firmware \
      mkinitcpio \
      iptables-nft \
      "${microcode_package}"
  else
    if ! pacstrap -K /mnt \
      base \
      linux \
      linux-headers \
      linux-firmware \
      mkinitcpio \
      iptables-nft \
      "${microcode_package}" >/tmp/oparch-pacstrap.log 2>&1; then
      warn "pacstrap failed. Showing last 120 lines."
      tail -n 120 /tmp/oparch-pacstrap.log >&2 || true
      return 1
    fi
  fi

  log "Generating fstab"
  genfstab -U /mnt > /mnt/etc/fstab

  stage_logo_asset_if_present
  stage_netboot_binary_if_present
  write_install_state

  log "Base system installed."
}
