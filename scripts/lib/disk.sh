#!/usr/bin/env bash

# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

# shellcheck disable=SC2034
EFI_PART=""
# shellcheck disable=SC2034
SWAP_PART=""
# shellcheck disable=SC2034
ROOT_PART=""
# shellcheck disable=SC2034
ROOT_PART_UUID=""
# shellcheck disable=SC2034
SWAP_PART_UUID=""

partition_path() {
  local disk="$1"
  local index="$2"

  if [[ "${disk}" =~ (nvme|mmcblk|loop) ]]; then
    printf '%sp%s' "${disk}" "${index}"
  else
    printf '%s%s' "${disk}" "${index}"
  fi
}

prepare_disk_layout() {
  log "Wiping partition table on ${TARGET_DISK}"
  wipefs -af "${TARGET_DISK}"
  sgdisk --zap-all "${TARGET_DISK}"

  log "Creating GPT partitions"
  sgdisk -n 1:0:+1G -t 1:ef00 -c 1:EFI "${TARGET_DISK}"

  if [[ "${SWAP_PARTITION_GB}" -gt 0 ]]; then
    sgdisk -n 2:0:+${SWAP_PARTITION_GB}G -t 2:8200 -c 2:SWAP "${TARGET_DISK}"
    sgdisk -n 3:0:0 -t 3:8300 -c 3:CRYPTROOT "${TARGET_DISK}"
    EFI_PART="$(partition_path "${TARGET_DISK}" 1)"
    SWAP_PART="$(partition_path "${TARGET_DISK}" 2)"
    ROOT_PART="$(partition_path "${TARGET_DISK}" 3)"
  else
    sgdisk -n 2:0:0 -t 2:8300 -c 2:CRYPTROOT "${TARGET_DISK}"
    EFI_PART="$(partition_path "${TARGET_DISK}" 1)"
    SWAP_PART=""
    ROOT_PART="$(partition_path "${TARGET_DISK}" 2)"
  fi

  partprobe "${TARGET_DISK}"
  udevadm settle

  log "Formatting EFI partition ${EFI_PART}"
  mkfs.fat -F32 "${EFI_PART}"

  log "Creating LUKS2 container on ${ROOT_PART}"
  printf '%s' "${SHARED_SECRET}" | cryptsetup luksFormat --type luks2 --batch-mode --key-file - "${ROOT_PART}"
  printf '%s' "${SHARED_SECRET}" | cryptsetup open --key-file - "${ROOT_PART}" cryptroot

  log "Creating Btrfs filesystem"
  mkfs.btrfs -f /dev/mapper/cryptroot

  log "Creating Btrfs subvolumes"
  mount /dev/mapper/cryptroot /mnt
  btrfs subvolume create /mnt/@
  btrfs subvolume create /mnt/@log
  btrfs subvolume create /mnt/@pkg
  btrfs subvolume create /mnt/@snapshots

  local user=""
  for user in "${LOGIN_USERS[@]}"; do
    btrfs subvolume create "/mnt/@home-${user}"
  done

  umount /mnt

  log "Mounting Btrfs subvolumes"
  mount -o subvol=@ /dev/mapper/cryptroot /mnt
  mkdir -p /mnt/boot
  mkdir -p /mnt/home
  mkdir -p /mnt/var/log
  mkdir -p /mnt/var/cache/pacman/pkg
  mkdir -p /mnt/snapshots
  mkdir -p /mnt/dotfiles

  mount -o subvol=@log /dev/mapper/cryptroot /mnt/var/log
  mount -o subvol=@pkg /dev/mapper/cryptroot /mnt/var/cache/pacman/pkg
  mount -o subvol=@snapshots /dev/mapper/cryptroot /mnt/snapshots
  mkdir -p /mnt/snapshots/system

  for user in "${LOGIN_USERS[@]}"; do
    mkdir -p "/mnt/home/${user}"
    mount -o subvol=@home-"${user}" /dev/mapper/cryptroot "/mnt/home/${user}"
    mkdir -p "/mnt/snapshots/${user}"
  done

  mount "${EFI_PART}" /mnt/boot

  ROOT_PART_UUID="$(blkid -s UUID -o value "${ROOT_PART}")"
  if [[ -n "${SWAP_PART}" ]]; then
    SWAP_PART_UUID="$(blkid -s UUID -o value "${SWAP_PART}")"
  else
    SWAP_PART_UUID=""
  fi

  log "Disk layout is ready."
}
