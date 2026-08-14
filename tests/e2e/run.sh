#!/usr/bin/env bash
#
# The end-to-end harness: boots the Arch live environment under QEMU, runs the
# installer inside it against a disposable disk, and boots what it installed.
# Described in docs/development/006-end-to-end-testing.md.
#
# The ISO is given, not downloaded, and nothing inside the guest autostarts:
# this drives the serial console itself, so it works on the official ISO.

set -euo pipefail

readonly ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly WORK="${ROOT}/tests/e2e/work"
readonly OVMF_CODE="/usr/share/edk2/x64/OVMF_CODE.4m.fd"
readonly OVMF_VARS="/usr/share/edk2/x64/OVMF_VARS.4m.fd"

# Long enough for pacstrap over a mirror, short enough that a wedged guest is
# not a hung terminal.
readonly REPLY_TIMEOUT=900

iso=""
keep=0

usage() {
    cat >&2 <<'USAGE'
usage: tests/e2e/run.sh --iso <path> [--keep]

  --iso <path>   the Arch live ISO to boot
  --keep         leave the work directory behind for inspection
USAGE
    exit 2
}

while (($# > 0)); do
    case "$1" in
        --iso) iso="${2-}"; shift 2 ;;
        --keep) keep=1; shift ;;
        *) usage ;;
    esac
done

[[ -n "${iso}" ]] || usage
[[ -f "${iso}" ]] || { echo "no such ISO: ${iso}" >&2; exit 1; }
[[ -f "${OVMF_CODE}" ]] || { echo "no UEFI firmware at ${OVMF_CODE}; install edk2-ovmf" >&2; exit 1; }

# ------------------------------------------------------------------ the guest

# The label is how archiso finds its own squashfs once the kernel is booted
# from outside the ISO, which is what passing `console=` on the command line
# costs us.
label="$(blkid -o value -s LABEL "${iso}")"
[[ -n "${label}" ]] || { echo "cannot read the ISO's label: ${iso}" >&2; exit 1; }

# One run at a time. Two of them share this directory, and the second wipes it
# while the first is still booting from it: what follows is a failure in the
# guest that has nothing to do with anything being tested.
if ps -C qemu-system-x86_64 -o args= 2>/dev/null | grep -qF "${WORK}"; then
    echo "harness: another run is already using ${WORK}" >&2
    echo "harness: wait for it, or stop it, before starting this one" >&2
    exit 1
fi

rm -rf "${WORK}"
mkdir -p "${WORK}/share/lib"

# ------------------------------------------------------- what the guest is given
#
# The harness tests what is built, not what an ISO carries, so the binaries and
# the assets travel over 9p.
#
# They are built here rather than assumed. The Rust host embeds the BAML
# program at compile time, so a phase added to the sources is not in the binary
# until it is rebuilt — and a run against yesterday's binary answers a question
# nobody asked, convincingly. That happened once; it is why this builds.

readonly INSTALLER="${ROOT}/src/installer/host/target/release/oparch-installer"
readonly RENDERER="${ROOT}/src/return-message-render/oparch-return-message-render"
readonly DOTFILES_SYNC="${ROOT}/src/dotfiles-sync/oparch-dotfiles-sync"
readonly DOTFILES_PACKAGE="${ROOT}/tests/e2e/share/dotfiles"
readonly CONFIG="${ROOT}/tests/e2e/share/install.yaml"

require() {
    [[ -e "$1" ]] || {
        echo "harness: missing $1" >&2
        echo "harness: build it with: $2" >&2
        exit 1
    }
}

# `cargo build` alone is not enough: what the host actually runs is the BAML
# program embedded in its generated SDK, and only `baml generate` puts a change
# to `baml_src/` there. Without this step a rebuilt binary still runs the old
# program, which is exactly as convincing and exactly as wrong.
echo "harness: building the installer"
baml --directory "${ROOT}/src/installer" generate >/dev/null
cargo build --release --quiet --manifest-path "${ROOT}/src/installer/host/Cargo.toml"

echo "harness: building the renderer"
( cd "${ROOT}/src/return-message-render" \
    && baml pack main --output ./oparch-return-message-render >/dev/null )

# The installer enters the target and runs this there, so what is tested is the
# tool as it ships rather than the one the unit tests link against.
echo "harness: building the dotfiles tool"
( cd "${ROOT}/src/dotfiles-sync" \
    && baml pack main --output ./oparch-dotfiles-sync >/dev/null )

require "${INSTALLER}" "cargo build --release --manifest-path src/installer/host/Cargo.toml"
require "${RENDERER}" "cd src/return-message-render && baml pack main --output ./oparch-return-message-render"
require "${DOTFILES_SYNC}" "cd src/dotfiles-sync && baml pack main --output ./oparch-dotfiles-sync"
require "${DOTFILES_PACKAGE}/main.dfmap" "it is committed; see tests/e2e/share/dotfiles"
require "${CONFIG}" "write it; see docs/tools/oparch-installer/001-config-file-format.md"

# The host binary loads the BAML runtime as a shared library. It is given the
# one this machine already has rather than left to fetch its own, which is also
# what the ISO will do: see docs/development/001-host-bridge.md.
baml_library="$(find "${HOME}/.cache/baml/libs" -name 'libbaml_cffi-*.so' 2>/dev/null | head -1)"
[[ -n "${baml_library}" ]] || {
    echo "harness: no BAML runtime library under ~/.cache/baml/libs" >&2
    exit 1
}

cp "${INSTALLER}" "${RENDERER}" "${DOTFILES_SYNC}" "${CONFIG}" "${WORK}/share/"
cp -r "${DOTFILES_PACKAGE}" "${WORK}/share/dotfiles"
cp "${baml_library}" "${WORK}/share/lib/"
cp -r "${ROOT}/assets" "${WORK}/share/assets"

echo "harness: extracting the kernel from ${iso##*/} (label ${label})"
bsdtar -xf "${iso}" -C "${WORK}" \
    arch/boot/x86_64/vmlinuz-linux arch/boot/x86_64/initramfs-linux.img

qemu-img create -f qcow2 "${WORK}/disk.qcow2" 20G >/dev/null
cp "${OVMF_VARS}" "${WORK}/OVMF_VARS.fd"

accel="tcg"
cpu="max"
if [[ -r /dev/kvm && -w /dev/kvm ]]; then
    accel="kvm"
    cpu="host"
fi
echo "harness: acceleration ${accel}"

# ------------------------------------------------- talking to the serial line
#
# The guest is driven through its serial console, which means matching text
# that does not always end in a newline — a shell prompt never does. So the
# reader takes one character at a time and matches against what it has seen,
# rather than reading lines.

seen=""

# Waits for a pattern to appear on the console. Everything read is echoed, so a
# failed run leaves the guest's own account of it on screen.
try_expect() {
    local pattern="$1" limit="$2" char
    local deadline=$((SECONDS + limit))
    seen=""
    while ((SECONDS < deadline)); do
        if IFS= read -r -N1 -t 2 char <&"${QEMU[0]}"; then
            printf '%s' "${char}"
            seen+="${char}"
            [[ "${seen}" == *"${pattern}"* ]] && return 0
        fi
    done
    return 1
}

expect() {
    local pattern="$1" limit="${2:-${REPLY_TIMEOUT}}"
    if try_expect "${pattern}" "${limit}"; then
        return 0
    fi
    echo >&2
    echo "harness: timed out after ${limit}s waiting for: ${pattern}" >&2
    return 1
}

# Reads whatever is still coming until the line goes quiet, so an answer to one
# command is never mistaken for the answer to the next.
drain() {
    local char
    while IFS= read -r -N1 -t 2 char <&"${QEMU[0]}"; do
        printf '%s' "${char}"
    done
    return 0
}

# A serial line ends with a carriage return. Sending a newline instead leaves
# the terminal joining what should have been two commands into one.
send() {
    printf '%s\r' "$1" >&"${QEMU[1]}"
}

# Nothing waits for a shell prompt. The prompt arrives interleaved with escape
# sequences — `root`, an escape, `@archiso` — so the text a person reads is
# never in the byte stream to match against. The guest is asked to say when it
# is done instead, and the marker is split where it is typed so that the shell
# echoing the command back is not mistaken for the answer to it.
readonly MARK="OPARCH"

# Waits for whichever of two markers arrives first. Answering with a word for
# each outcome, rather than with `$?`, is what keeps this from depending on a
# `?` surviving the wire: it did not, and the status came back empty.
expect_either() {
    local good="$1" bad="$2" limit="$3" char
    local deadline=$((SECONDS + limit))
    seen=""
    while ((SECONDS < deadline)); do
        if IFS= read -r -N1 -t 2 char <&"${QEMU[0]}"; then
            printf '%s' "${char}"
            seen+="${char}"
            [[ "${seen}" == *"${good}"* ]] && return 0
            [[ "${seen}" == *"${bad}"* ]] && return 1
        fi
    done
    echo >&2
    echo "harness: timed out after ${limit}s waiting for the guest to answer" >&2
    return 2
}

# Runs one command in the guest and fails the harness if it does.
run_in_guest() {
    local command="$1" limit="${2:-120}" outcome=0
    send "${command} && echo ${MARK}-O''K || echo ${MARK}-BA''D"
    expect_either "${MARK}-OK" "${MARK}-BAD" "${limit}" || outcome=$?
    if ((outcome != 0)); then
        echo >&2
        echo "harness: the guest failed at: ${command}" >&2
        return 1
    fi
}

cleanup() {
    if [[ -n "${QEMU_PID:-}" ]] && kill -0 "${QEMU_PID}" 2>/dev/null; then
        kill "${QEMU_PID}" 2>/dev/null || true
        wait "${QEMU_PID}" 2>/dev/null || true
    fi
    ((keep)) || rm -rf "${WORK}"
}
# Also on a signal: a harness that spawns virtual machines and is interrupted
# has to take them with it, or the next run shares the console with the last
# one and their output is read as one.
trap cleanup EXIT INT TERM

# ------------------------------------------------------------------- the boot

echo "harness: booting the live environment"

coproc QEMU {
    qemu-system-x86_64 \
        -machine q35,accel="${accel}" -cpu "${cpu}" -smp 4 -m 6144 \
        -drive "if=pflash,format=raw,readonly=on,file=${OVMF_CODE}" \
        -drive "if=pflash,format=raw,file=${WORK}/OVMF_VARS.fd" \
        -drive "file=${WORK}/disk.qcow2,if=virtio,format=qcow2" \
        -drive "file=${iso},media=cdrom,readonly=on" \
        -kernel "${WORK}/arch/boot/x86_64/vmlinuz-linux" \
        -initrd "${WORK}/arch/boot/x86_64/initramfs-linux.img" \
        -append "archisobasedir=arch archisolabel=${label} cow_spacesize=4G console=ttyS0,115200" \
        -virtfs "local,path=${WORK}/share,mount_tag=oparch,security_model=none" \
        -netdev user,id=net0 -device virtio-net,netdev=net0 \
        -nographic 2>&1
}
QEMU_PID=$!

expect "archiso login:" 300
send "root"

# Nothing here waits a fixed time for the shell to take over from `login`:
# anything typed while `login` still has the line is swallowed by it, and how
# long that takes is not ours to know. So it asks until it is answered.
wait_for_shell() {
    local attempt
    for attempt in {1..20}; do
        # `stty -echo` alone does not hold: readline puts the terminal back
        # the way it wants it at every prompt, which is also what doubles the
        # first character of each line. Replacing the shell with one that does
        # no line editing is what makes the echo stay off, and with it only
        # what the guest produces comes back — never what it was told to do.
        send "exec bash --noediting"
        send "stty -echo"
        send "echo ${MARK}-RE''ADY"
        if try_expect "${MARK}-READY" 6; then
            drain
            return 0
        fi
    done
    echo >&2
    echo "harness: the guest never reached a shell" >&2
    return 1
}
wait_for_shell

echo
echo "harness: the live environment is up"

# The share is not mounted under /mnt: that is where the installer mounts the
# system it is building, and it would be mounting over its own inputs.
readonly SHARE="/oparch"

echo "harness: mounting what the host shares, at ${SHARE}"
run_in_guest "mkdir -p ${SHARE}"
run_in_guest "mount -t 9p -o trans=virtio,version=9p2000.L oparch ${SHARE}"

echo
echo "harness: the share is mounted"

# ------------------------------------------------------- what the ISO lacks
#
# The official ISO does not carry what the return message is drawn with. The
# project's own will, and then this step goes away: see
# docs/development/006-end-to-end-testing.md.

echo "harness: installing what the live environment is missing"
# The live environment is older than the mirrors it installs from, so what it
# gets is built against a newer glibc than it has. Upgrading is the way out of
# that, but not the kernel: replacing `linux` takes the running kernel's modules
# with it, and the next `cryptsetup open` fails with `crypt: unknown target
# type` because the module for the kernel that is actually running is gone.
run_in_guest "pacman -Syu --noconfirm --ignore linux --ignore linux-firmware imagemagick pango noto-fonts git" 1200

# The installer runs the renderer by name, so it has to be findable by name.
run_in_guest "install -m755 ${SHARE}/oparch-return-message-render /usr/local/bin/"
# The installer looks the tool up by name to copy it into the target.
run_in_guest "install -m755 ${SHARE}/oparch-dotfiles-sync /usr/local/bin/"

# ----------------------------------------------------------- the installation

echo
echo "harness: installing"

if ! run_in_guest "BAML_LIBRARY_PATH=\$(echo ${SHARE}/lib/libbaml_cffi-*.so) BAML_LIBRARY_DISABLE_DOWNLOAD=1 ${SHARE}/oparch-installer --config ${SHARE}/install.yaml --assets ${SHARE}/assets" 1800; then
    # The installer reports a phase's exit status and not what the tool it ran
    # had to say, so the tool is asked again, by hand, with what the phase left
    # behind. Its own message is what a failing run is worth having.
    echo
    echo "harness: asking the renderer directly, for the message the phase swallowed"
    send "oparch-return-message-render --config /mnt/etc/opinionatedarch/return-message.yaml --assets ${SHARE}/assets --output /mnt/usr/share/plymouth/themes/opinionatedarch; echo ${MARK}-DIAGNO''SED"
    expect "${MARK}-DIAGNOSED" 180 || true

    # The renderer reports the exit status of a drawing command and not what
    # the command said, so the command is run again with its own voice.
    echo
    echo "harness: asking ImageMagick itself"
    send "magick -version | head -2; magick -list format | grep -i pango || echo NO-PANGO-DELEGATE; echo ${MARK}-PRO''BED"
    expect "${MARK}-PROBED" 60 || true
    send "cat /tmp/oparch-return-message/heading-es.markup; echo; magick -background none -size 800x -define pango:markup=true 'pango:@/tmp/oparch-return-message/heading-es.markup' /tmp/probe.png; echo ${MARK}-DRA''WN"
    expect "${MARK}-DRAWN" 60 || true
    exit 1
fi

echo
echo "harness: the installation reported success"

# ------------------------------------------------------------- the dotfiles
#
# The case in docs/development/006-end-to-end-testing.md: a package is applied.
# What is checked is what nobody would notice missing — the modes and the ACL
# that decide whether the operator can edit their own configuration afterwards,
# and one target per operation the map declares.

echo
echo "harness: what the dotfiles step left behind"
run_in_guest "test \"\$(stat -c '%a %U:%G' /mnt/dotfiles)\" = '2775 root:dotfiles'"
run_in_guest "getfacl -p /mnt/dotfiles | grep -q '^default:group::rwx'"
run_in_guest "test \"\$(stat -c '%a' /mnt/dotfiles/shell)\" = '2775'"
run_in_guest "grep -q 'directory = /dotfiles' /mnt/etc/gitconfig"
run_in_guest "test -L /mnt/home/personal/.aliases.sh"
run_in_guest "test -f /mnt/home/work/.profile"
run_in_guest "grep -q 'personal@example.invalid' /mnt/home/personal/.gitconfig"
run_in_guest "grep -q 'work@example.invalid' /mnt/home/work/.gitconfig"

# ---------------------------------------------------------------- the reboot
#
# Step 5, and the one the unit tests cannot reach: the disk that was just
# installed is booted on its own, with no ISO attached, and asked to prove it
# gets as far as the passphrase.

# What the firmware will be asked to find, recorded while there is still a
# system that can be asked about it.
echo
echo "harness: what the installation left for the firmware"
send "find /mnt/boot/EFI -type f; efibootmgr -v; echo ${MARK}-INSPEC''TED"
expect "${MARK}-INSPECTED" 60 || true

# The installed machine has no screen here, and its kernel writes where a
# screen would be. The harness adds a serial console to the one file that is
# generated per machine, leaving the menu the project ships untouched: what is
# tested is still the boot chain the installer built, and the only difference
# is where the kernel's own messages come out.
echo
echo "harness: giving the installed kernel a serial console"
run_in_guest "sed -i 's/^set linux_extra=\"\\(.*\\)\"/set linux_extra=\"\\1 console=tty0 console=ttyS0,115200\"/' /mnt/boot/grub/oparch.cfg"
run_in_guest "cat /mnt/boot/grub/oparch.cfg"

echo
echo "harness: shutting the live environment down"
send "poweroff"
wait "${QEMU_PID}" 2>/dev/null || true
unset QEMU_PID

echo "harness: booting what was installed"

coproc QEMU {
    qemu-system-x86_64 \
        -machine q35,accel="${accel}" -cpu "${cpu}" -smp 4 -m 4096 \
        -drive "if=pflash,format=raw,readonly=on,file=${OVMF_CODE}" \
        -drive "if=pflash,format=raw,file=${WORK}/OVMF_VARS.fd" \
        -drive "file=${WORK}/disk.qcow2,if=virtio,format=qcow2" \
        -netdev user,id=net0 -device virtio-net,netdev=net0 \
        -nographic 2>&1
}
QEMU_PID=$!

# The unlock prompt is what proves the chain: firmware found the bootloader,
# the bootloader found the kernel this project's menu names, and the initramfs
# reached the hook that asks for the passphrase.
# The menu is not checked here. A key pressed while it starts is what brings it
# up, and that was verified by hand on a machine with a screen.
#
# It is not checked because this guest has no screen: GRUB draws the menu on
# the video console, so none of it reaches the serial line, and a check that
# cannot see what it is waiting for has no way to know when to stop pressing.
# The attempt that was made kept sending keys long past GRUB, with the
# passphrase prompt already up, and that run did not reach a login. What became
# of those keys was never established; what was established is that a check
# able to interfere with the unlock it is validating is not worth having.
expect "A password is required to access the cryptroot volume" 300

echo
echo "harness: it boots, and it is asking for the passphrase"

# The prompt alone proves the chain as far as the initramfs. Answering it is
# what proves the rest: that the container opens with the secret the
# installation was given, that the root subvolume mounts, and that the system
# it built reaches a login.
send "harness secret"
expect "oparch login:" 300

echo
echo "harness: it unlocked, and reached a login"
