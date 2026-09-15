# oparch-installer-interactive

## Description

`oparch-installer-interactive` is the interactive interface for installing OpinionatedArch. It runs from the live environment, asks every installation input through a terminal interface one screen at a time, and installs through the installer library, which [oparch-installer](../../installer/unattended/000-command.md) is built on too, so an installation made from its screens is the one a configuration file would make.

The screens act on the live environment where the operator needs them to: the keymap is applied to the console as it is chosen, a wireless network is connected to from the network screen, and a device can be mounted to take a source from it, as [Installer Input Sources](../../installer/unattended/003-input-sources.md) describes. None of that is part of the installation.

## Why is needed

Installing by hand means answering in front of the machine, and several answers are easier to give seeing what the machine has: its disks, the networks in range, the keymaps and timezones it offers. The screens validate answers as they are given, so a wrong one is corrected on the screen it was given on.

## Requirements

Everything [oparch-installer](../../installer/unattended/000-command.md) requires, because it installs through the same library. On top of that, what its screens call, which the Arch live medium also carries: `kbd` for `loadkeys`, `iproute2` for `ip`, and `iwd` for `iwctl`.

`iwctl` talks to a daemon, and on a live medium that daemon is running: it is how `releng` is built, and this project's own image is built from it. `ip` is read for the machine's wireless interfaces rather than `iwctl` being asked, because one prints a line per interface and the other prints a table drawn for a person to look at.

And two things of its own:

- **The BAML runtime library.** This tool has a host, so its binary loads a shared library of about 25 MB rather than carrying it. Where it comes from is [Host Bridge](../../../development/001-host-bridge.md). It comes in a package of its own, `oparch-baml-runtime`, which this tool's package depends on, and what goes on `PATH` is a wrapper that names it with `BAML_LIBRARY_PATH`, along with `BAML_LIBRARY_DISABLE_DOWNLOAD`, which turns a missing one into a failure instead of a silent download.
- **Its assets.** The wrapper names those too, at the one place [Oparch Tools](../../../decisions/015-oparch-tools.md) keeps them, because this tool's own default is a directory beside its binary and that is not where the project puts them.

## Input parameters

- `--assets <path>`: Optional. Directory holding installer assets, including the project's return-message template package, read from `<path>/return-message`. Default: `assets`.

The exit status is `0` when the installation finished, and non-zero when it was cancelled or when an installation step failed.

## Interactive usage

The tool takes over the terminal and asks ten screens in order: keymap, network, target disk, data preservation, hardware, work contexts, locale and identity, dotfiles, return message, and a summary.

The keymap is first because it is the only answer that changes how every later answer is typed: it is applied to the console the moment it is given.

The network is second, and it is the one screen that may ask nothing: a machine already reaching the package repository is not stopped to be told so. It comes after the keymap because a wireless passphrase is typed like every other answer.

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
