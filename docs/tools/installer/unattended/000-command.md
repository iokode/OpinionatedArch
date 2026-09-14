# oparch-installer

## Description

`oparch-installer` installs OpinionatedArch onto a target disk without asking anything. It runs from the live environment, takes every installation input from a configuration file, and then performs the installation defined in [Installer Inputs and Bootstrap Baseline](002-inputs-and-bootstrap-baseline.md). The format of that file is defined in [Installer Configuration File Format](001-config-file-format.md).

It takes over no terminal. Progress is reported as plain timestamped lines, so the run can be logged and read by a test. What a command wrote is reported once the command has finished.

Its interactive version is [oparch-installer-interactive](../../installer/interactive/000-command.md), which collects the same inputs through screens and installs through the same library.

The tool presumes it runs inside the live installation environment: it calls `lsblk`, `localectl`, `timedatectl` and `pacstrap` directly and does not check whether they exist.

## Why is needed

The installation is not a single command: it partitions and encrypts a disk, creates a subvolume layout, bootstraps a base system and configures it before first boot. Doing that by hand is neither repeatable nor verifiable. One tool owns the whole sequence, so an installation can be reproduced from a recorded configuration instead of from memory.

## Requirements

What has to be on the live environment before this runs. It is not checked for: the installer presumes the environment it is documented to run in and calls what it needs without asking whether it is there, which is what [End-to-End Testing](../../../development/006-end-to-end-testing.md) argues for and against testing it anywhere else.

The Arch live medium already carries most of it: `gptfdisk` for `sgdisk`, `cryptsetup`, `btrfs-progs`, `dosfstools` for `mkfs.fat`, `arch-install-scripts` for `pacstrap`, `arch-chroot` and `genfstab`, `util-linux` for `blkid`, `lsblk`, `mount` and `wipefs`, `parted` for `partprobe`, `systemd` for `udevadm`, `localectl` and `timedatectl`, and `curl` and `tar`.

The rest has to be there before a run, whether the medium carries it or not:

- **`git`**, and only when the dotfiles package is taken from a repository. It is cloned with its history, because `/dotfiles` stays the repository [Disk Layout](../../../decisions/001-disk-layout.md) restores from.
- **`fontconfig`**, for `fc-scan`, when the chosen theme carries a font of its own: the family a font file declares is read from the file rather than trusted from the manifest.
- **`age`**, 1.3.1 or later, when the dotfiles map declares secrets: `age-inspect` tells a secret store from any other file, and `age` with its `batchpass` plugin opens it. The plugin is what reads the passphrase from a file descriptor, where `age` alone asks a terminal for one.
- **Its assets**, at the one place [Oparch Tools](../../../decisions/015-oparch-tools.md) keeps them, which is where this tool reads them unless it is told otherwise.

It also needs the two tools it calls by name, findable on `PATH`: `oparch-return-message-render` when a return message was asked for, and `oparch-dotfiles-sync` when a dotfiles package was, which it copies into the target before entering it. What each of those needs is in its own document, and the return message's needs are the ones most often missing from a live medium.

None of that has to be arranged by hand: all of it is what this tool's package declares, so installing the tool brings it. Which is [Package Repository](../../../decisions/016-package-repository.md) and not anything decided here — this section names what the tool calls, whoever put it there, because a list that named a way of installing would have to be edited every time one changed.

What the *installed* system gets is a different list and is not this one: it is the bootstrap package set in [Installer Inputs and Bootstrap Baseline](002-inputs-and-bootstrap-baseline.md).

## Input parameters

- `--config <path>`: Mandatory. File every installation input is taken from.
- `--assets <path>`: Optional. Directory holding installer assets, including the project's return-message template package, read from `<path>/return-message`. Default: `/usr/share/opinionatedarch/assets`.

The exit status is `0` when the installation finished, `2` when the command line is wrong or the configuration file cannot be read, and `1` when the configuration file could not be used or when an installation step failed.
