# End-to-End Testing

End-to-end tests boot the real Arch live environment under QEMU and run the installer inside it, against a disposable disk image. Everything below the installer — `pacstrap`, `arch-chroot`, `cryptsetup`, `sgdisk` — is the genuine article, and the result is verified by booting the disk that was just installed.

This document describes the harness. It does not describe the installer, which is documented in `../tools/oparch-installer/000-command.md`.

## Why the installer is not tested on the development machine

The installer presumes it runs inside the live installation environment. It calls `arch-chroot`, `pacstrap` and `sgdisk` without checking whether they exist, and it is meant to stay that way: environment checks scattered through the installation phases would buy test convenience with permanent complexity in the code that matters most.

Attaching a disk image to a loop device on the development machine would exercise the partitioning phase, but only there, and only by installing the live environment's tooling onto a machine that is not it. Giving the installer the environment it expects is both more faithful and less work.

QEMU is used rather than the desktop hypervisor already available because the harness has to be a command, not a session: it boots a raw image directly, exposes the guest's console as text on standard output, resets to a clean disk with a copy-on-write overlay, and runs headless. The desktop hypervisor remains the better tool for driving the interface by hand.

## What the harness needs from the installer

The installer's configuration file is what makes the run automatable. With `--config`, no terminal is taken over, no question is asked, and progress is reported as plain timestamped lines that a test can read. Driving the interactive interface over a serial console instead would mean scripting escape sequences against a redrawing terminal, which is brittle in ways that have already been observed.

## Shape of a run

1. Create a disposable disk from a base image with `qemu-img create -f qcow2 -b`, so each run starts from the same state and leaves nothing behind.
2. Boot the Arch ISO with that disk attached, the kernel and initramfs extracted from the ISO so `console=ttyS0` can be passed on the kernel command line, and `-nographic -serial mon:stdio` so the guest's console is the harness's standard output.
3. Expose the installer binary, its runtime library, its assets and the configuration file to the guest through a 9p mount, so a new build is tested without rebuilding the ISO.
4. Run the installer with `--config`, and read its output from the serial console.
5. Boot the resulting disk again, this time without the ISO, and assert on the boot: the bootloader entry, the passphrase prompt, and reaching a login.

Steps 4 and 5 are what distinguish this from the unit tests. The BAML test suite already verifies which commands the installer decides to run, against recording doubles and with no privileges. The harness verifies that those commands, run for real and in order, produce a system that boots.

## State

The harness is not built yet. The installer side of it is: `--config` exists, is covered by tests, and reports plainly without a terminal.

Not yet resolved:

- Whether the Arch ISO exposes a boot parameter that runs a script from the mounted media, which would remove the need to type anything into the serial console.
- Where the base ISO comes from, and whether the harness downloads it or expects it to be provided.
- Whether the guest reaches the network for `pacstrap`, or is given a local package cache through a second 9p mount, which is faster and makes runs reproducible.
