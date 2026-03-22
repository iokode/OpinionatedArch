#!/usr/bin/env bash

# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

configure_installed_system() {
  log "Running chroot configuration"

  arch-chroot /mnt /bin/bash -s <<'CHROOT_EOF'
set -euo pipefail

source /root/oparch-install.env

# Ensure this exists before package hooks trigger mkinitcpio.
printf 'KEYMAP=%s\n' "${CONSOLE_KEYMAP}" > /etc/vconsole.conf

run_pacman() {
  if [[ "${OPARCH_VERBOSE:-0}" == "1" ]]; then
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

set_or_replace_config_key() {
  local file="$1"
  local key="$2"
  local value="$3"

  if grep -q "^${key}=" "${file}"; then
    sed -i "s|^${key}=.*|${key}=${value}|" "${file}"
  else
    printf '%s=%s\n' "${key}" "${value}" >> "${file}"
  fi
}

install_post_chroot_packages() {
  echo "[INFO] Installing packages..."
  run_pacman -Sy --noconfirm --needed \
    btrfs-progs \
    cryptsetup \
    grub \
    efibootmgr \
    plymouth \
    sudo \
    networkmanager \
    snapper
}

install_snap_pac() {
  echo "[INFO] Installing packages..."
  run_pacman -S --noconfirm --needed snap-pac
}

configure_locale_and_time() {
  sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
  locale-gen
  printf 'LANG=en_US.UTF-8\n' > /etc/locale.conf

  printf 'KEYMAP=%s\n' "${CONSOLE_KEYMAP}" > /etc/vconsole.conf

  ln -sf "/usr/share/zoneinfo/${TIMEZONE}" /etc/localtime
  hwclock --systohc --utc
}

configure_identity() {
  printf '%s\n' "${HOSTNAME_VALUE}" > /etc/hostname
}

configure_users_and_groups() {
  groupadd dotfiles
  groupadd login-users

  install -d -m 2775 -o root -g dotfiles /dotfiles
  install -d -m 2775 -o root -g dotfiles /dotfiles/config

  IFS=',' read -r -a login_users <<< "${LOGIN_USERS_CSV}"

  local user
  for user in "${login_users[@]}"; do
    useradd -M -d "/home/${user}" -G wheel,dotfiles,login-users -s /bin/bash "${user}"
    chown -R "${user}:${user}" "/home/${user}"

    printf '%s:%s\n' "${user}" "${SHARED_SECRET}" | chpasswd
  done

  passwd -l root

  cat > /etc/sudoers.d/10-wheel <<'SUDO_EOF'
%wheel ALL=(ALL:ALL) ALL
SUDO_EOF
  chmod 440 /etc/sudoers.d/10-wheel
}

configure_network_stack() {
  systemctl enable NetworkManager.service
  systemctl enable systemd-resolved.service
}

configure_snapshots() {
  mkdir -p /snapshots/system

  IFS=',' read -r -a login_users <<< "${LOGIN_USERS_CSV}"
  local user
  for user in "${login_users[@]}"; do
    mkdir -p "/snapshots/${user}"
  done

  cat > /usr/local/bin/oparch-snapshot-system <<'SYSTEM_SNAP_EOF'
#!/usr/bin/env bash
set -euo pipefail

reason="${1:-}"
if [[ -z "${reason}" ]]; then
  echo "Usage: oparch-snapshot-system <reason>" >&2
  exit 1
fi

timestamp="$(date +%Y%m%d-%H%M%S)"
slug="$(printf '%s' "${reason}" | tr '[:space:]/' '__' | tr -cd '[:alnum:]_.-')"
[[ -n "${slug}" ]] || slug="manual"
target="/snapshots/system/${timestamp}-${slug}"

btrfs subvolume snapshot -r / "${target}"
SYSTEM_SNAP_EOF
  chmod 755 /usr/local/bin/oparch-snapshot-system

  cat > /usr/local/bin/oparch-snapshot-home <<'HOME_SNAP_EOF'
#!/usr/bin/env bash
set -euo pipefail

target_user="${1:-}"
reason="${2:-}"
if [[ -z "${target_user}" || -z "${reason}" ]]; then
  echo "Usage: oparch-snapshot-home <user> <reason>" >&2
  exit 1
fi

source_subvol="/home/${target_user}"
target_dir="/snapshots/${target_user}"
[[ -d "${source_subvol}" ]] || { echo "Home subvolume not found: ${source_subvol}" >&2; exit 1; }
mkdir -p "${target_dir}"

timestamp="$(date +%Y%m%d-%H%M%S)"
slug="$(printf '%s' "${reason}" | tr '[:space:]/' '__' | tr -cd '[:alnum:]_.-')"
[[ -n "${slug}" ]] || slug="manual"
target="${target_dir}/${timestamp}-${slug}"

btrfs subvolume snapshot -r "${source_subvol}" "${target}"
HOME_SNAP_EOF
  chmod 755 /usr/local/bin/oparch-snapshot-home
}

configure_swap_encryption() {
  if [[ -z "${SWAP_PART_UUID}" ]]; then
    return 0
  fi

  cat > /etc/crypttab <<CRYPTTAB_EOF
cryptswap UUID=${SWAP_PART_UUID} /dev/urandom swap,cipher=aes-xts-plain64,size=256
CRYPTTAB_EOF

  printf '/dev/mapper/cryptswap none swap defaults 0 0\n' >> /etc/fstab
}

configure_plymouth_defaults() {
  install -d -m 755 /etc/opinionatedarch
  cat > /etc/opinionatedarch/ownership.env <<OWNERSHIP_EOF
OWNER_NAME=${OWNER_NAME}
OWNER_PHONE=${OWNER_PHONE}
OWNER_EMAIL=${OWNER_EMAIL}
OWNER_RETURN_ADDRESS=${OWNER_RETURN_ADDRESS}
INCLUDE_LOGO=${INCLUDE_LOGO}
OWNERSHIP_EOF

  if [[ "${INCLUDE_LOGO}" == "yes" && -f /tmp/oparch-logo.png ]]; then
    install -d -m 755 /usr/share/plymouth/themes/opinionatedarch
    cp -f /tmp/oparch-logo.png /usr/share/plymouth/themes/opinionatedarch/logo.png
  fi

  plymouth-set-default-theme bgrt
}

configure_initramfs() {
  sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect microcode kms keyboard keymap block plymouth encrypt filesystems)/' /etc/mkinitcpio.conf
  mkinitcpio -P
}

configure_grub() {
  local timeout_value="2"
  if [[ "${MACHINE_ROLE}" == "MainPC" ]]; then
    timeout_value="-1"
  fi

  set_or_replace_config_key /etc/default/grub GRUB_DEFAULT '0'
  set_or_replace_config_key /etc/default/grub GRUB_TIMEOUT "${timeout_value}"
  set_or_replace_config_key /etc/default/grub GRUB_CMDLINE_LINUX_DEFAULT '"quiet splash"'
  set_or_replace_config_key /etc/default/grub GRUB_CMDLINE_LINUX "\"cryptdevice=UUID=${ROOT_PART_UUID}:cryptroot root=/dev/mapper/cryptroot\""

  cat > /etc/grub.d/40_custom <<'GRUB_CUSTOM_EOF'
#!/bin/sh
exec tail -n +3 $0

menuentry 'Netboot Arch' {
  search --no-floppy --file --set=root /EFI/OpinionatedArch/netbootx64.efi
  chainloader /EFI/OpinionatedArch/netbootx64.efi
}

menuentry 'EFI firmware' {
  fwsetup
}

menuentry 'Shutdown' {
  halt
}
GRUB_CUSTOM_EOF
  chmod +x /etc/grub.d/40_custom

  grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=OpinionatedArch
  grub-mkconfig -o /boot/grub/grub.cfg
}

install_post_chroot_packages
configure_locale_and_time
configure_identity
configure_users_and_groups
configure_network_stack
configure_snapshots
configure_swap_encryption
configure_plymouth_defaults
configure_initramfs
configure_grub
install_snap_pac

rm -f /root/oparch-install.env
CHROOT_EOF

  log "Chroot configuration finished."
}
