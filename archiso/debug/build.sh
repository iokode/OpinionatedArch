#!/usr/bin/env bash
#
# Builds an image carrying the installer built from this working tree, with the
# two tools it calls, to try them in before they are published.
#
# It is assembled the way archiso/distrib/build.sh assembles the published
# image, out of a profile of archiso's with this directory's differences
# applied over it, and for the same reason. The profile is `baseline`, which
# boots and carries little else: the image is for a virtual machine, and most
# of what `releng` brings is for real hardware. What an installation needs of
# the live system and `baseline` lacks is taken from `releng` as it is on the
# day.
#
# The tools are built first and put where their packages put them. The image
# carries no repository of its own, so an installation made from it needs a
# network.
#
# Needs archiso, grub, jq, and the BAML toolchain the tools are built with.
# Runs as any user: mkarchiso runs its steps in a user namespace when it is not
# root. Takes the directory to leave the image in.

set -euo pipefail

readonly HERE="$(cd "$(dirname "$0")" && pwd)"
readonly ROOT="$(cd "$HERE/../.." && pwd)"
readonly BASELINE=/usr/share/archiso/configs/baseline
readonly RELENG=/usr/share/archiso/configs/releng/airootfs

. "$ROOT/scripts/lib/toolchain.sh"

say() { printf '==> %s\n' "$*" >&2; }

output="${1:?the directory to leave the image in}"
mkdir -p "$output"
output="$(cd "$output" && pwd)"

# Not under /tmp, which is often memory: the root filesystem of the image is
# about a gigabyte before it is compressed.
cache="${XDG_CACHE_HOME:-$HOME/.cache}"
mkdir -p "$cache"
work="$(mktemp -d -p "$cache" oparch-debug-image.XXXXXX)"

# What mkarchiso leaves when it is not root is owned by the IDs of the
# namespace it ran in, and is removed from inside one.
remove_work() {
    if (( EUID != 0 )); then
        unshare --map-auto --map-root-user rm -rf -- "$work"
    else
        rm -rf -- "$work"
    fi
}
trap remove_work EXIT

# ------------------------------------------------------------------ the tools

say "Building the tools from $ROOT"
( cd "$ROOT/tools/installer/unattended" && capped baml pack main --output ./oparch-installer )
capped baml --directory "$ROOT/tools/installer/interactive" generate
capped cargo build --release --manifest-path "$ROOT/tools/installer/interactive/host/Cargo.toml"
( cd "$ROOT/tools/return-message/render" \
    && capped baml pack main --output ./oparch-return-message-render )
( cd "$ROOT/tools/dotfiles/sync" && capped baml pack main --output ./oparch-dotfiles-sync )

# The runtime library the interactive installer's host loads.
library="$(baml_runtime_library)"

# ---------------------------------------------------------------- the profile

say "Taking the profile from $BASELINE"
profile="$work/profile"
air="$profile/airootfs"
cp -r "$BASELINE" "$profile"
cp "$HERE/profiledef.sh" "$HERE/packages.x86_64" "$HERE/pacman.conf" "$profile/"
cp -r "$HERE/airootfs/." "$air/"

# `baseline` starts the agents of other hypervisors, cloud-init and sshd, and
# this image carries none of them.
rm -rf "$air/etc/systemd/system/cloud-init.target.wants" "$air/etc/ssh"
rm -f "$air/etc/systemd/system/multi-user.target.wants/"{hv_fcopy_daemon,hv_kvp_daemon,hv_vss_daemon,sshd,vboxservice,vmtoolsd,vmware-vmblock-fuse}.service

# From `releng`: root's shell is zsh, which is what reads the file that starts
# the installer, and root is logged in on the first console by itself; the
# keyring is made at boot out of every keyring installed, the project's among
# them; and the mirrorlist has its servers uncommented while the image is
# built, by a hook that is removed once it has run.
say "Taking what an installation needs of the live system from $RELENG"
mkdir -p "$air/etc/systemd/system/getty@tty1.service.d" \
    "$air/etc/systemd/system/multi-user.target.wants" \
    "$air/etc/pacman.d/hooks"
cp "$RELENG/etc/passwd" "$RELENG/etc/hostname" "$air/etc/"
cp "$RELENG/etc/systemd/system/getty@tty1.service.d/autologin.conf" \
    "$air/etc/systemd/system/getty@tty1.service.d/"
cp "$RELENG/etc/systemd/system/pacman-init.service" \
    "$RELENG/etc/systemd/system/etc-pacman.d-gnupg.mount" \
    "$air/etc/systemd/system/"
cp -P "$RELENG/etc/systemd/system/multi-user.target.wants/pacman-init.service" \
    "$air/etc/systemd/system/multi-user.target.wants/"
cp "$RELENG/etc/pacman.d/hooks/uncomment-mirrors.hook" \
    "$RELENG/etc/pacman.d/hooks/zzzz99-remove-custom-hooks-from-airootfs.hook" \
    "$air/etc/pacman.d/hooks/"

# The project's key, where the keyring made at boot is populated from, and
# marked as trusted, as the oparch-keyring package installs it.
say "Trusting the project's signing key"
keyrings="$air/usr/share/pacman/keyrings"
mkdir -p "$keyrings"
cp "$ROOT/packages/oparch-keyring/oparch.gpg" "$keyrings/"
install -dm700 "$work/gnupg"
fingerprint="$(GNUPGHOME="$work/gnupg" gpg --with-colons --import-options show-only \
    --import < "$ROOT/packages/oparch-keyring/oparch.gpg" |
    awk -F: '/^fpr:/ { print $10; exit }')"
[ -n "$fingerprint" ]
printf '%s:4:\n' "$fingerprint" > "$keyrings/oparch-trusted"

# The tools from this tree, where their packages put them, and the file the
# published image starts the installer with.
say "Putting the tools in"
mkdir -p "$air/usr/bin" "$air/usr/lib/oparch" "$air/usr/share/opinionatedarch" "$air/root"
cp "$ROOT/tools/installer/unattended/oparch-installer" "$air/usr/bin/"
cp "$ROOT/packages/oparch-installer/oparch-installer-interactive.sh" \
    "$air/usr/bin/oparch-installer-interactive"
cp "$ROOT/tools/return-message/render/oparch-return-message-render" "$air/usr/bin/"
cp "$ROOT/tools/dotfiles/sync/oparch-dotfiles-sync" "$air/usr/bin/"
cp "$ROOT/tools/installer/interactive/host/target/release/oparch-installer-interactive" \
    "$air/usr/lib/oparch/"
cp "$library" "$air/usr/lib/oparch/"
cp -r "$ROOT/assets" "$air/usr/share/opinionatedarch/assets"
cp "$ROOT/archiso/distrib/airootfs/root/.zprofile" "$air/root/"

# ------------------------------------------------------------------ the image

say "Building"
capped mkarchiso -v -w "$work/build" -o "$output" "$profile"
