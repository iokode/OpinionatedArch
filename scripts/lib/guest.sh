#!/usr/bin/env bash
#
# Starting a guest under QEMU and driving it over its serial line. The
# end-to-end harness in tests/e2e/ runs its cases in such a guest, and
# scripts/vm.sh puts the tools of a working tree into one.
#
# It holds no guest of its own and nothing about what one is for: whoever
# sources it says what to boot and what to type.
#
# Nothing here relies on `set -e`. A guest is driven from functions whose status
# the caller captures, and `set -e` is suppressed for everything such a function
# calls; a step that failed would otherwise carry on into the next one. So every
# step that can fail is checked where it is called and answers with a status of
# its own.

# Where the firmware the guest boots is read from. Its path is `edk2-ovmf`'s
# own, which is why this runs on Arch: a path that moves only when a
# distribution moves it is one less thing to discover at run time.
readonly OVMF_CODE=/usr/share/edk2/x64/OVMF_CODE.4m.fd
readonly OVMF_VARS=/usr/share/edk2/x64/OVMF_VARS.4m.fd

# The size of the disk a guest installs onto: what the layout needs — a gibibyte
# of EFI system partition, four of recovery and a container for the rest — with
# room for what an installation puts in the container. The file is a sparse
# qcow2, so the number is a ceiling rather than an allocation.
readonly GUEST_DISK_SIZE=32G

# A bootstrap is the memory-hungriest thing a guest does, and the live system
# holds its own root in RAM while doing it. Four cores rather than the host's,
# because a guest without acceleration emulates every one of them on one host
# thread each and more of them stop helping long before that.
readonly GUEST_MEMORY=4096
readonly GUEST_CPUS=4

# How a directory of the host reaches the guest, and where it is mounted there.
# Not under `/mnt`, which is where the installer mounts the system it is
# building and where mounting would be mounting over its own inputs; and not
# under `/media` either, which the installer unmounts when an installation
# starts.
readonly SHARE_TAG=oparch_case
readonly SHARE_MOUNT=/run/oparch-case

# The console the guest answers on. A serial line carries no window size of its
# own, so the guest is given one, and it is generous: what is read is what the
# guest wrote, and a narrow terminal wraps and truncates exactly that.
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
# read while waiting.
readonly WAIT_SHELL=900
readonly WAIT_COMMAND=300
readonly WAIT_POWEROFF=300
readonly POLL=2

# The guest being driven. There is one at a time.
GUEST_PID=""
GUEST_LOG=""
GUEST_INPUT=""
GUEST_COMMANDS=0
GUEST_TOKEN=""

guest_say() {
    printf '    %s\n' "$*" >&2
}

# Whether the guest has a network: `present` gives it one through QEMU's own
# user-mode networking, and `none` gives it none.
guest_network() {
    case "$1" in
        none)
            GUEST_NETWORK=(-nic none)
            ;;
        present)
            GUEST_NETWORK=(-netdev user,id=net0 -device virtio-net,netdev=net0)
            guest_say "the guest has a network"
            ;;
        *)
            guest_say "FAILED: $1 is not something a guest's network can be"
            return 1
            ;;
    esac
}

# Hardware acceleration when `/dev/kvm` can be read and written, and emulation
# when it cannot. Which one a guest got is said out loud, because it is the
# difference between a run somebody waits for and a run somebody leaves.
guest_acceleration() {
    if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
        GUEST_ACCELERATION=(-machine q35,accel=kvm -cpu host)
        guest_say "using hardware acceleration"
    else
        GUEST_ACCELERATION=(-machine q35,accel=tcg -cpu qemu64)
        guest_say "no /dev/kvm: emulating, which is slow"
    fi
}

# Starts a guest and leaves it driveable. Its console is a file that is read and
# a fifo that is written, and the fifo is held open for reading and writing
# here: a fifo whose only writer closes it hands the guest an end of input it
# cannot come back from, and this way there is always a writer.
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
    # `exec 9>&- 2>/dev/null` closes the console and sends everything the caller
    # has left to say into the same hole — a failure after it included.
    { exec 9>&-; } 2>/dev/null || :
    rm -f "$GUEST_INPUT"
    GUEST_PID=""
}

# Waits for the guest to end on its own, and kills it when it will not. The
# disk an installation wrote is only safe to boot once the process holding it
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
    guest_say "the guest did not power off; killing it"
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
# all. Those are three different things — a refusal is not a hang — so they are
# three statuses.
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

# A command held to succeeding, and said out loud either way. What a check that
# does not hold stops is the caller's to decide.
guest_check() {
    local what="$1"
    local command="$2"
    local seconds="${3:-$WAIT_COMMAND}"
    local status=0

    guest_run "$command" "$seconds" || status=$?
    case "$status" in
        0) guest_say "ok: $what"; return 0 ;;
        1) guest_say "FAILED: $what" ;;
        *) guest_say "FAILED: $what (nothing came back)" ;;
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
            guest_say "FAILED: the guest ended before the console answered"
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
    guest_say "FAILED: the guest never reached a shell on the serial console"
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
        guest_say "FAILED: the console never came back without line editing"
        return 1
    fi
    guest_send "stty -echo rows $CONSOLE_ROWS cols $CONSOLE_COLUMNS"
    guest_check "the console answers with what the guest produced" true
}
