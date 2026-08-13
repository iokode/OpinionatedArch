# oparch-installer

## Description

`oparch-installer` installs OpinionatedArch onto a target disk. It runs from the live environment, collects every installation input, and then performs the installation defined in `002-inputs-and-bootstrap-baseline.md`.

Inputs are collected in one of two ways, and both produce the same configuration:

- Interactively, through a terminal interface that asks one screen at a time.
- From a configuration file, which answers every question at once. The format is defined in `001-config-file-format.md`.

The tool presumes it runs inside the live installation environment: it calls `lsblk`, `localectl`, `timedatectl` and `pacstrap` directly and does not check whether they exist.

## Why is needed

The installation is not a single command: it partitions and encrypts a disk, creates a subvolume layout, bootstraps a base system and configures it before first boot. Doing that by hand is neither repeatable nor verifiable. One tool owns the whole sequence, so an installation can be reproduced from a recorded configuration instead of from memory.

## Input parameters

- `--config <path>`: Optional. Answer every question from this file instead of asking. Without it, the terminal interface is shown.
- `--assets <path>`: Optional. Directory holding installer assets, including the project's return-message template package, read from `<path>/return-message`. Default: `assets`.

The exit status is `0` when the installation finished, and non-zero when it was cancelled, when the configuration file could not be used, or when an installation step failed.

## Interactive usage

Without `--config`, the tool takes over the terminal and asks nine screens in order: keymap, target disk, data preservation, hardware, users, locale and identity, dotfiles, return message, and a summary.

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
