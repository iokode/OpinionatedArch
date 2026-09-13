#!/usr/bin/env bash
#
# The image where the boot looks for it, the machine's own menu file naming it,
# and the hook that will move it there again the next time the package is
# updated. The last is what keeps this true after the installation is over.

case_assert() {
    guest_check "the microcode image is in the directory the boot reads" \
        "test -f /mnt/boot/OpinionatedArch/amd-ucode.img"

    guest_check "nothing was left where the package put it" \
        "test ! -e /mnt/boot/amd-ucode.img"

    guest_check "the machine's own menu file names it" \
        "grep -q 'amd-ucode.img' /mnt/boot/OpinionatedArch/grub/oparch.cfg"

    guest_check "an update of the package will move it there again" \
        "test -f /mnt/etc/pacman.d/hooks/90-oparch-microcode-amd.hook"
}
