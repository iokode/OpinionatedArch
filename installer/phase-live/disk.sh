#!/usr/bin/env bash

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
  log "Wiping partition table on ${TARGET_DISK}..."
  run_cmd wipefs -af "${TARGET_DISK}"
  run_cmd sgdisk --zap-all "${TARGET_DISK}"

  log "Creating GPT partitions..."
  run_cmd sgdisk -n 1:0:+1G -t 1:ef00 -c 1:EFI "${TARGET_DISK}"

  if [[ "${SWAP_PARTITION_GB}" -gt 0 ]]; then
    run_cmd sgdisk -n 2:0:+${SWAP_PARTITION_GB}G -t 2:8200 -c 2:SWAP "${TARGET_DISK}"
    run_cmd sgdisk -n 3:0:0 -t 3:8300 -c 3:CRYPTROOT "${TARGET_DISK}"
    EFI_PART="$(partition_path "${TARGET_DISK}" 1)"
    SWAP_PART="$(partition_path "${TARGET_DISK}" 2)"
    ROOT_PART="$(partition_path "${TARGET_DISK}" 3)"
  else
    run_cmd sgdisk -n 2:0:0 -t 2:8300 -c 2:CRYPTROOT "${TARGET_DISK}"
    EFI_PART="$(partition_path "${TARGET_DISK}" 1)"
    SWAP_PART=""
    ROOT_PART="$(partition_path "${TARGET_DISK}" 2)"
  fi

  run_cmd partprobe "${TARGET_DISK}"
  run_cmd udevadm settle

  log "Formatting EFI partition ${EFI_PART}..."
  run_cmd mkfs.fat -F32 "${EFI_PART}"

  log "Creating LUKS2 container on ${ROOT_PART}..."
  run_cmd_with_input "${SHARED_SECRET}" cryptsetup luksFormat --type luks2 --batch-mode --key-file - "${ROOT_PART}"
  run_cmd_with_input "${SHARED_SECRET}" cryptsetup open --key-file - "${ROOT_PART}" cryptroot

  log "Creating Btrfs filesystem..."
  run_cmd mkfs.btrfs -f /dev/mapper/cryptroot

  log "Creating Btrfs subvolumes..."
  run_cmd mount /dev/mapper/cryptroot /mnt
  run_cmd btrfs subvolume create /mnt/@
  run_cmd btrfs subvolume create /mnt/@log
  run_cmd btrfs subvolume create /mnt/@pkg
  run_cmd btrfs subvolume create /mnt/@snapshots

  local user=""
  for user in "${LOGIN_USERS[@]}"; do
    run_cmd btrfs subvolume create "/mnt/@home-${user}"
  done

  run_cmd umount /mnt

  log "Mounting Btrfs subvolumes..."
  run_cmd mount -o subvol=@ /dev/mapper/cryptroot /mnt
  mkdir /mnt/boot
  mkdir /mnt/home
  mkdir /mnt/var
  mkdir /mnt/var/log
  mkdir /mnt/var/cache
  mkdir /mnt/var/cache/pacman
  mkdir /mnt/var/cache/pacman/pkg
  mkdir /mnt/snapshots
  mkdir /mnt/dotfiles

  run_cmd mount -o subvol=@log /dev/mapper/cryptroot /mnt/var/log
  run_cmd mount -o subvol=@pkg /dev/mapper/cryptroot /mnt/var/cache/pacman/pkg
  run_cmd mount -o subvol=@snapshots /dev/mapper/cryptroot /mnt/snapshots
  mkdir /mnt/snapshots/system

  for user in "${LOGIN_USERS[@]}"; do
    mkdir "/mnt/home/${user}"
    run_cmd mount -o subvol=@home-"${user}" /dev/mapper/cryptroot "/mnt/home/${user}"
    mkdir "/mnt/snapshots/${user}"
  done

  run_cmd mount "${EFI_PART}" /mnt/boot

  ROOT_PART_UUID="$(blkid -s UUID -o value "${ROOT_PART}")"
  if [[ -n "${SWAP_PART}" ]]; then
    SWAP_PART_UUID="$(blkid -s UUID -o value "${SWAP_PART}")"
  else
    SWAP_PART_UUID=""
  fi

  log "Disk layout is ready."
}
