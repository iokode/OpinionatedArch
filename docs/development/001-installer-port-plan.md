# Installer Port Plan

The installer is being rewritten in BAML, replacing the earlier Bash and C# implementations kept under `src/` and `installer/` for reference. This document records what is done, what is left, and the order the remaining work has to happen in. It is a plan, so it is expected to shrink and eventually be deleted.

## Where the code is

- `baml/utils/` — the generic BAML, namespace `root.common`: the `Shell` and `Files` ports, their host adapters, their recording doubles, their implementations over `baml.sys` and `baml.fs`, and helpers for text, paths and YAML.
- `baml/installer/` — the installer itself, with its Rust host under `baml/installer/host/`.
- `baml/return-message-render/` — the renderer. No host: `baml pack` makes it an executable of its own. It owns namespace `root.return_message`, and with it the template package format, the values format and the theme format, which the installer links from here because it asks for what a package declares, validates the same values in its own configuration file, and reads the theme to know how many languages it may offer.
- Layout and the reason for it: `../decisions/016-baml-repository-layout.md`.

Tests, counted on 2026-08-11: 232 in `baml/installer`, 127 in `baml/return-message-render`, 36 in `baml/utils`. Counts move with the work, so treat them as of that date rather than as a fact about the suite. Every suite runs with `baml test` and needs no host, no bridge, no ImageMagick and no privileges. The counts overlap: a suite also runs the tests of every namespace linked into it.

## Done

**Both ways in.** The terminal interface asks eight screens with back navigation, per-answer validation and a note explaining each question; `--config` takes the same inputs from a YAML file and reports as plain lines without taking over the terminal. Formats: `../tools/oparch-installer/001-config-file-format.md`.

**The template package and the theme.** Manifest parsing with format-version checking, message bodies with `{{field}}` references and `[[optional region]]` removal, and loading either from a local directory or from a URL as a `tar` whose entries are listed and refused before extraction if any would land outside the destination — the same path for both, since a theme is delivered like a package. The return-message screen asks for a package, asks for a theme, then asks the fields the package declares and offers the numbers of languages the theme lays out. Both are read and checked, with the values, before the disk is touched. Formats: `../tools/oparch-return-message-render/001-template-package-format.md`, `002-values-format.md` and `003-theme-format.md`; the decision behind the theme is `../decisions/017-return-message-themes.md`.

**Ten of ten phases**, orchestrated in order and stopping at the first failure: `prepare_layout`, `bootstrap_base_system`, `configure_localization`, `configure_identity`, `configure_users`, `configure_network`, `configure_swap`, `configure_return_message`, `configure_initramfs`, `configure_bootloader`. Every command's exit status is checked, and a failed file operation is reported by the host and noticed by the orchestrator.

**The pre-boot message phase.** It downloads the logo, asking the operator what to do when the download fails; writes the values into the target as `/etc/opinionatedarch/return-message.yaml`, composed by the same namespace that parses that format so the two cannot disagree; installs the project's Plymouth theme; runs `oparch-return-message-render` against the file it just wrote, with the theme in the target as its output; and makes that theme the default. It runs before the initramfs is built, and does nothing at all when no return message was asked for.

**`oparch-return-message-render`.** Composes the images with ImageMagick and installs them into the Plymouth theme. It has no host: nothing in it needs a terminal or a command's output while that command still runs, so `baml pack` produces the executable directly. The text is drawn through Pango with markup on: everything coming from a package or an operator is escaped, and the only tags in what is drawn are the ones the tool writes itself. That is what lets a theme style a value by its `kind` and put an icon in front of it, while a package can still carry `<` or `&` and have them drawn. A script the chosen family does not cover renders through fontconfig's fallback, and a font a theme carries is found because the drawing commands are pointed at the theme's directory.

**The splash.** The theme under `assets/plymouth/opinionatedarch/` was rewritten for this design: a `.plymouth` file and one script body that draws no text and only places the images. The fragments the earlier implementation concatenated, and the font and box images it drew text with, are deleted. The renderer writes the script the splash runs — seven numeric literals taken from the theme's `screen` values, then that body, read from the project's assets so a re-run cannot stack a second prelude — and copies the theme's background image beside the others when it has one.

**The bootloader.** GRUB on the EFI partition, and the menu `../decisions/008-grub-boot-policy.md` designs, kept in `assets/grub/grub.cfg` and installed exactly as it is — `grub-mkconfig` is not used. What differs by machine is written beside it as `/boot/grub/oparch.cfg`, which the menu's first line reads: the container's UUID, the microcode image, and whether the splash is asked for. The recovery entry keeps its place in the order and says the recovery system is not installed, rather than starting something that is not there.

**The end-to-end harness**, `test/e2e/run.sh`, described in `000-end-to-end-testing.md`. It boots the official Arch ISO under QEMU, drives the serial console, installs from a configuration file, then boots the disk it just built and answers the passphrase. It builds what it tests, because the host embeds the BAML program at compile time and a stale binary answers a question nobody asked.

## Left to do, in order

1. **The ISO.** Built with `archiso`, carrying the tools, the assets and its packages in its cache. Last, because everything it would carry now works. Recorded in `../remaining.md`.

## Open

- The splash works, and the harness cannot see it. On 2026-08-11 an installation on VMware, with a display, booted to the return message screen, and pressing Escape moved between it and the text unlock prompt and back. The harness runs its guest with `-nographic`, so Plymouth has no display there and falls back to text: it never draws the splash and never runs the script the renderer writes. That is a limit of the harness, not of the thing it is testing.
- How the message *reads* at the resolutions these machines boot at is a separate question, and it is open. The project's theme composes at 3840 px wide and the splash scales the images to the `fit` its `screen` section declares; that it appears is known, that it is comfortable to read on a given panel is not, and `../decisions/007-preboot-ownership-message.md` asks for that to be checked on the real ones.
- `install_mode: keep-homes` is refused by the disk phase, as the earlier implementation also did.
- What an installed system would need in order to rebuild its message, and what ImageMagick and the fonts need on the ISO and on the target, are recorded in `../remaining.md` and not repeated here.
- `src/` and `installer/` are deleted once this reaches parity.

## Working notes

It boots. On 2026-08-11 the harness installed from a configuration file and then started the disk it had made: the firmware found `\EFI\OpinionatedArch\grubx64.efi`, GRUB started the kernel the project's menu names, the initramfs asked for the passphrase, and the secret the installation was given opened the container and reached a login on the hostname that was configured.

What that run does not cover is the splash: with `-nographic` there is no display for one, so what it saw was the text fallback `007` requires rather than the composed images. The splash itself was seen the same day, on VMware, by hand. The recording doubles remain what they always were — they assert which commands would run, not that they work.

The installer presumes it runs from the Arch live environment and does not check for the tools it calls. Do not add environment checks to make it runnable elsewhere; give it the environment instead.
