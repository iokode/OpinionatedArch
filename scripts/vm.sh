#!/usr/bin/env bash
#
# Boots, in a window, a machine installed from the debug image, with the tools
# built from this working tree in place of the ones the installation took from
# the published repository, so that a change to them can be tried on an
# installed system before it is merged.
#
#     scripts/vm.sh
#
# Every run installs the machine again, on a new disk: the debug image is built
# and booted in a window, and the installer it carries installs the machine
# there, with the answers in scripts/vm-config.yaml, while this script drives it
# over the serial line. It installs over the network, because the debug image
# carries no repository of its own. Once that is done the window closes, and one
# opens on the installed disk.
#
# The tools are copied over the packaged ones, so updating their packages
# inside the machine puts the published ones back.
#
# What the image is and how it is built is archiso/debug/build.sh.

set -euo pipefail

readonly ROOT="$(cd "$(dirname "$0")/.." && pwd)"
readonly CONFIG="$ROOT/scripts/vm-config.yaml"

readonly WORK="${XDG_CACHE_HOME:-$HOME/.cache}/oparch-vm"
readonly IMAGE_DIR="$WORK/image"
readonly SHARE="$WORK/share"
readonly DISK="$WORK/disk.qcow2"
readonly VARS="$WORK/firmware-vars.fd"

# How long an installation over the network is waited for.
readonly WAIT_INSTALL=3600

. "$ROOT/scripts/lib/guest.sh"

say() {
    printf '==> %s\n' "$*" >&2
}

# The shared secret and the work contexts, as the answers give them, to say how
# the installed machine is entered.
shared_secret() {
    sed -n 's/^shared_secret:[[:space:]]*//p' "$CONFIG" | sed -e 's/^"//' -e 's/"$//'
}

work_contexts() {
    sed -n '/^work_contexts:/,/^[^[:space:]-]/s/^[[:space:]]*-[[:space:]]*//p' "$CONFIG" |
        paste -sd, - | sed 's/,/, /g'
}

build_image() {
    rm -rf "$IMAGE_DIR"
    "$ROOT/archiso/debug/build.sh" "$IMAGE_DIR"
    image="$(ls "$IMAGE_DIR"/*.iso)"
}

# A disk with nothing on it, firmware variables of its own that the
# installation registers its boot entry in, and the answers the machine is
# installed with, in the directory the guest mounts.
prepare_machine() {
    qemu-img create -f qcow2 "$DISK" "$GUEST_DISK_SIZE" >/dev/null
    cp "$OVMF_VARS" "$VARS"

    rm -rf "$SHARE"
    mkdir -p "$SHARE"
    cp "$CONFIG" "$SHARE/config.yaml"
}

# The live system, in a window, driven over its serial line: the kernel and the
# initramfs are taken out of the image and handed over, because that is what
# lets the serial line be a console too.
#
# The image logs root in on the first console, and that login starts the
# interactive installer. It is masked on the kernel command line, so the first
# console, which is what the window shows, is the unattended installation's
# from the moment the system starts.
boot_live() {
    local kernel="$WORK/vmlinuz-linux"
    local initramfs="$WORK/initramfs-linux.img"
    local label

    bsdtar -xOf "$image" arch/boot/x86_64/vmlinuz-linux >"$kernel"
    bsdtar -xOf "$image" arch/boot/x86_64/initramfs-linux.img >"$initramfs"
    label="$(blkid -s LABEL -o value "$image")"

    guest_acceleration
    guest_network present

    guest_start "$WORK/install.log" "$WORK/install.in" \
        "${GUEST_ACCELERATION[@]}" \
        -m "$GUEST_MEMORY" -smp "$GUEST_CPUS" \
        -display gtk -serial stdio \
        "${GUEST_NETWORK[@]}" \
        -drive "if=pflash,format=raw,readonly=on,file=$OVMF_CODE" \
        -drive "if=pflash,format=raw,file=$VARS" \
        -drive "if=virtio,format=qcow2,file=$DISK" \
        -drive "media=cdrom,readonly=on,file=$image" \
        -virtfs "local,path=$SHARE,mount_tag=$SHARE_TAG,security_model=none,readonly=on" \
        -kernel "$kernel" -initrd "$initramfs" \
        -append "archisobasedir=arch archisolabel=$label console=tty0 console=ttyS0,115200 systemd.mask=getty@tty1.service"
}

# Installs the machine, puts the tools from this tree over the packaged ones
# while the installation is still mounted, and powers the live system off. The
# disk is only safe to boot once the guest that wrote it has gone.
install_machine() {
    guest_wait_for_shell || return 1
    guest_quieten || return 1

    guest_check "the answers reach the guest" \
        "mkdir -p $SHARE_MOUNT \
            && mount -t 9p -o trans=virtio,version=9p2000.L,ro $SHARE_TAG $SHARE_MOUNT" || return 1

    # The installation runs on the first console, which is what the window
    # shows. What the kernel wrote there while the system started is cleared
    # first.
    guest_check "the first console is cleared for the installation" \
        "printf '\033c' >/dev/tty1" || return 1

    # The mask on the first console's login is kept under /run, and pacstrap
    # gives the target the live system's /run: left there, it stops the systemd
    # package enabling the login on the installed system's first console. It is
    # removed before the installation, and the live console stays as it is,
    # because systemd read the mask when the system started.
    guest_check "the mask on the first console's login is out of the installation's way" \
        "rm /run/systemd/generator.early/getty@tty1.service" || return 1

    # Under `script`, which gives the installer a terminal of its own, so what it
    # writes reaches the window as it is written, and keeps a copy of it, so a
    # failure can still be read once the window has gone.
    if ! guest_check "the installer installs the machine" \
            "script -qefc 'oparch-installer --config $SHARE_MOUNT/config.yaml' /run/oparch-install.log \
                </dev/null >/dev/tty1" "$WAIT_INSTALL"; then
        guest_run "cat /run/oparch-install.log" || :
        return 1
    fi

    guest_check "the tools from this tree are where the installation put the packaged ones" \
        "install -m 755 /usr/bin/oparch-return-message-render /mnt/usr/bin/oparch-return-message-render \
            && install -m 755 /usr/bin/oparch-dotfiles-sync /mnt/usr/bin/oparch-dotfiles-sync \
            && install -m 755 /usr/bin/oparch-work-context-list /mnt/usr/bin/oparch-work-context-list \
            && rm -rf /mnt/usr/share/opinionatedarch/assets \
            && cp -r /usr/share/opinionatedarch/assets /mnt/usr/share/opinionatedarch/assets" || return 1

    guest_say "powering the live system off"
    guest_send poweroff
    guest_wait_for_exit
}

# The installed disk, booted on its own the way the machine would be: by the
# entry the installation registered with the firmware.
boot_disk() {
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

build_image
prepare_machine

say "Installing a machine from $(basename "$image")"
say "The window shows the installation, and closes when it is done; then one opens on the installed disk."
boot_live
trap guest_stop EXIT

if ! install_machine; then
    say "The machine could not be installed. What the serial line said is in $WORK/install.log"
    exit 1
fi
trap - EXIT

say "The window is the installed machine. The disk asks for $(shared_secret), and $(work_contexts) log in with it."
boot_disk
