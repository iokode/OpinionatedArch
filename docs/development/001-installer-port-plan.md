# Installer Port Plan

The installer is being rewritten in BAML, replacing the earlier Bash and C# implementations kept under `src/` and `installer/` for reference. This document records what is done, what is left, and the order the remaining work has to happen in. It is a plan, so it is expected to shrink and eventually be deleted.

## Where the code is

- `baml/utils/` — the generic BAML, namespace `root.common`: the `Shell` and `Files` ports, their host adapters, their recording doubles, their implementations over `baml.sys` and `baml.fs`, and helpers for text, paths and YAML.
- `baml/installer/` — the installer itself, with its Rust host under `baml/installer/host/`.
- `baml/return-message-render/` — the renderer. No host: `baml pack` makes it an executable of its own. It owns namespace `root.return_message`, and with it the template package format, the values format and the theme format, which the installer links from here because it asks for what a package declares, validates the same values in its own configuration file, and reads the theme to know how many languages it may offer.
- Layout and the reason for it: `../decisions/016-baml-repository-layout.md`.

Tests, counted on 2026-08-10: 186 in `baml/installer`, 123 in `baml/return-message-render`, 26 in `baml/utils`. The installer's number moves with the work in progress, so treat it as of that date rather than as a fact about the suite. Every suite runs with `baml test` and needs no host, no bridge, no ImageMagick and no privileges. The counts overlap: a suite also runs the tests of every namespace linked into it.

## Done

**Both ways in.** The terminal interface asks ten screens with back navigation and per-answer validation; `--config` takes the same inputs from a YAML file and reports as plain lines without taking over the terminal. Formats: `../tools/oparch-installer/001-config-file-format.md`.

**The template package and the theme.** Manifest parsing with format-version checking, message bodies with `{{field}}` references and `[[optional region]]` removal, and loading either from a local directory or from a URL as a `tar` whose entries are listed and refused before extraction if any would land outside the destination — the same path for both, since a theme is delivered like a package. The return-message screen asks for a package, asks for a theme, then asks the fields the package declares and offers the numbers of languages the theme lays out. Both are read and checked, with the values, before the disk is touched. Formats: `../tools/oparch-return-message-render/001-template-package-format.md`, `002-values-format.md` and `003-theme-format.md`; the decision behind the theme is `../decisions/017-return-message-themes.md`.

**Eight of ten phases**, orchestrated in order and stopping at the first failure: `prepare_layout`, `bootstrap_base_system`, `configure_localization`, `configure_identity`, `configure_users`, `configure_network`, `configure_swap`, `configure_return_message`. Every command's exit status is checked, and a failed file operation is reported by the host and noticed by the orchestrator.

**The pre-boot message phase.** It downloads the logo, asking the operator what to do when the download fails; writes the values into the target as `/etc/opinionatedarch/return-message.yaml`, composed by the same namespace that parses that format so the two cannot disagree; installs the project's Plymouth theme; runs `oparch-return-message-render` against the file it just wrote, with the theme in the target as its output; and makes that theme the default. It runs before the initramfs is built, and does nothing at all when no return message was asked for.

**`oparch-return-message-render`.** Composes the images with ImageMagick and installs them into the Plymouth theme. It has no host: nothing in it needs a terminal or a command's output while that command still runs, so `baml pack` produces the executable directly. The text is drawn through Pango with markup on: everything coming from a package or an operator is escaped, and the only tags in what is drawn are the ones the tool writes itself. That is what lets a theme style a value by its `kind` and put an icon in front of it, while a package can still carry `<` or `&` and have them drawn. A script the chosen family does not cover renders through fontconfig's fallback, and a font a theme carries is found because the drawing commands are pointed at the theme's directory.

**The splash.** The theme under `assets/plymouth/opinionatedarch/` was rewritten for this design: a `.plymouth` file and one script body that draws no text and only places the images. The fragments the earlier implementation concatenated, and the font and box images it drew text with, are deleted. The renderer writes the script the splash runs — seven numeric literals taken from the theme's `screen` values, then that body, read from the project's assets so a re-run cannot stack a second prelude — and copies the theme's background image beside the others when it has one.

## Left to do, in order

1. **Initramfs phase.** The `HOOKS` line and `mkinitcpio -P`. Unblocked: the hooks are now the base list plus `plymouth`, with nothing project-specific, since the splash draws no text.
2. **End-to-end harness.** `../development/000-end-to-end-testing.md`. Needs `qemu`, `edk2-ovmf` and an Arch ISO.
3. **Bootloader phase.** Deliberately last: `../decisions/008-grub-boot-policy.md` requires a static `grub.cfg` that does not exist yet, and writing the one path whose failure means the machine does not boot should happen where it can be booted and seen to fail.

## Open

- The Plymouth script has never run. Its arithmetic, the names it expects above it and the numbers it is handed are asserted as text by the renderer's tests, and read by nothing else until a machine boots it. Step 2 is the first time it executes.
- What the message looks like on a real panel is still unverified. The project's theme composes at 3840 px wide and the splash scales the images to the `fit` its `screen` section declares; only step 2 shows whether the result reads at the resolutions these machines actually boot at.
- `install_mode: keep-homes` is refused by the disk phase, as the earlier implementation also did.
- What an installed system would need in order to rebuild its message, and what ImageMagick and the fonts need on the ISO and on the target, are recorded in `../remaining.md` and not repeated here.
- `src/` and `installer/` are deleted once this reaches parity.

## Working notes

Nothing here is tested against a real disk, and nothing in this chain has ever booted — not the installer, not the theme it installs, not the script the renderer writes. The recording doubles assert which commands would run and what files would be written; they cannot assert that any of it boots. That is what step 2 exists for, and until it runs "done" means "asserted", not "verified".

The installer presumes it runs from the Arch live environment and does not check for the tools it calls. Do not add environment checks to make it runnable elsewhere; give it the environment instead.
