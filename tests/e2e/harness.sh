#!/usr/bin/env bash
#
# The wiring for the end-to-end tests, as specified in
# docs/development/006-end-to-end-testing.md. It starts a guest on the image
# being tested, exposes the case's files to it, asserts what is true of any
# completed installation, boots the disk that was made, and cleans up after
# itself. Starting a guest and driving its serial console is
# scripts/lib/guest.sh, which this sources.
#
# It holds no case and asserts nothing particular to one. It is sourced by
# tests/e2e/run.sh, which is the command.
#
# Nothing here relies on `set -e`, for the reason guest.sh gives: a case is
# driven from a function the runner calls with its status captured, so every
# step that can fail is checked where it is called and answers with a status of
# its own, which is what the runner reports.

. "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib/guest.sh"

# The disposable disk is attached over virtio, so the guest calls it `/dev/vda`
# and a case's configuration names it there.
readonly GUEST_DISK_DEVICE=/dev/vda

# How long the steps of a case that take longest are waited for, in seconds. The
# installation is the one that is generous: a run with hardware acceleration is
# minutes and the same run emulated is the better part of an hour, and a limit
# that fits the first fails the second for no reason.
readonly WAIT_INSTALL=7200
readonly WAIT_PASSPHRASE=900
readonly WAIT_LOGIN=900

# Boots the image being tested, with the case's own files attached and the
# disposable disk it will install onto.
#
# The kernel and the initramfs are taken out of the image and handed to the
# guest directly, because that is what allows `console=ttyS0` on the kernel
# command line. The medium's own boot menu carries no such thing, and editing
# it would be editing the image that is being tested.
guest_boot_medium() {
    local kernel="$CASE_WORK/vmlinuz-linux"
    local initramfs="$CASE_WORK/initramfs-linux.img"

    if ! bsdtar -xOf "$CASE_IMAGE" arch/boot/x86_64/vmlinuz-linux >"$kernel"; then
        guest_say "FAILED: the image carries no arch/boot/x86_64/vmlinuz-linux"
        return 1
    fi
    if ! bsdtar -xOf "$CASE_IMAGE" arch/boot/x86_64/initramfs-linux.img >"$initramfs"; then
        guest_say "FAILED: the image carries no arch/boot/x86_64/initramfs-linux.img"
        return 1
    fi

    # How the live system finds the medium it was booted from: by the label the
    # image carries, which is read from the image rather than written down here
    # because it is dated and changes with every build.
    local label
    label="$(blkid -s LABEL -o value "$CASE_IMAGE")"
    if [ -z "$label" ]; then
        guest_say "FAILED: the image carries no label for the live system to find it by"
        return 1
    fi

    guest_start "$CASE_WORK/medium.log" "$CASE_WORK/medium.in" \
        "${GUEST_ACCELERATION[@]}" \
        -m "$GUEST_MEMORY" -smp "$GUEST_CPUS" \
        -nographic -serial mon:stdio \
        "${GUEST_NETWORK[@]}" \
        -drive "if=pflash,format=raw,readonly=on,file=$OVMF_CODE" \
        -drive "if=pflash,format=raw,file=$CASE_VARS" \
        -drive "if=virtio,format=qcow2,file=$CASE_DISK" \
        -drive "media=cdrom,readonly=on,file=$CASE_IMAGE" \
        -virtfs "local,path=$CASE_DIR/share,mount_tag=$SHARE_TAG,security_model=none,readonly=on" \
        -kernel "$kernel" -initrd "$initramfs" \
        -append "archisobasedir=arch archisolabel=$label console=ttyS0,115200"
}

# Boots the disk that was just installed, and nothing else: no medium, and no
# kernel handed in from outside. What starts it is the bootloader the
# installation put on the disk and the entry it registered with the firmware,
# which is why this guest keeps the firmware variables the installation wrote.
guest_boot_installed_disk() {
    guest_start "$CASE_WORK/installed.log" "$CASE_WORK/installed.in" \
        "${GUEST_ACCELERATION[@]}" \
        -m "$GUEST_MEMORY" -smp "$GUEST_CPUS" \
        -nographic -serial mon:stdio \
        "${GUEST_NETWORK[@]}" \
        -drive "if=pflash,format=raw,readonly=on,file=$OVMF_CODE" \
        -drive "if=pflash,format=raw,file=$CASE_VARS" \
        -drive "if=virtio,format=qcow2,file=$CASE_DISK"
}

# The shared secret a configuration file gives the installer, for the case that
# hands one over: what unlocks the disk is then written once, where the
# installation is described, and the passphrase the installed machine is
# answered with is that same value rather than a copy of it.
harness_secret_in() {
    sed -n 's/^shared_secret:[[:space:]]*//p' "$1" | sed -e 's/^"//' -e 's/"$//'
}

# The installation the case performs, held to the outcome it declared.
#
# `installs` and `refuses` are the two outcomes there are, and the difference
# between a refusal and a run that said nothing at all is what the third status
# of `guest_finish` is for.
harness_install() {
    local status=0

    guest_say "driving the installation"
    case_drive || status=$?

    case "$CASE_OUTCOME" in
        installs)
            if [ "$status" -eq 0 ]; then
                guest_say "ok: the installer installed the machine"
                return 0
            fi
            guest_say "FAILED: the installer did not install the machine"
            return 1
            ;;
        refuses)
            if [ "$status" -ne 1 ]; then
                guest_say "FAILED: the installer did not refuse the installation"
                return 1
            fi
            guest_say "ok: the installer refused the installation"
            guest_check "the disk is as it was" \
                "test ! -e ${GUEST_DISK_DEVICE}1 && test -z \"\$(blkid -o value -s PTTYPE $GUEST_DISK_DEVICE)\""
            ;;
        *)
            guest_say "FAILED: $CASE_OUTCOME is not an outcome a case can declare"
            return 1
            ;;
    esac
}

# What is true of any completed installation: the layout
# docs/decisions/001-disk-layout.md fixes, on the disk it was just written to.
# It lives here rather than in each case because it is true of all of them, and
# a copy of it in every case would be a copy to drift.
#
# The target is read where the installation left it mounted, which is the one
# place the whole layout is reachable without the passphrase being given again.
harness_assert_layout() {
    guest_check "the EFI system partition is FAT32 and named EFI" \
        "test \"\$(blkid -o value -s TYPE ${GUEST_DISK_DEVICE}1)\" = vfat \
            && test \"\$(blkid -o value -s PARTLABEL ${GUEST_DISK_DEVICE}1)\" = EFI" || return 1

    guest_check "the recovery partition is ext4, labelled RECOVERY" \
        "test \"\$(blkid -o value -s TYPE ${GUEST_DISK_DEVICE}2)\" = ext4 \
            && test \"\$(blkid -o value -s LABEL ${GUEST_DISK_DEVICE}2)\" = RECOVERY" || return 1

    guest_check "the rest of the disk is one LUKS container" \
        "test \"\$(blkid -o value -s TYPE ${GUEST_DISK_DEVICE}3)\" = crypto_LUKS" || return 1

    guest_check "the root subvolume is the target's filesystem" \
        "test \"\$(findmnt -no FSTYPE /mnt)\" = btrfs" || return 1

    guest_check "the filesystem holds the subvolumes the layout fixes" \
        "( for s in @ @snapshots @log @pkg @dotfiles @swap; do \
            btrfs subvolume list /mnt | awk '{print \$NF}' | grep -qx \"\$s\" || exit 1; \
        done )" || return 1

    guest_check "each work context has a home subvolume of its own" \
        "btrfs subvolume list /mnt | awk '{print \$NF}' | grep -q '^home/@'" || return 1

    guest_check "the machine's boot artifacts are on the EFI system partition" \
        "test -f /mnt/boot/OpinionatedArch/vmlinuz-linux \
            && test -f /mnt/boot/OpinionatedArch/initramfs-linux.img \
            && test -f /mnt/boot/OpinionatedArch/grub/grub.cfg \
            && test -f /mnt/boot/OpinionatedArch/grub/oparch.cfg \
            && test -f /mnt/boot/EFI/OpinionatedArch/grubx64.efi" || return 1
}

# The disk that was just made, booted on its own: asked for its passphrase, and
# reaching a login.
#
# The installed machine writes where a screen would be, so its kernel is told
# to use the serial line as well. What says so is the file the installer
# generates per machine, beside the menu the project ships — the menu is what
# is being tested and nothing here touches it — and the setting is added to
# what that file already carries rather than replacing it.
harness_boot_installed_system() {
    local settings=/mnt/boot/OpinionatedArch/grub/oparch.cfg

    guest_check "the installed kernel is told to use the serial line" \
        "echo 'set linux_extra=\"\$linux_extra console=ttyS0,115200\"' >> $settings" || return 1

    guest_say "powering the live environment off"
    guest_send poweroff
    guest_wait_for_exit || return 1

    guest_say "booting the disk that was installed"
    guest_boot_installed_disk

    # What is waited for is the hook's own announcement and not the prompt that
    # follows it. A machine installed with a return message boots Plymouth, and
    # Plymouth takes the asking: the announcement is still written to this
    # console and the prompt is not, so a harness waiting for the prompt waits
    # for a machine that is already asking.
    if ! guest_expect "A password is required to access the cryptroot volume" \
            "$WAIT_PASSPHRASE"; then
        guest_say "FAILED: the installed machine never asked for its passphrase"
        return 1
    fi
    guest_say "ok: the installed machine asked for its passphrase"

    guest_send "$CASE_PASSPHRASE"

    if ! guest_expect "login:" "$WAIT_LOGIN"; then
        guest_say "FAILED: the installed machine never reached a login"
        return 1
    fi
    guest_say "ok: the installed machine reached a login"
}

# The shape of a run, once there is a guest to run it in. Every step is checked
# here, because `set -e` is suppressed for everything this is called from.
#
# The checks that belong to every completed installation are made before the
# case's own, because a case's assertions about a disk whose layout is already
# wrong are noise on a machine that is already broken.
harness_drive_case() {
    guest_wait_for_shell || return 1
    guest_quieten || return 1

    # What is mounted is the case's `share/` and never the case itself: the rest
    # of a case is the test's own code, and the machine being tested has no
    # business reading it.
    guest_check "what the case gives the guest is mounted" \
        "mkdir -p $SHARE_MOUNT \
            && mount -t 9p -o trans=virtio,version=9p2000.L,ro $SHARE_TAG $SHARE_MOUNT" || return 1

    harness_install || return 1
    guest_quieten || return 1

    if [ "$CASE_OUTCOME" = installs ]; then
        harness_assert_layout || return 1
    fi

    case_assert || return 1

    if [ "$CASE_OUTCOME" = installs ]; then
        harness_boot_installed_system || return 1
    fi
}

# Everything a case needs before there is anything to drive: a disposable disk,
# so that every case starts from the same state and leaves nothing behind, a
# copy of the firmware's variables, and the guest itself.
#
# The variables are one copy for both of this case's boots, because what the
# installation registers with the firmware is what starts the machine
# afterwards.
#
# Whether the machine has a network is the case's to say: an installation with
# one and an installation without one take their packages from different places
# and are different installations. A case that says nothing has none, because a
# guest that cannot reach anything is the reproducible one.
harness_prepare_guest() {
    if ! qemu-img create -f qcow2 "$CASE_DISK" "$GUEST_DISK_SIZE" >/dev/null; then
        guest_say "FAILED: the disposable disk could not be created"
        return 1
    fi
    if ! cp "$OVMF_VARS" "$CASE_VARS"; then
        guest_say "FAILED: the firmware's variables are not at $OVMF_VARS"
        return 1
    fi
    guest_acceleration
    guest_network "${CASE_NETWORK:-none}" || return 1
    guest_boot_medium || return 1
}

# One case, from a disk that has nothing on it to a report of what became of
# it. The runner calls this once per case, in a subshell of its own, so what a
# case declares belongs to that case alone.
#
# A case is four files and a directory, and every case has all of them:
# `case.sh` says what it is and what it is held to, `drive.sh` performs the
# installation, `assert.sh` says what this case is for, and `share/` is what
# the guest can see.
harness_run_case() {
    CASE_DIR="$1"
    CASE_WORK="$2"
    CASE_IMAGE="$3"

    . "$CASE_DIR/case.sh"
    . "$CASE_DIR/drive.sh"
    . "$CASE_DIR/assert.sh"

    mkdir -p "$CASE_WORK"
    CASE_DISK="$CASE_WORK/disk.qcow2"
    CASE_VARS="$CASE_WORK/firmware-vars.fd"

    local status=0
    if harness_prepare_guest; then
        harness_drive_case || status=$?
    else
        status=1
    fi

    guest_stop

    # The guest's disk, its firmware variables and the images it was booted
    # with are gigabytes and say nothing once the case is over. The transcripts
    # stay: they are what a failed case is read from.
    rm -f "$CASE_DISK" "$CASE_VARS" \
        "$CASE_WORK/vmlinuz-linux" "$CASE_WORK/initramfs-linux.img"

    return "$status"
}
