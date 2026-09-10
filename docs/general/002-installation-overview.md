# Installation Overview

OpinionatedArch is installed from an Arch Linux live environment. The installer collects every target-specific value through interactive prompts and produces a reboot-ready system in one run.

## Running the Installer

1. Boot an Arch Linux live environment.
2. Run `curl -fsSL https://oparch.iokode.dev/install.sh | bash`, which puts the installer on it and starts it.
3. Answer the prompts — or hand the installer a file with `--config` and answer nothing.

Step 2 fetches everything, so it wants a network from the start; what it does and why it is shaped that way is [Installation Script](../decisions/017-installation-script.md). The other way in is an image of this project's own, which carries all of it already, needs no network, and starts the installer without being asked: [Installation ISO](../decisions/018-installation-iso.md) decides it and it does not exist yet.

The command and its options are [oparch-installer](../tools/oparch-installer/000-command.md).

## Installation Flow

1. Collect installer input, and bring in everything it names.
2. Prepare the target disk and its mount points.
3. Install the base system.
4. Configure the installed system for first boot: localization, identity, users and groups, network, swap.
5. Render the pre-boot return message, when one was asked for.
6. Build the initramfs and install the bootloader.
7. Apply the dotfiles package, when one was given.

Every step is required and the run stops at the first failure: an installation either finishes in full or it fails. Two of the steps are present only when the installation was given what they act on, so a run never lists a step that will not happen.

The installer works on a system it is not running on. It writes into the mounted target directly, and enters it with `arch-chroot` only for the commands that have to see it as their own root — one answer for both, described in [Where a Command Runs](../development/003-where-a-command-runs.md).

## Install Modes

The installer offers two modes:

- `wipe-all` repartitions the selected disk and destroys all previous data on it.
- `keep-homes` reinstalls the system while preserving selected existing home subvolumes, and recreates those work contexts alongside any further one requested.

See [Disk Layout](../decisions/001-disk-layout.md).

## What the Installer Asks

The keymap is asked first, and applied to the console at once, so that everything after it is typed with it. The network comes next and is the one screen that may not appear: a machine that already reaches the package repository is not stopped to be told so, and one that does not is offered a Wi-Fi network, another look, or going on without one. The rest cover the target disk and install mode, microcode and GPU driver, swap sizes, the work contexts, the shared secret, timezone, hostname, an optional public dotfiles package with the encrypted secret store its map may need, and the optional pre-boot return message with its ownership fields, languages, and logo.

The complete prompt list, the bootstrap package set, and the services enabled before first boot are in [Installer Inputs and Bootstrap Baseline](../tools/oparch-installer/002-inputs-and-bootstrap-baseline.md).

## Baseline Assumption

The installer assumes it starts from a clean Arch live environment. It does not carry defensive handling for install state that cannot exist in that baseline.
