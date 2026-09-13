#!/usr/bin/env bash
#
# Boots the published installation image in a window, with the tools built
# from this working tree put in place of the ones the image carries, so that a
# change to them can be tried by hand before it is merged.
#
#     scripts/vm.sh                  build the tools, boot the image, open the installer
#     scripts/vm.sh --iso <image>    the same, with an image already on this machine
#     scripts/vm.sh --disk           boot the disk the last installation left
#
# What reaches the live system is what an image built from this tree would
# carry of the tools: the installer's two commands and the wrapper of the
# interactive one, the renderer, the dotfiles tool, the assets, and the file
# that starts the installer on the first console. The rest is the published
# image, so the package, its dependencies and the image itself are not what is
# tried here.
#
# The guest is driven over its serial line with scripts/lib/guest.sh, which the
# end-to-end harness drives its guests with too. The window is its screen, and
# once the tools are in place it is yours.

set -euo pipefail

readonly ROOT="$(cd "$(dirname "$0")/.." && pwd)"
readonly IMAGE_URL="https://oparch.iokode.dev/latest.iso"
readonly CHECKSUM_URL="https://oparch.iokode.dev/latest.sha256"

# Kept between runs: the image, so that it is downloaded when a newer one is
# published and not otherwise, and the disk and firmware variables of the last
# guest, so that the machine it installed can be booted afterwards.
readonly WORK="${XDG_CACHE_HOME:-$HOME/.cache}/oparch-vm"
readonly SHARE="$WORK/share"
readonly DISK="$WORK/disk.qcow2"
readonly VARS="$WORK/firmware-vars.fd"

. "$ROOT/scripts/lib/guest.sh"

say() {
    printf '==> %s\n' "$*" >&2
}

usage() {
    printf 'Usage: %s [--iso <image>] [--disk]\n' "$0" >&2
}

image=""
disk_only=false
while [ "$#" -gt 0 ]; do
    case "$1" in
        --iso)
            image="${2:-}"
            if [ -z "$image" ]; then
                usage
                exit 2
            fi
            shift 2
            ;;
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

# A build that allocates without bound takes a machine with no swap down before
# anything can stop it, so each one is held to a ceiling where the user's
# systemd is there to hold it.
capped() {
    if systemd-run --user --scope -q -p MemoryMax=8G -p MemorySwapMax=0 true 2>/dev/null; then
        systemd-run --user --scope -q -p MemoryMax=8G -p MemorySwapMax=0 "$@"
    else
        "$@"
    fi
}

build_tools() {
    say "Building the tools from $ROOT"
    ( cd "$ROOT/src/installer/unattended" && capped baml pack main --output ./oparch-installer )
    capped baml --directory "$ROOT/src/installer/interactive" generate
    capped cargo build --release --manifest-path "$ROOT/src/installer/interactive/host/Cargo.toml"
    ( cd "$ROOT/src/return-message/render" \
        && capped baml pack main --output ./oparch-return-message-render )
    ( cd "$ROOT/src/dotfiles/sync" && capped baml pack main --output ./oparch-dotfiles-sync )
}

# What the guest is given, in one directory it mounts read-only.
stage_tools() {
    rm -rf "$SHARE"
    mkdir -p "$SHARE"
    cp "$ROOT/src/installer/unattended/oparch-installer" "$SHARE/"
    cp "$ROOT/src/installer/interactive/host/target/release/oparch-installer-interactive" "$SHARE/"
    cp "$ROOT/packages/oparch-installer/oparch-installer-interactive.sh" "$SHARE/"
    cp "$ROOT/src/return-message/render/oparch-return-message-render" "$SHARE/"
    cp "$ROOT/src/dotfiles/sync/oparch-dotfiles-sync" "$SHARE/"
    cp -r "$ROOT/assets" "$SHARE/assets"
    cp "$ROOT/archiso/airootfs/root/.zprofile" "$SHARE/zprofile"
}

# The image that is published, downloaded once per image and checked against
# the checksum published beside it before it is kept.
fetch_image() {
    local published sum name
    published="$(curl -fsSL "$CHECKSUM_URL")"
    sum="${published%% *}"
    name="${published##* }"
    image="$WORK/$name"
    if [ -f "$image" ]; then
        return 0
    fi

    say "Downloading $name"
    rm -f "$WORK"/*.iso "$WORK"/*.iso.part
    curl -fL -o "$image.part" "$IMAGE_URL"
    say "Checking $name against its published checksum"
    printf '%s  %s\n' "$sum" "$image.part" | sha256sum -c --quiet -
    mv "$image.part" "$image"
}

# A disk with nothing on it, and firmware variables of its own that the
# installation registers its boot entry in.
prepare_machine() {
    qemu-img create -f qcow2 "$DISK" "$GUEST_DISK_SIZE" >/dev/null
    cp "$OVMF_VARS" "$VARS"
}

# The live system, in a window, with its serial line left to be driven. The
# kernel and the initramfs are taken out of the image and handed over, as the
# end-to-end harness does, because that is what lets the serial line be a
# console too; the first console stays the window's.
boot_live() {
    local kernel="$WORK/vmlinuz-linux"
    local initramfs="$WORK/initramfs-linux.img"
    local label

    bsdtar -xOf "$image" arch/boot/x86_64/vmlinuz-linux >"$kernel"
    bsdtar -xOf "$image" arch/boot/x86_64/initramfs-linux.img >"$initramfs"
    label="$(blkid -s LABEL -o value "$image")"

    guest_acceleration
    guest_network present

    guest_start "$WORK/serial.log" "$WORK/serial.in" \
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
        -append "archisobasedir=arch archisolabel=$label console=tty0 console=ttyS0,115200"
}

# Puts the tools from this tree where the image's own are, and starts the first
# console again, so that what opens there is the installer from this tree.
put_tools_in_place() {
    guest_wait_for_shell || return 1
    guest_quieten || return 1

    guest_check "the tools from this tree reach the guest" \
        "mkdir -p $SHARE_MOUNT \
            && mount -t 9p -o trans=virtio,version=9p2000.L,ro $SHARE_TAG $SHARE_MOUNT" || return 1

    guest_check "the tools from this tree are where the image keeps its own" \
        "install -m 755 $SHARE_MOUNT/oparch-installer /usr/bin/oparch-installer \
            && install -m 755 $SHARE_MOUNT/oparch-installer-interactive \
                /usr/lib/oparch/oparch-installer-interactive \
            && install -m 755 $SHARE_MOUNT/oparch-installer-interactive.sh \
                /usr/bin/oparch-installer-interactive \
            && install -m 755 $SHARE_MOUNT/oparch-return-message-render \
                /usr/bin/oparch-return-message-render \
            && install -m 755 $SHARE_MOUNT/oparch-dotfiles-sync /usr/bin/oparch-dotfiles-sync \
            && rm -rf /usr/share/opinionatedarch/assets \
            && cp -r $SHARE_MOUNT/assets /usr/share/opinionatedarch/assets \
            && install -m 644 $SHARE_MOUNT/zprofile /root/.zprofile" || return 1

    # Whatever the first console was running is the image's own installer, in a
    # login shell. Asked to end, the installer ends and the shell and `login`
    # stay, because an interactive shell ignores that signal; so everything on
    # the console is killed instead. With `login` gone the console logs in again,
    # and starts what the file put in place above says to start.
    guest_check "the first console starts again, with the installer from this tree" \
        "pkill -KILL -t tty1; true" || return 1
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

build_tools
stage_tools
if [ -z "$image" ]; then
    fetch_image
fi
prepare_machine

say "Booting $(basename "$image")"
boot_live
trap guest_stop EXIT

if ! put_tools_in_place; then
    say "The tools could not be put in place. What the serial line said is in $WORK/serial.log"
    exit 1
fi

say "The window is the live system, with the tools from this tree in it."
say "Close the window to end it. scripts/vm.sh --disk boots what it installed."
wait "$GUEST_PID" || :
