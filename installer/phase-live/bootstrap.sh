#!/usr/bin/env bash

stage_netboot_binary() {
  local netboot_url="https://archlinux.org/static/netboot/ipxe-arch.efi"
  local netboot_local_path="/tmp/oparch/netbootx64.efi"

  working "Downloading Arch netboot EFI binary..." curl -fL --retry 2 --connect-timeout 10 -o "${netboot_local_path}" "${netboot_url}"
  run_cmd mkdir /mnt/boot/EFI
  run_cmd mkdir /mnt/boot/EFI/OpinionatedArch
  run_cmd cp "${netboot_local_path}" /mnt/boot/EFI/OpinionatedArch/netbootx64.efi
  log "Staged ${netboot_local_path} to ESP."
}

stage_live_temp_assets_for_repo() {
  run_cmd mkdir -p /mnt/usr/opinionatedarch/tmp
  working "Staging /tmp/oparch for chroot..." cp -a /tmp/oparch/. /mnt/usr/opinionatedarch/tmp/
  log "Staged /tmp/oparch to /mnt/usr/opinionatedarch/tmp for chroot."
}

stage_install_repo() {
  run_cmd mkdir -p /mnt/usr/opinionatedarch
  working "Staging installer repository..." cp -a "${OPARCH_REPO_ROOT}/." /mnt/usr/opinionatedarch/
  run_cmd chown -R root:root /mnt/usr/opinionatedarch
  run_cmd find /mnt/usr/opinionatedarch -type d -exec chmod 755 {} +
  run_cmd find /mnt/usr/opinionatedarch -type f -exec chmod 644 {} +
  log "Staged installer repository to /usr/opinionatedarch."
}

write_install_state() {
  local login_users_csv
  login_users_csv="$(join_by ',' "${LOGIN_USERS[@]}")"

  {
    printf 'STARTUP_POLICY=%q\n' "${STARTUP_POLICY}"
    printf 'UCODE_PACKAGE=%q\n' "${UCODE_PACKAGE}"
    printf 'GPU_DRIVER=%q\n' "${GPU_DRIVER}"
    printf 'ZRAM_SWAP_GB=%q\n' "${ZRAM_SWAP_GB}"
    printf 'SWAP_PARTITION_GB=%q\n' "${SWAP_PARTITION_GB}"
    printf 'LOGIN_USERS_CSV=%q\n' "${login_users_csv}"
    printf 'SHARED_SECRET=%q\n' "${SHARED_SECRET}"
    printf 'CONSOLE_KEYMAP=%q\n' "${CONSOLE_KEYMAP}"
    printf 'TIMEZONE=%q\n' "${TIMEZONE}"
    printf 'HOSTNAME_VALUE=%q\n' "${HOSTNAME_VALUE}"
    printf 'INCLUDE_RETURN_MESSAGE=%q\n' "${INCLUDE_RETURN_MESSAGE}"
    printf 'OWNER_NAME=%q\n' "${OWNER_NAME}"
    printf 'OWNER_PHONE=%q\n' "${OWNER_PHONE}"
    printf 'OWNER_EMAIL=%q\n' "${OWNER_EMAIL}"
    printf 'OWNER_RETURN_ADDRESS=%q\n' "${OWNER_RETURN_ADDRESS}"
    printf 'INCLUDE_LOGO=%q\n' "${INCLUDE_LOGO}"
    printf 'ROOT_PART_UUID=%q\n' "${ROOT_PART_UUID}"
    printf 'SWAP_PART_UUID=%q\n' "${SWAP_PART_UUID}"
    printf 'OPARCH_VERBOSE=%q\n' "${OPARCH_VERBOSE:-0}"
  } > /mnt/root/oparch-install.env
  run_cmd chmod 600 /mnt/root/oparch-install.env
}

bootstrap_base_system() {
  local -a packages=(
    base
    linux
    linux-headers
    linux-firmware
    mkinitcpio
    iptables-nft
    btrfs-progs
    cryptsetup
    grub
    efibootmgr
    gum
    fzf
    sudo
    networkmanager
    snapper
    snap-pac
  )

  if [[ "${UCODE_PACKAGE}" != "none" ]]; then
    packages+=("${UCODE_PACKAGE}")
  fi

  if [[ "${GPU_DRIVER}" == "nvidia" ]]; then
    packages+=(nvidia)
  elif [[ "${GPU_DRIVER}" == "nvidia-open" ]]; then
    packages+=(nvidia-open)
  fi

  if [[ "${INCLUDE_RETURN_MESSAGE}" == "yes" ]]; then
    packages+=(plymouth)
  fi

  run_pkg_cmd --title "Installing base system..." pacstrap -K /mnt "${packages[@]}"

  run_cmd bash -c 'genfstab -U /mnt > /mnt/etc/fstab'

  stage_netboot_binary
  stage_install_repo
  stage_live_temp_assets_for_repo
  write_install_state

  log "Base system installed."
}
