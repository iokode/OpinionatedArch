#!/usr/bin/env bash

stage_netboot_binary() {
  local netboot_url="https://archlinux.org/static/netboot/ipxe-arch.efi"
  local netboot_local_path="/tmp/oparch/netbootx64.efi"

  log "Downloading Arch netboot EFI binary..."
  run_cmd curl -fL --retry 2 --connect-timeout 10 -o "${netboot_local_path}" "${netboot_url}"
  run_cmd mkdir /mnt/boot/EFI
  run_cmd mkdir /mnt/boot/EFI/OpinionatedArch
  run_cmd cp "${netboot_local_path}" /mnt/boot/EFI/OpinionatedArch/netbootx64.efi
  log "Staged ${netboot_local_path} to ESP."
}

stage_live_temp_assets_for_repo() {
  run_cmd mkdir -p /mnt/usr/oparch/tmp
  run_cmd cp -a /tmp/oparch/. /mnt/usr/oparch/tmp/
  log "Staged /tmp/oparch to /mnt/usr/oparch/tmp for chroot."
}

stage_install_repo() {
  run_cmd mkdir -p /mnt/usr/oparch
  run_cmd cp -a "${OPARCH_REPO_ROOT}/." /mnt/usr/oparch/
  run_cmd chown -R root:root /mnt/usr/oparch
  run_cmd find /mnt/usr/oparch -type d -exec chmod 755 {} +
  run_cmd find /mnt/usr/oparch -type f -exec chmod 644 {} +
  log "Staged installer repository to /usr/oparch."
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
  elif [[ "${CPU_VENDOR}" == "AMD" ]]; then
    microcode_package="amd-ucode"
  fi

  run_cmd mkdir /mnt/etc
  printf 'KEYMAP=%s\n' "${CONSOLE_KEYMAP}" > /mnt/etc/vconsole.conf

  log "Installing base system..."
  if [[ -n "${microcode_package}" ]]; then
    run_pkg_cmd pacstrap -K /mnt \
      base \
      linux \
      linux-headers \
      linux-firmware \
      mkinitcpio \
      iptables-nft \
      "${microcode_package}"
  else
    run_pkg_cmd pacstrap -K /mnt \
      base \
      linux \
      linux-headers \
      linux-firmware \
      mkinitcpio \
      iptables-nft
  fi

  log "Generating fstab..."
  if [[ "${OPARCH_VERBOSE:-0}" == "0" ]]; then
    if ! genfstab -U /mnt > /mnt/etc/fstab 2>/tmp/oparch-cmd.log; then
      warn "Command failed: genfstab -U /mnt"
      tail -n 120 /tmp/oparch-cmd.log >&4 || true
      return 1
    fi
  else
    genfstab -U /mnt > /mnt/etc/fstab
  fi

  stage_netboot_binary
  stage_install_repo
  stage_live_temp_assets_for_repo
  write_install_state

  log "Base system installed."
}
