#!/usr/bin/env bash
#
# What an installation with a network leaves that one without cannot: the tools
# this project ships, taken from the repository that publishes them, and that
# repository written into the machine above the official ones so that updating
# it later updates them too.

case_assert() {
    harness_check "the tools this project ships are on the machine" \
        "arch-chroot /mnt pacman -Q oparch-assets oparch-return-message-render \
            oparch-dotfiles-sync oparch-keyring"

    harness_check "the machine can be updated from the repository it came from" \
        "grep -q '^Server = https://packages.oparch.iokode.dev' /mnt/etc/pacman.conf"

    # Order is the whole of what decides which repository serves a name two of
    # them carry, so it is the order that is checked and not the presence.
    harness_check "this project's repository is above the official ones" \
        "test \"\$(grep -n '^\\[oparch\\]' /mnt/etc/pacman.conf | cut -d: -f1)\" \
            -lt \"\$(grep -n '^\\[core\\]' /mnt/etc/pacman.conf | cut -d: -f1)\""

    harness_check "the key those packages are checked against is trusted there" \
        "arch-chroot /mnt pacman-key --list-keys 1E2FAAF03FFCBE59"
}
