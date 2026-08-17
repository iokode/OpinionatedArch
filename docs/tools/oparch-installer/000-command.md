# oparch-installer

## Description

`oparch-installer` installs OpinionatedArch onto a target disk. It runs from the live environment, collects every installation input, and then performs the installation defined in [Installer Inputs and Bootstrap Baseline](002-inputs-and-bootstrap-baseline.md).

Inputs are collected in one of two ways, and both produce the same configuration:

- Interactively, through a terminal interface that asks one screen at a time.
- From a configuration file, which answers every question at once. The format is defined in [Installer Configuration File Format](001-config-file-format.md).

The tool presumes it runs inside the live installation environment: it calls `lsblk`, `localectl`, `timedatectl` and `pacstrap` directly and does not check whether they exist.

## Why is needed

The installation is not a single command: it partitions and encrypts a disk, creates a subvolume layout, bootstraps a base system and configures it before first boot. Doing that by hand is neither repeatable nor verifiable. One tool owns the whole sequence, so an installation can be reproduced from a recorded configuration instead of from memory.

## Requirements

What has to be on the live environment before this runs. It is not checked for: the installer presumes the environment it is documented to run in and calls what it needs without asking whether it is there, which is what [End-to-End Testing](../../development/006-end-to-end-testing.md) argues for and against testing it anywhere else.

The Arch live medium already carries most of it: `gptfdisk` for `sgdisk`, `cryptsetup`, `btrfs-progs`, `dosfstools` for `mkfs.fat`, `arch-install-scripts` for `pacstrap`, `arch-chroot` and `genfstab`, `util-linux` for `blkid`, `lsblk`, `mount` and `wipefs`, `parted` for `partprobe`, `systemd` for `udevadm`, `localectl` and `timedatectl`, `kbd` for `loadkeys`, and `curl` and `tar`.

Three things are not on it, and each has to be installed before a run:

- **`git`**, and only when the dotfiles package is taken from a repository. It is cloned with its history, because `/dotfiles` stays the repository [Disk Layout](../../decisions/001-disk-layout.md) restores from.
- **`fontconfig`**, for `fc-scan`, when the chosen theme carries a font of its own: the family a font file declares is read from the file rather than trusted from the manifest.
- **The BAML runtime library.** This tool has a host, so its binary loads a shared library of about 25 MB rather than carrying it. Where it comes from is [Host Bridge](../../development/001-host-bridge.md); on the project's own medium it is shipped and pointed at with `BAML_LIBRARY_PATH`, and `BAML_LIBRARY_DISABLE_DOWNLOAD` turns a missing one into a failure instead of a silent download.

It also needs the two tools it calls by name, findable on `PATH`: `oparch-return-message-render` when a return message was asked for, and `oparch-dotfiles-sync` when a dotfiles package was, which it copies into the target before entering it. What each of those needs is in its own document, and the return message's needs are the ones most often missing from a live medium.

What the *installed* system gets is a different list and is not this one: it is the bootstrap package set in [Installer Inputs and Bootstrap Baseline](002-inputs-and-bootstrap-baseline.md).

## Input parameters

- `--config <path>`: Optional. Answer every question from this file instead of asking. Without it, the terminal interface is shown.
- `--assets <path>`: Optional. Directory holding installer assets, including the project's return-message template package, read from `<path>/return-message`. Default: `assets`.

The exit status is `0` when the installation finished, and non-zero when it was cancelled, when the configuration file could not be used, or when an installation step failed.

## Interactive usage

Without `--config`, the tool takes over the terminal and asks nine screens in order: keymap, target disk, data preservation, hardware, work contexts, locale and identity, dotfiles, return message, and a summary.

The keymap is first because it is the only answer that changes how every later answer is typed: it is applied to the console the moment it is given.

The left pane lists the screens and marks which are done. The right pane shows the current one. Answers are validated as they are given, and an invalid answer is reported without leaving the screen.

Navigation:

| Key | Action |
| --- | --- |
| `↑` `↓` | Move within a list |
| Typing | Filter the list |
| `Enter` | Select, or accept a text field |
| `Space` | Toggle an entry in a multiple-choice list |
| `Esc`, `F1` | Go back one screen; on the first screen, cancel the installation |
| `F2` | Start the installation, from the summary screen only |
| `F3` | About |
| `F4` | Change the verbose level |
| `F6` | Exit |
| `F7` | Power off the machine |

Nothing is written to the target disk until `F2` is pressed on the summary screen, which lists every collected setting.

The verbose level selects how much of the installation is shown while it runs: `0` shows the current step and its progress, `1` adds the installer's own messages, and `2` adds the output of every command. Output is captured at every level, so raising the level does not lose what already happened. The level is chosen before the installation starts; once it is running, the keyboard is not read.

With `--config`, no terminal is taken over and no question is asked. Progress is reported as plain timestamped lines, so the run can be logged and read by a test.
