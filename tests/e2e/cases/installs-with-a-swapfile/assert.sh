#!/usr/bin/env bash
#
# The file, where the layout puts it; what it is, according to the kernel's own
# reader rather than to its name; and the line that makes the machine use it at
# every boot. A swap file that exists and is never mounted is the failure this
# is looking for.

case_assert() {
    harness_check "the swap file is on its own subvolume" \
        "test -f /mnt/swap/swapfile"

    harness_check "it is a swap area, and the size that was asked for" \
        "test \"\$(blkid -o value -s TYPE /mnt/swap/swapfile)\" = swap \
            && test \"\$(stat -c %s /mnt/swap/swapfile)\" -ge 1073741824"

    harness_check "the machine mounts it at every boot" \
        "grep -q '^/swap/swapfile none swap' /mnt/etc/fstab"
}
