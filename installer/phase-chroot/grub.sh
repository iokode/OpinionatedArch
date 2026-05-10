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

chroot_configure_grub() {
  local timeout_style="hidden"
  local timeout_value="1"
  local linux_default="quiet"
  if [[ "${STARTUP_POLICY}" == "manual" ]]; then
    timeout_style="menu"
    timeout_value="-1"
  fi
  if [[ "${INCLUDE_RETURN_MESSAGE}" == "yes" ]]; then
    linux_default="quiet splash"
  fi

  chroot_set_or_replace_config_key /etc/default/grub GRUB_DEFAULT '0'
  chroot_set_or_replace_config_key /etc/default/grub GRUB_TIMEOUT_STYLE "${timeout_style}"
  chroot_set_or_replace_config_key /etc/default/grub GRUB_TIMEOUT "${timeout_value}"
  chroot_set_or_replace_config_key /etc/default/grub GRUB_CMDLINE_LINUX_DEFAULT "\"${linux_default}\""
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
