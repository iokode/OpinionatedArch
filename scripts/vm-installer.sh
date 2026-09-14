#!/usr/bin/env bash
#
# Builds the debug image, which carries the tools built from this working tree,
# and boots it in a window, so that a change to the installer can be tried by
# hand before it is merged.
#
#     scripts/vm-installer.sh          build the image, boot it, open the installer
#     scripts/vm-installer.sh --disk   boot the disk the last installation left
#
# Rebooting the live system closes its window and opens one booting the disk,
# as --disk does. Powering it off, or closing the window, ends it.
#
# What the image is and how it is built is archiso/debug/build.sh.

set -euo pipefail

readonly ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Kept between runs: the disk and firmware variables of the last guest, so that
# the machine it installed can be booted afterwards.
readonly WORK="${XDG_CACHE_HOME:-$HOME/.cache}/oparch-vm-installer"
readonly IMAGE_DIR="$WORK/image"
readonly DISK="$WORK/disk.qcow2"
readonly VARS="$WORK/firmware-vars.fd"

. "$ROOT/scripts/lib/guest.sh"

say() {
    printf '==> %s\n' "$*" >&2
}

usage() {
    printf 'Usage: %s [--disk]\n' "$0" >&2
}

disk_only=false
while [ "$#" -gt 0 ]; do
    case "$1" in
        --disk)
            disk_only=true
            shift
            ;;
        *)
            usage
            exit 2
            ;;
    esac
done

build_image() {
    rm -rf "$IMAGE_DIR"
    "$ROOT/archiso/debug/build.sh" "$IMAGE_DIR"
    image="$(ls "$IMAGE_DIR"/*.iso)"
}

# A disk with nothing on it, and firmware variables of its own that the
# installation registers its boot entry in.
prepare_machine() {
    qemu-img create -f qcow2 "$DISK" "$GUEST_DISK_SIZE" >/dev/null
    cp "$OVMF_VARS" "$VARS"
}

# The live system, in a window. The kernel and the initramfs are taken out of
# the image and handed over, because that is what lets the serial line be a
# console too, and what the kernel writes there is how a reboot is told from a
# power off.
#
# A reboot ends QEMU rather than restarting it. A guest whose kernel is handed
# in from outside starts that same kernel again on every reset, which is the
# live system, and never reaches the entry the installation registered; so what
# follows a reboot is decided once QEMU has gone, at the end of this script.
boot_live() {
    local kernel="$WORK/vmlinuz-linux"
    local initramfs="$WORK/initramfs-linux.img"
    local label

    bsdtar -xOf "$image" arch/boot/x86_64/vmlinuz-linux >"$kernel"
    bsdtar -xOf "$image" arch/boot/x86_64/initramfs-linux.img >"$initramfs"
    label="$(blkid -s LABEL -o value "$image")"

    guest_acceleration
    guest_network present

    rm -f "$WORK/serial.log"
    qemu-system-x86_64 \
        "${GUEST_ACCELERATION[@]}" \
        -m "$GUEST_MEMORY" -smp "$GUEST_CPUS" \
        -display gtk -serial "file:$WORK/serial.log" -no-reboot \
        "${GUEST_NETWORK[@]}" \
        -drive "if=pflash,format=raw,readonly=on,file=$OVMF_CODE" \
        -drive "if=pflash,format=raw,file=$VARS" \
        -drive "if=virtio,format=qcow2,file=$DISK" \
        -drive "media=cdrom,readonly=on,file=$image" \
        -kernel "$kernel" -initrd "$initramfs" \
        -append "archisobasedir=arch archisolabel=$label console=tty0 console=ttyS0,115200"
}

# The disk the last installation left, booted on its own the way the machine
# would be: by the entry the installation registered with the firmware.
boot_disk() {
    if [ ! -f "$DISK" ] || [ ! -f "$VARS" ]; then
        say "There is no disk from a previous run in $WORK"
        exit 1
    fi
    guest_acceleration
    guest_network present
    qemu-system-x86_64 \
        "${GUEST_ACCELERATION[@]}" \
        -m "$GUEST_MEMORY" -smp "$GUEST_CPUS" \
        -display gtk \
        "${GUEST_NETWORK[@]}" \
        -drive "if=pflash,format=raw,readonly=on,file=$OVMF_CODE" \
        -drive "if=pflash,format=raw,file=$VARS" \
        -drive "if=virtio,format=qcow2,file=$DISK"
}

mkdir -p "$WORK"

if ! qemu-system-x86_64 -display help | grep -qx gtk; then
    say "This QEMU has no window to draw in. On Arch, qemu-ui-gtk is what gives it one."
    exit 1
fi

if "$disk_only"; then
    boot_disk
    exit 0
fi

build_image
prepare_machine

say "Booting $(basename "$image")"
say "Rebooting it boots the disk it installed. Powering it off, or closing the window, ends it."
boot_live

# The kernel says it is restarting on its serial console before it resets the
# machine, and says nothing of the kind when it powers off or when the window
# is closed under it.
if grep -q 'reboot: Restarting system' "$WORK/serial.log"; then
    say "The live system rebooted; booting the disk it installed"
    boot_disk
fi
