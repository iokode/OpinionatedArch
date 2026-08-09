# Installation Overview

OpinionatedArch is installed from an Arch Linux live environment. The installer collects every target-specific value through interactive prompts and produces a reboot-ready system in one run.

## Running the Installer

1. Boot an Arch Linux live environment (archiso).
2. Clone or copy this repository into that environment.
3. From the repository root, run:

```bash
./installer/install.sh
```

4. Answer the interactive prompts.

## Installation Flow

1. Collect installer input.
2. Prepare target disk and mount points.
3. Install base system.
4. Generate system configuration required for first boot.
5. Run chroot configuration.
6. Finalize installation to reboot-ready state.

The installer runs in two phases. The live phase, under `installer/phase-live/`, works from the live environment on the target disk. The chroot phase, under `installer/phase-chroot/`, configures the installed system before first boot.

## Install Modes

The installer offers two modes:

- `wipe-all` repartitions the selected disk and destroys all previous data on it.
- `keep-homes` reinstalls the system while preserving selected existing home subvolumes, and creates their users again alongside any additional login users requested.

See [Disk Layout](../decisions/002-disk-layout.md).

## What the Installer Asks

Prompts cover the target disk and install mode, startup policy, microcode and GPU driver, swap sizes, login usernames, the shared secret, keymap, timezone, hostname, an optional public dotfiles repository, and the optional pre-boot return message with its ownership fields, languages, and logo.

The complete prompt list, the bootstrap package set, and the services enabled before first boot are in [Installer Inputs and Bootstrap Baseline](../decisions/000-installer-inputs-and-bootstrap-baseline.md).

## Baseline Assumption

The installer assumes it starts from a clean Arch live environment. It does not carry defensive handling for install state that cannot exist in that baseline.
