#!/usr/bin/env bash

chroot_set_or_replace_config_key() {
  local file="$1"
  local key="$2"
  local value="$3"

  if grep -q "^${key}=" "${file}"; then
    sed -i "s|^${key}=.*|${key}=${value}|" "${file}"
  else
    printf '%s=%s\n' "${key}" "${value}" >> "${file}"
  fi
}

chroot_configure_swap_encryption() {
  if [[ -z "${SWAP_PART_UUID}" ]]; then
    return 0
  fi

  cat > /etc/crypttab <<CRYPTTAB_EOF
cryptswap UUID=${SWAP_PART_UUID} /dev/urandom swap,cipher=aes-xts-plain64,size=256
CRYPTTAB_EOF

  printf '/dev/mapper/cryptswap none swap defaults 0 0\n' >> /etc/fstab
}

chroot_configure_plymouth_defaults() {
  install -d -m 755 /etc/opinionatedarch
  cat > /etc/opinionatedarch/ownership.env <<OWNERSHIP_EOF
OWNER_NAME=${OWNER_NAME}
OWNER_PHONE=${OWNER_PHONE}
OWNER_EMAIL=${OWNER_EMAIL}
OWNER_RETURN_ADDRESS=${OWNER_RETURN_ADDRESS}
INCLUDE_LOGO=${INCLUDE_LOGO}
OWNERSHIP_EOF

  if [[ "${INCLUDE_LOGO}" == "yes" ]]; then
    install -d -m 755 /usr/share/plymouth/themes/opinionatedarch
    cp /usr/opinionatedarch/tmp/logo.png /usr/share/plymouth/themes/opinionatedarch/logo.png
  fi

  plymouth-set-default-theme bgrt
}

chroot_configure_initramfs() {
  sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect microcode kms keyboard keymap block plymouth encrypt filesystems)/' /etc/mkinitcpio.conf
  mkinitcpio -P
}

chroot_configure_grub() {
  local timeout_style="hidden"
  local timeout_value="1"
  if [[ "${STARTUP_POLICY}" == "manual" ]]; then
    timeout_style="menu"
    timeout_value="-1"
  fi

  chroot_set_or_replace_config_key /etc/default/grub GRUB_DEFAULT '0'
  chroot_set_or_replace_config_key /etc/default/grub GRUB_TIMEOUT_STYLE "${timeout_style}"
  chroot_set_or_replace_config_key /etc/default/grub GRUB_TIMEOUT "${timeout_value}"
  chroot_set_or_replace_config_key /etc/default/grub GRUB_CMDLINE_LINUX_DEFAULT '"quiet splash"'
  chroot_set_or_replace_config_key /etc/default/grub GRUB_CMDLINE_LINUX "\"cryptdevice=UUID=${ROOT_PART_UUID}:cryptroot root=/dev/mapper/cryptroot\""

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
