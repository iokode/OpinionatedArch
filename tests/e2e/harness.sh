#!/usr/bin/env bash
#
# The wiring for the end-to-end tests, as specified in
# docs/development/006-end-to-end-testing.md. It starts a guest on the image
# being tested, drives its serial console, exposes the case's files to it,
# asserts what is true of any completed installation, boots the disk that was
# made, and cleans up after itself.
#
# It holds no case and asserts nothing particular to one. It is sourced by
# tests/e2e/run.sh, which is the command.
#
# Nothing here relies on `set -e`. A case is driven from a function that the
# runner calls with its status captured, and `set -e` is suppressed for
# everything such a function calls; a step that failed would otherwise carry on
# into the next one. So every step that can fail is checked where it is called
# and answers with a status of its own, which is what the runner reports.

# Where the firmware the guest boots is read from. Its path is `edk2-ovmf`'s
# own, which is why this runs on Arch: a path that moves only when a
# distribution moves it is one less thing to discover at run time.
readonly OVMF_CODE=/usr/share/edk2/x64/OVMF_CODE.4m.fd
readonly OVMF_VARS=/usr/share/edk2/x64/OVMF_VARS.4m.fd

# The disposable disk is attached over virtio, so the guest calls it `/dev/vda`
# and a case's configuration names it there. Its size is what the layout needs
# — a gibibyte of EFI system partition, four of recovery and a container for
# the rest — with room for what an installation puts in the container. The file
# is a sparse qcow2, so the number is a ceiling rather than an allocation.
readonly GUEST_DISK_DEVICE=/dev/vda
readonly GUEST_DISK_SIZE=32G

# A bootstrap is the memory-hungriest thing a run does, and the live system
# holds its own root in RAM while doing it. Four cores rather than the host's,
# because a guest without acceleration emulates every one of them on one host
# thread each and more of them stop helping long before that.
readonly GUEST_MEMORY=4096
readonly GUEST_CPUS=4

# How the case's own files reach the guest, and where they are mounted there.
# Not under `/mnt`, which is where the installer mounts the system it is
# building and where mounting would be mounting over its own inputs; and not
# under `/media` either, which the installer unmounts when an installation
# starts.
#
# What is mounted is the case's `share/` and never the case itself: the rest of
# a case is the test's own code, and the machine being tested has no business
# reading it.
readonly SHARE_TAG=oparch_case
readonly SHARE_MOUNT=/run/oparch-case

# The console the guest answers on. A serial line carries no window size of its
# own, so the guest is given one, and it is generous: what the harness reads is
# what the guest wrote, and a narrow terminal wraps and truncates exactly that.
readonly CONSOLE_ROWS=50
readonly CONSOLE_COLUMNS=200

# What the guest announces with. A command sent over the line comes back
# echoed, so what says a command is done has to be a string the echo cannot
# produce: the guest builds each of these out of two pieces, and only the shell
# that ran the command prints one whole. The outcome is a different word rather
# than an exit status, because a status does not survive the wire.
readonly MARKER=OPARCH-E2E
readonly MARKER_OK=OK
readonly MARKER_FAILED=FAILED

# How long each thing is waited for, in seconds, and how often the transcript is
# read while waiting. The installation is the one that is generous: a run with
# hardware acceleration is minutes and the same run emulated is the better part
# of an hour, and a limit that fits the first fails the second for no reason.
readonly WAIT_SHELL=900
readonly WAIT_COMMAND=300
readonly WAIT_INSTALL=7200
readonly WAIT_PASSPHRASE=900
readonly WAIT_LOGIN=900
readonly WAIT_POWEROFF=300
readonly POLL=2

# The guest being driven. There is one at a time: a case is one installation,
# and the harness performs one installation per guest.
GUEST_PID=""
GUEST_LOG=""
GUEST_INPUT=""
GUEST_COMMANDS=0
GUEST_TOKEN=""

harness_say() {
    printf '    %s\n' "$*" >&2
}

# Hardware acceleration when `/dev/kvm` can be read and written, and emulation
# when it cannot. Which one a run got is said out loud, because it is the
# difference between a run somebody waits for and a run somebody leaves.
# Whether the machine this case installs has a network, which is the case's to
# say: an installation with one and an installation without one take their
# packages from different places and are different installations. A case that
# says nothing has none, because a guest that cannot reach anything is the
# reproducible one.
guest_network() {
    case "${CASE_NETWORK:-none}" in
        none)
            GUEST_NETWORK=(-nic none)
            ;;
        present)
            GUEST_NETWORK=(-netdev user,id=net0 -device virtio-net,netdev=net0)
            harness_say "the guest has a network"
            ;;
        *)
            harness_say "FAILED: ${CASE_NETWORK} is not something a guest's network can be"
            return 1
            ;;
    esac
}

guest_acceleration() {
    if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
        GUEST_ACCELERATION=(-machine q35,accel=kvm -cpu host)
        harness_say "using hardware acceleration"
    else
        GUEST_ACCELERATION=(-machine q35,accel=tcg -cpu qemu64)
        harness_say "no /dev/kvm: emulating, which is slow"
    fi
}

# Starts a guest and leaves it driveable. Its console is a file the harness
# reads and a fifo the harness writes, and the fifo is held open for reading
# and writing here: a fifo whose only writer closes it hands the guest an end
# of input it cannot come back from, and this way there is always a writer.
guest_start() {
    local log="$1"
    local input="$2"
    shift 2

    rm -f "$input"
    mkfifo "$input"
    exec 9<>"$input"

    qemu-system-x86_64 "$@" <"$input" >"$log" 2>&1 &

    GUEST_PID=$!
    GUEST_LOG="$log"
    GUEST_INPUT="$input"
    GUEST_COMMANDS=0
}

# Kills the guest if it is still there and lets go of its console. A guest that
# has already gone is the outcome this wants, so failing to kill it is not a
# failure.
guest_stop() {
    if [ -n "$GUEST_PID" ]; then
        kill "$GUEST_PID" 2>/dev/null || :
        wait "$GUEST_PID" 2>/dev/null || :
    fi
    # The braces are what keeps the quieting to the close. `exec` with nothing
    # to run applies its redirections to the shell itself and keeps them, so
    # `exec 9>&- 2>/dev/null` closes the console and sends everything this
    # harness has left to say into the same hole — a failure after it included.
    { exec 9>&-; } 2>/dev/null || :
    rm -f "$GUEST_INPUT"
    GUEST_PID=""
}

# Waits for the guest to end on its own, and kills it when it will not. The
# disk the installation wrote is only safe to boot once the process holding it
# has gone.
guest_wait_for_exit() {
    local waited=0
    while [ "$waited" -lt "$WAIT_POWEROFF" ]; do
        if ! kill -0 "$GUEST_PID" 2>/dev/null; then
            wait "$GUEST_PID" 2>/dev/null || :
            GUEST_PID=""
            { exec 9>&-; } 2>/dev/null || :
            rm -f "$GUEST_INPUT"
            return 0
        fi
        sleep "$POLL"
        waited=$((waited + POLL))
    done
    harness_say "the guest did not power off; killing it"
    guest_stop
    return 1
}

# A serial line ends a command with a carriage return. A newline leaves the
# terminal joining what should have been two commands into one.
guest_send() {
    printf '%s\r' "$1" >&9
}

# Reads the transcript again and again until what is being waited for is in it.
# It is read as text rather than in lines because a shell prompt does not end
# in a newline, and a reader that works in lines waits for ever at exactly the
# moment it has arrived.
guest_expect() {
    local pattern="$1"
    local seconds="$2"
    local waited=0

    while [ "$waited" -lt "$seconds" ]; do
        if grep -qE -- "$pattern" "$GUEST_LOG"; then
            return 0
        fi
        # A guest that has died is not going to say anything else, so what it
        # said is read one last time and then this is over.
        if ! kill -0 "$GUEST_PID" 2>/dev/null; then
            if grep -qE -- "$pattern" "$GUEST_LOG"; then
                return 0
            fi
            return 1
        fi
        sleep "$POLL"
        waited=$((waited + POLL))
    done
    return 1
}

# Starts a command in the guest. The announcement carries a number of its own,
# so a command's answer cannot be an earlier command's answer still sitting in
# the transcript.
#
# Starting and waiting are apart because an installation driven by hand is both
# at once: the command that is running is the interface being answered, and
# what became of it is only known screens later.
guest_begin() {
    GUEST_COMMANDS=$((GUEST_COMMANDS + 1))
    GUEST_TOKEN="$MARKER-$GUEST_COMMANDS"
    guest_send "{ $1 ; } && echo $GUEST_TOKEN-\"\"$MARKER_OK || echo $GUEST_TOKEN-\"\"$MARKER_FAILED"
}

# Waits for the command that was begun last and answers with what became of it:
# zero when it succeeded, one when it failed, and two when nothing came back at
# all. Those are three different things — a case that expects a refusal is told
# the installer said no, never that it hung — so they are three statuses.
guest_finish() {
    local seconds="${1:-$WAIT_COMMAND}"

    if ! guest_expect "$GUEST_TOKEN-($MARKER_OK|$MARKER_FAILED)" "$seconds"; then
        return 2
    fi
    if grep -qE -- "$GUEST_TOKEN-$MARKER_OK" "$GUEST_LOG"; then
        return 0
    fi
    return 1
}

# One command, run and waited for, which is every command that is not an
# interface.
guest_run() {
    guest_begin "$1"
    guest_finish "${2:-$WAIT_COMMAND}"
}

# What the harness makes its own assertions with, and what a case makes its
# own with. A check that does not hold ends the case where it failed: an
# installation either finished in full or it did not.
harness_check() {
    local what="$1"
    local command="$2"
    local seconds="${3:-$WAIT_COMMAND}"
    local status=0

    guest_run "$command" "$seconds" || status=$?
    case "$status" in
        0) harness_say "ok: $what"; return 0 ;;
        1) harness_say "FAILED: $what" ;;
        *) harness_say "FAILED: $what (nothing came back)" ;;
    esac
    return 1
}

# Asks the guest until it answers, sending whatever it needs in order to be
# able to answer at all before each attempt.
#
# Nothing waits a fixed time for something to hand the line over. What is typed
# while `login` still has it is swallowed, and so is what is typed while a
# shell is replacing itself; how long either takes is not ours to know. What
# comes back from a probe came back from a shell that was ready to run it.
guest_prod() {
    local before="$1"
    local seconds="$2"
    local waited=0

    while [ "$waited" -lt "$seconds" ]; do
        # A guest that has ended is not on its way to a prompt, and asking it
        # again is asking nothing.
        if ! kill -0 "$GUEST_PID" 2>/dev/null; then
            harness_say "FAILED: the guest ended before the console answered"
            return 1
        fi
        if [ -n "$before" ]; then
            guest_send "$before"
        fi
        if guest_run true 20; then
            return 0
        fi
        waited=$((waited + 20))
    done
    return 1
}

# Gets a shell on the serial line. The name is what a login prompt wants and a
# command a shell does not have, so it costs one line either way and the probe
# behind it comes back only from a shell.
guest_wait_for_shell() {
    if guest_prod root "$WAIT_SHELL"; then
        return 0
    fi
    harness_say "FAILED: the guest never reached a shell on the serial console"
    return 1
}

# Leaves the line carrying only what the guest produces, and gives it a size.
# Turning the echo off does not hold under a shell with line editing, because
# the editor puts the terminal back the way it wants it at every prompt; a
# shell without one is what makes it hold.
#
# This is done again after an installation driven by hand, because the
# interface takes the terminal over and hands it back the way it found it.
guest_quieten() {
    guest_send "exec bash --noediting"
    if ! guest_prod "" "$WAIT_COMMAND"; then
        harness_say "FAILED: the console never came back without line editing"
        return 1
    fi
    guest_send "stty -echo rows $CONSOLE_ROWS cols $CONSOLE_COLUMNS"
    harness_check "the console answers with what the guest produced" true
}

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
        harness_say "FAILED: the image carries no arch/boot/x86_64/vmlinuz-linux"
        return 1
    fi
    if ! bsdtar -xOf "$CASE_IMAGE" arch/boot/x86_64/initramfs-linux.img >"$initramfs"; then
        harness_say "FAILED: the image carries no arch/boot/x86_64/initramfs-linux.img"
        return 1
    fi

    # How the live system finds the medium it was booted from: by the label the
    # image carries, which is read from the image rather than written down here
    # because it is dated and changes with every build.
    local label
    label="$(blkid -s LABEL -o value "$CASE_IMAGE")"
    if [ -z "$label" ]; then
        harness_say "FAILED: the image carries no label for the live system to find it by"
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

    harness_say "driving the installation"
    case_drive || status=$?

    case "$CASE_OUTCOME" in
        installs)
            if [ "$status" -eq 0 ]; then
                harness_say "ok: the installer installed the machine"
                return 0
            fi
            harness_say "FAILED: the installer did not install the machine"
            return 1
            ;;
        refuses)
            if [ "$status" -ne 1 ]; then
                harness_say "FAILED: the installer did not refuse the installation"
                return 1
            fi
            harness_say "ok: the installer refused the installation"
            harness_check "the disk is as it was" \
                "test ! -e ${GUEST_DISK_DEVICE}1 && test -z \"\$(blkid -o value -s PTTYPE $GUEST_DISK_DEVICE)\""
            ;;
        *)
            harness_say "FAILED: $CASE_OUTCOME is not an outcome a case can declare"
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
    harness_check "the EFI system partition is FAT32 and named EFI" \
        "test \"\$(blkid -o value -s TYPE ${GUEST_DISK_DEVICE}1)\" = vfat \
            && test \"\$(blkid -o value -s PARTLABEL ${GUEST_DISK_DEVICE}1)\" = EFI" || return 1

    harness_check "the recovery partition is ext4, labelled RECOVERY" \
        "test \"\$(blkid -o value -s TYPE ${GUEST_DISK_DEVICE}2)\" = ext4 \
            && test \"\$(blkid -o value -s LABEL ${GUEST_DISK_DEVICE}2)\" = RECOVERY" || return 1

    harness_check "the rest of the disk is one LUKS container" \
        "test \"\$(blkid -o value -s TYPE ${GUEST_DISK_DEVICE}3)\" = crypto_LUKS" || return 1

    harness_check "the root subvolume is the target's filesystem" \
        "test \"\$(findmnt -no FSTYPE /mnt)\" = btrfs" || return 1

    harness_check "the filesystem holds the subvolumes the layout fixes" \
        "( for s in @ @snapshots @log @pkg @dotfiles @swap; do \
            btrfs subvolume list /mnt | awk '{print \$NF}' | grep -qx \"\$s\" || exit 1; \
        done )" || return 1

    harness_check "each work context has a home subvolume of its own" \
        "btrfs subvolume list /mnt | awk '{print \$NF}' | grep -q '^home/@'" || return 1

    harness_check "the machine's boot artifacts are on the EFI system partition" \
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

    harness_check "the installed kernel is told to use the serial line" \
        "echo 'set linux_extra=\"\$linux_extra console=ttyS0,115200\"' >> $settings" || return 1

    harness_say "powering the live environment off"
    guest_send poweroff
    guest_wait_for_exit || return 1

    harness_say "booting the disk that was installed"
    guest_boot_installed_disk

    # What is waited for is the hook's own announcement and not the prompt that
    # follows it. A machine installed with a return message boots Plymouth, and
    # Plymouth takes the asking: the announcement is still written to this
    # console and the prompt is not, so a harness waiting for the prompt waits
    # for a machine that is already asking.
    if ! guest_expect "A password is required to access the cryptroot volume" \
            "$WAIT_PASSPHRASE"; then
        harness_say "FAILED: the installed machine never asked for its passphrase"
        return 1
    fi
    harness_say "ok: the installed machine asked for its passphrase"

    guest_send "$CASE_PASSPHRASE"

    if ! guest_expect "login:" "$WAIT_LOGIN"; then
        harness_say "FAILED: the installed machine never reached a login"
        return 1
    fi
    harness_say "ok: the installed machine reached a login"
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

    harness_check "what the case gives the guest is mounted" \
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
harness_prepare_guest() {
    if ! qemu-img create -f qcow2 "$CASE_DISK" "$GUEST_DISK_SIZE" >/dev/null; then
        harness_say "FAILED: the disposable disk could not be created"
        return 1
    fi
    if ! cp "$OVMF_VARS" "$CASE_VARS"; then
        harness_say "FAILED: the firmware's variables are not at $OVMF_VARS"
        return 1
    fi
    guest_acceleration
    guest_network || return 1
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
