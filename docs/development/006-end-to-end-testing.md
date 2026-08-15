# End-to-End Testing

End-to-end tests boot the real Arch live environment under QEMU and run the installer inside it, against a disposable disk image. Everything below the installer — `pacstrap`, `arch-chroot`, `cryptsetup`, `sgdisk` — is the genuine article, and the result is verified by booting the disk that was just installed.

This document describes the harness. It does not describe the installer, which is documented in [oparch-installer](../tools/oparch-installer/000-command.md).

The harness is `tests/e2e/run.sh`. It is the only test that lives outside the source of a tool, for the reason [Repository Layout](002-repository-layout.md) gives: it belongs to no project and tests all of them at once, where a unit test is a `test` block compiled with the code it exercises.

## Why the installer is not tested on the development machine

The installer presumes it runs inside the live installation environment. It calls `arch-chroot`, `pacstrap` and `sgdisk` without checking whether they exist, and it is meant to stay that way: environment checks scattered through the installation phases would buy test convenience with permanent complexity in the code that matters most.

Attaching a disk image to a loop device on the development machine would exercise the partitioning phase, but only there, and only by installing the live environment's tooling onto a machine that is not it. Giving the installer the environment it expects is both more faithful and less work.

QEMU is used rather than the desktop hypervisor already available because the harness has to be a command, not a session: it boots a raw image directly, exposes the guest's console as text on standard output, resets to a clean disk with a copy-on-write overlay, and runs headless. The desktop hypervisor remains the better tool for driving the interface by hand.

## What the harness needs from the installer

The installer's configuration file is what makes the run automatable. With `--config`, no terminal is taken over, no question is asked, and progress is reported as plain timestamped lines that a test can read. Driving the interactive interface over a serial console instead would mean scripting escape sequences against a redrawing terminal, which is brittle in ways that have already been observed.

## Shape of a run

1. Create a disposable disk from a base image with `qemu-img create -f qcow2 -b`, so each run starts from the same state and leaves nothing behind.
2. Boot the Arch ISO with that disk attached, the kernel and initramfs extracted from the ISO so `console=ttyS0` can be passed on the kernel command line, and `-nographic -serial mon:stdio` so the guest's console is the harness's standard output.
3. Expose the installer binary, its runtime library, `oparch-return-message-render`, `oparch-dotfiles-sync`, the assets, the fixtures and the configuration file to the guest through a 9p mount, so a new build is tested without rebuilding anything.
4. Run the installer with `--config`, and read its output from the serial console.
5. Boot the resulting disk again, this time without the ISO, and assert on the boot: the bootloader entry, the passphrase prompt, and reaching a login.

Steps 4 and 5 are what distinguish this from the unit tests. The BAML test suite already verifies which commands the installer decides to run, against recording doubles and with no privileges. The harness verifies that those commands, run for real and in order, produce a system that boots.

## The medium the harness boots

The harness boots the **official Arch ISO**, not the one this project will ship. That ISO is built with `archiso` and does not exist yet, and it is the last thing this project builds: everything it would carry has to work before there is a point in carrying it.

Two things follow, and they are the harness's own work rather than the installer's:

- The live environment is missing what the tools require of it. The harness installs `imagemagick`, `pango`, `noto-fonts` and `git` with `pacman` in the guest before running the installer; which tool needs which, and why installing ImageMagick does not bring Pango, is the `Requirements` section of each tool's command document. On the project's own ISO they are already installed, so this step disappears when that ISO arrives.
- There is no package cache to install from, so the guest reaches the network, both for those two packages and for `pacstrap`. The project's own ISO will carry its packages in its cache; until then, a run needs the network and is only as reproducible as the mirrors it hits.

The ISO is provided rather than downloaded: the harness is given a path to one and does not go looking for it. It is not versioned — it is over a gigabyte, and it is an input to a test rather than part of the project.

Nothing autostarts inside the guest. The harness types the installer's command over the serial console itself, which needs no boot parameter and no support from the medium. The project's own ISO will start the installer on its own, which `archiso` provides for; the harness does not, because it also has to run against the official ISO, which does not.

### What running it on an official ISO costs

Three things had to be dealt with before an installation would complete, and all three are the medium's age rather than the installer's doing. They are written down because they look like bugs in the installation the first time they are met.

- **The live environment is older than the mirrors it installs from.** An ISO from July gets an ImageMagick built against a newer glibc than it carries, and the first drawing command fails with a missing `GLIBC_2.44`. The way out is to upgrade the live environment, not just to install into it.
- **The upgrade must leave the running kernel alone.** Replacing `linux` deletes the modules of the kernel that is currently running, and the next `cryptsetup open` fails with `crypt: unknown target type`. The harness upgrades with `--ignore linux --ignore linux-firmware`.
- **The overlay the live system writes to is small.** Around 250 MB free is not enough for that upgrade, so the harness boots with `cow_spacesize=4G`, which is what `archiso` provides for.

None of this applies to the ISO this project will ship, which carries its own packages, at its own versions, already installed.

### What this harness cannot see

Its guest runs with `-nographic`, so there is no display for a splash. Plymouth falls back to the text prompt [Pre-Boot Ownership Message](../decisions/010-preboot-ownership-message.md) requires, which is worth knowing works, but the harness therefore never draws the composed message and never runs the script the renderer writes.

That is a limit of this harness. The splash itself was seen on 2026-08-11, on VMware and by hand: the machine booted to the return message screen, and Escape moved between it and the text prompt. A run with a display attached is what would bring that under the harness.

## The dotfiles step, case by case

These are the cases the dotfiles step has to be covered by. They are written here because there is nowhere else yet; each of them is a document of its own once there is a place for test specifications, and this section goes when they move.

Two fixtures are needed for all of them: a dotfiles package whose map declares a link, a copy and a render, and an encrypted store holding what that render references. Both live beside the configuration file the harness already hands the guest.

**A package is applied.** The configuration names a dotfiles package. After the installation, `/dotfiles` holds what the package held; its directories are `2775` and its files `664`; the default ACL [Dotfiles](../decisions/019-dotfiles.md) requires is on it; `/dotfiles` is in git's system `safe.directory`; and each of the three operations the map declared has produced its target, owned by the user the map named.

**A repository stays a repository.** The same run with the package taken from a `git` origin. Afterwards `/dotfiles` is a repository with its history and its remote, not a checkout of one revision.

**A map that needs secrets gets them.** The configuration also names the encrypted store and its passphrase. Afterwards the rendered target holds the secret's value, and the store on the installed system is `0700` at its root and `0600` at each file, owned `root:root`.

**A package that does not hold what it declares is refused.** A map naming a file that is not in the package. The run stops before the disk is touched, and says which file and where the map says it should be.

**A passphrase that does not open the store is refused.** The same, stopping for that reason and saying so, with the disk equally untouched.

The last two are what makes the first three worth having: they are the cases where the installation is meant not to happen, and the assertion is on the disk being as it was.

## State

The harness runs all five steps. It boots the live environment, drives it over the serial console, installs from a configuration file with every phase against the real `sgdisk`, `cryptsetup`, `mkfs.btrfs`, `pacstrap`, `arch-chroot`, ImageMagick and `mkinitcpio`, and then boots the disk it has just made, answers the passphrase, and waits for a login. It builds what it tests: the host embeds the BAML program at compile time, so a binary that was not rebuilt runs the previous one and says nothing about it.

One thing is deliberately not checked. The menu is reached by pressing a key while the machine starts, and GRUB draws that menu on the video console, which this guest does not have — so a check would be pressing keys it cannot see the effect of, and the attempt at one was still sending them when the passphrase prompt was up. That path was verified by hand instead.
