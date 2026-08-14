# What Is Built

What this project has working today, and where in the repository it is. Its counterpart is `001-remaining.md`, which is what it has not; between them they are the whole answer to "where is this".

This document is descriptive. What the tools are for is defined in `../tools/`, why they are built this way in `../development/`, and neither is repeated here.

## Where the code is

- `src/utils/` — the generic BAML, namespace `root.common`: the `Shell` and `Files` ports, the host adapter for commands, their recording doubles, their implementations over `baml.sys` and `baml.fs`, and helpers for text, paths and YAML.
- `src/installer/` — `oparch-installer`, with its Rust host under `src/installer/host/`.
- `src/return-message-render/` — `oparch-return-message-render`. No host: `baml pack` makes it an executable of its own. It owns namespace `root.return_message`, and with it the template package format, the values format and the theme format, which the installer links from here because it asks for what a package declares, validates the same values in its own configuration file, and reads the theme to know how many languages it may offer.
- `src/dotfiles-sync/` — `oparch-dotfiles-sync`. No host either, and packed the same way.
- `tests/e2e/run.sh` — the end-to-end harness, with the configuration file and the dotfiles package it hands the guest.

The layout and the reason for it are `../development/002-repository-layout.md`.

Tests, counted on 2026-08-13: 270 in `src/installer`, 131 in `src/return-message-render`, 83 in `src/dotfiles-sync`, 40 in `src/utils`. Counts move with the work, so treat them as of that date rather than as a fact about the suite. Every suite runs with `baml test` and needs no host, no bridge, no ImageMagick and no privileges. The counts overlap: a suite also runs the tests of every namespace linked into it.

## The installer

**Both ways in.** The terminal interface asks nine screens with back navigation, per-answer validation and a note explaining each question, the last of them a summary; `--config` takes the same inputs from a YAML file and reports as plain lines without taking over the terminal. Formats: `../tools/oparch-installer/001-config-file-format.md`.

**The keymap first.** It is the first screen, and `loadkeys` applies it as it is answered, so everything typed afterwards is typed with it — including the two masked answers, the shared secret and the passphrase of the secret store.

**Eleven phases**, orchestrated in order and stopping at the first failure: `prepare_layout`, `bootstrap_base_system`, `configure_localization`, `configure_identity`, `configure_users`, `configure_network`, `configure_swap`, `configure_return_message`, `configure_initramfs`, `configure_bootloader`, `configure_dotfiles`. Nine of them always run; the return message and the dotfiles are present only when the installation was given what they act on, so the list never shows a step that will not happen. Every command's exit status is checked, and a failed file operation is reported by the host and noticed by the orchestrator.

**The template package and the theme.** Manifest parsing with format-version checking, message bodies with `{{field}}` references and `[[optional region]]` removal, and loading either from a local directory or from a URL as a `tar` whose entries are listed and refused before extraction if any would land outside the destination — the same path for both, since a theme is delivered like a package. The return-message screen asks for a package, asks for a theme, then asks the fields the package declares and offers the numbers of languages the theme lays out. Both are read and checked, with the values, before the disk is touched. Formats: `../tools/oparch-return-message-render/001-template-package-format.md`, `../tools/oparch-return-message-render/002-values-format.md` and `../tools/oparch-return-message-render/003-theme-format.md`; the decision behind the theme is `../tools/oparch-return-message-render/004-themes.md`.

**The pre-boot message phase.** It downloads the logo, asking the operator what to do when the download fails; writes the values into the target as `/etc/opinionatedarch/return-message.yaml`, composed by the same namespace that parses that format so the two cannot disagree; installs the project's Plymouth theme; runs `oparch-return-message-render` against the file it just wrote, with the theme in the target as its output; and makes that theme the default. It runs before the initramfs is built, and does nothing at all when no return message was asked for.

**The bootloader.** GRUB on the EFI partition, and the menu `../decisions/007-grub-boot-policy.md` designs, kept in `assets/grub/grub.cfg` and installed exactly as it is — `grub-mkconfig` is not used. What differs by machine is written beside it as `/boot/grub/oparch.cfg`, which the menu's first line reads: the container's UUID, the microcode image, and whether the splash is asked for. The recovery entry keeps its place in the order and says the recovery system is not installed, rather than starting something that is not there.

**The dotfiles phase.** It copies the staged package into `/dotfiles`, leaves that tree as `../decisions/013-dotfiles-policy.md` requires — the modes, the default ACL, and `/dotfiles` named in git's system `safe.directory` — and then enters the target and runs `oparch-dotfiles-sync` there. The package is judged at the form rather than here: the installer runs the packed tool with `--dry-run` against what it staged, so a package that does not hold what its map declares is refused while there is still someone to ask. A map that declares secrets is given them as one encrypted archive, opened through the host's `Secrets` port into the live system's memory and copied into the target with the owner and modes the map format requires. The reasoning is `../plans/000-dotfiles-integration.md`.

## The tools

**`oparch-return-message-render`.** Composes the images with ImageMagick and installs them into the Plymouth theme. It has no host: nothing in it needs a terminal or a command's output while that command still runs, so `baml pack` produces the executable directly. The text is drawn through Pango with markup on: everything coming from a package or an operator is escaped, and the only tags in what is drawn are the ones the tool writes itself. That is what lets a theme style a value by its `kind` and put an icon in front of it, while a package can still carry `<` or `&` and have them drawn. A script the chosen family does not cover renders through fontconfig's fallback, and a font a theme carries is found because the drawing commands are pointed at the theme's directory.

**`oparch-dotfiles-sync`.** Parses a map, resolves its includes, expands the rules whose selectors match the machine, and builds the plan before applying any of it. It can be told which machine to plan for — `--hostname` and a repeatable `--user` — which is what lets the installer judge a package for a machine that does not exist yet; given neither, it reads the machine it is running on. `--dry-run` builds the plan and applies nothing, and `--list-secrets` prints what the plan requires from the store, one path per line, so a caller learns whether an archive is needed at all without an exit code standing in for a list.

**The splash.** The theme under `assets/plymouth/opinionatedarch/` was rewritten for this design: a `.plymouth` file and one script body that draws no text and only places the images. The renderer writes the script the splash runs — seven numeric literals taken from the theme's `screen` values, then that body, read from the project's assets so a re-run cannot stack a second prelude — and copies the theme's background image beside the others when it has one.

## What has been seen, and how

**It boots.** On 2026-08-11 the harness installed from a configuration file and then started the disk it had made: the firmware found `\EFI\OpinionatedArch\grubx64.efi`, GRUB started the kernel the project's menu names, the initramfs asked for the passphrase, and the secret the installation was given opened the container and reached a login on the hostname that was configured. That was the harness before the dotfiles step was given to it; it has not been run since, which `001-remaining.md` carries as work.

**The splash was seen by hand, not by the harness.** The same day, on VMware and with a display: the machine booted to the return message screen, and Escape moved between it and the text unlock prompt and back. The harness runs its guest with `-nographic`, so Plymouth has no display there and falls back to the text prompt, and it therefore never draws the composed message and never runs the script the renderer writes. That is a limit of the harness, not of the thing it is testing, and `../development/006-end-to-end-testing.md` records it as one.

**The recording doubles remain what they always were.** They assert which commands would run, not that they work. What answers that is the harness, and only for the run it makes.

## Open

- How the message *reads* at the resolutions these machines boot at. The project's theme composes at 3840 px wide and the splash scales the images to the `fit` its `screen` section declares; that it appears is known, that it is comfortable to read on a given panel is not, and `../decisions/006-preboot-ownership-message.md` asks for that to be checked on the real ones.
- `install_mode: keep-homes` is refused by the disk phase. `001-remaining.md` carries what implementing it needs.
- The installer presumes it runs from the Arch live environment and does not check for the tools it calls. That is deliberate, and `../development/006-end-to-end-testing.md` argues it: do not add environment checks to make it runnable elsewhere; give it the environment instead.
