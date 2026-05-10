#!/usr/bin/env bash

chroot_configure_initramfs() {
  if [[ "${INCLUDE_RETURN_MESSAGE}" == "yes" ]]; then
    sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect microcode kms keyboard keymap block opinionatedarch-plymouth-locale plymouth opinionatedarch-plymouth-font encrypt filesystems)/' /etc/mkinitcpio.conf
  else
    sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect microcode kms keyboard keymap block encrypt filesystems)/' /etc/mkinitcpio.conf
  fi
  mkinitcpio -P
}
