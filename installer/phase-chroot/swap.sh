#!/usr/bin/env bash

chroot_configure_swap_encryption() {
  if [[ -z "${SWAP_PART_UUID}" ]]; then
    return 0
  fi

  cat > /etc/crypttab <<CRYPTTAB_EOF
cryptswap UUID=${SWAP_PART_UUID} /dev/urandom swap,cipher=aes-xts-plain64,size=256
CRYPTTAB_EOF

  printf '/dev/mapper/cryptswap none swap defaults 0 0\n' >> /etc/fstab
}
