# Installer Port Plan

The installer is being rewritten in BAML, replacing the earlier Bash and C# implementations kept under `src/` and `installer/` for reference. This document records what is done, what is left, and the order the remaining work has to happen in. It is a plan, so it is expected to shrink and eventually be deleted.

## Where the code is

- `baml/utils/` — shared BAML, namespace `root.common`: the `Shell` and `Files` ports with their host adapters and recording doubles, text helpers.
- `baml/installer/` — the installer itself, with its Rust host under `baml/installer/host/`.
- Layout and the reason for it: `../decisions/016-baml-repository-layout.md`.

Tests: 122 in `baml/installer`, 13 in `baml/utils`. Both suites run with `baml test` and need no host, no bridge and no privileges.

## Done

**Both ways in.** The terminal interface asks ten screens with back navigation and per-answer validation; `--config` takes the same inputs from a YAML file and reports as plain lines without taking over the terminal. Formats: `../tools/oparch-installer/001-config-file-format.md`.

**The template package.** Manifest parsing with format-version checking, message bodies with `{{field}}` references and `[[optional region]]` removal, loading from a local directory, and fetching from a URL as a `tar` whose entries are listed and refused before extraction if any would land outside the destination. The return-message screen asks the fields the package declares. Formats: `../tools/oparch-return-message-render/001-template-package-format.md` and `002-values-format.md`.

**Seven of ten phases**, orchestrated in order and stopping at the first failure: `prepare_layout`, `bootstrap_base_system`, `configure_localization`, `configure_identity`, `configure_users`, `configure_network`, `configure_swap`. Every command's exit status is checked, and a failed file operation is reported by the host and noticed by the orchestrator.

## Left to do, in order

1. **`oparch-return-message-render`.** A new BAML project with its own host, composing three images with ImageMagick: the message, the English passphrase prompt, and one mask glyph. Documented in `../tools/oparch-return-message-render/000-command.md`. Blocks the phase below.
2. **Pre-boot message phase.** Runs the renderer, installs the theme, writes `/etc/opinionatedarch/return-message.yaml` so the message can be rebuilt later. The logo download, which the earlier implementation had and this one does not yet, belongs here.
3. **Initramfs phase.** The `HOOKS` line and `mkinitcpio -P`. Unblocked: the hooks are now the base list plus `plymouth`, with nothing project-specific, since the splash draws no text.
4. **End-to-end harness.** `../development/000-end-to-end-testing.md`. Needs `qemu`, `edk2-ovmf` and an Arch ISO.
5. **Bootloader phase.** Deliberately last: `../decisions/008-grub-boot-policy.md` requires a static `grub.cfg` that does not exist yet, and writing the one path whose failure means the machine does not boot should happen where it can be booted and seen to fail.

## Open

- ImageMagick has to reach both the ISO and the installed system; recorded in `../remaining.md`.
- `install_mode: keep-homes` is refused by the disk phase, as the earlier implementation also did.
- `src/` and `installer/` are deleted once this reaches parity.

## Working notes

Nothing here is tested against a real disk. The recording doubles assert which commands would run and what files would be written; they cannot assert that the result boots. That is what step 4 exists for, and until it runs "done" means "asserted", not "verified".

The installer presumes it runs from the Arch live environment and does not check for the tools it calls. Do not add environment checks to make it runnable elsewhere; give it the environment instead.
