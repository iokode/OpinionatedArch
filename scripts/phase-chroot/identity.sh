#!/usr/bin/env bash

chroot_configure_locale_and_time() {
  sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
  locale-gen
  printf 'LANG=en_US.UTF-8\n' > /etc/locale.conf

  printf 'KEYMAP=%s\n' "${CONSOLE_KEYMAP}" > /etc/vconsole.conf

  ln -s "/usr/share/zoneinfo/${TIMEZONE}" /etc/localtime
  hwclock --systohc --utc
}

chroot_configure_identity() {
  printf '%s\n' "${HOSTNAME_VALUE}" > /etc/hostname
}
