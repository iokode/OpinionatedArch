#!/usr/bin/env bash
#
# Prepares an official Arch live environment to run the OpinionatedArch
# installer. It is not needed on this project's own ISO, which carries all of
# this already installed and at versions that match its packages.
#
# What it deals with is the age of the medium. An official ISO is built on one
# day and installs from mirrors as they are on another, and the gap between the
# two is what breaks an installation in ways that look like the installer's
# fault:
#
#   - What the mirrors offer is built against a newer glibc than the ISO
#     carries, so a freshly installed ImageMagick will not even start:
#     `libm.so.6: version GLIBC_2.44 not found`. Installing more is not the way
#     out of that; upgrading is.
#
#   - Upgrading must leave the running kernel alone. Replacing `linux` removes
#     the modules of the kernel that is running right now, and the installer's
#     `cryptsetup open` then fails with `crypt: unknown target type`, which
#     reads like a disk problem and is not one.
#
# There is one thing this script cannot do for you. The live system writes to a
# small overlay — around 250 MB free — and the upgrade needs more than that. It
# is sized by a boot parameter, so it has to be set before the machine starts:
#
#   cow_spacesize=4G
#
# If pacman stops with `Partition / too full`, that is what is missing, and the
# fix is to boot again with it rather than to free anything up.

set -euo pipefail

if ((EUID != 0)); then
    echo "this has to run as root" >&2
    exit 1
fi

# What the installer needs and the official ISO does not carry. ImageMagick
# composes the pre-boot return message; `pango` is what draws its text, and is
# an optional dependency of ImageMagick on Arch, so asking for the one does not
# bring the other; `noto-fonts` is the family the message is drawn with, and
# the one its fallback draws from for a script that family does not cover.
readonly PACKAGES=(imagemagick pango noto-fonts)

echo "preparing the live environment: upgrading, and installing ${PACKAGES[*]}"

pacman -Syu --noconfirm \
    --ignore linux \
    --ignore linux-firmware \
    "${PACKAGES[@]}"

echo "the live environment is ready for the installer"
