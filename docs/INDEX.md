# Index

Every document in this directory, by type. What the types are and what shape each document takes is [Document Types](README.md).

## General

- [What is OpinionatedArch](general/000-what-is-opinionatedarch.md)
- [Operating Model](general/001-operating-model.md)
- [Installation Overview](general/002-installation-overview.md)
- [Glossary](general/003-glossary.md)

## Decisions

- [Work Contexts and Accounts](decisions/000-work-contexts-and-accounts.md)
- [Disk Layout](decisions/001-disk-layout.md)
- [Encryption](decisions/002-encryption.md)
- [Swap](decisions/003-swap.md)
- [Snapshots](decisions/004-snapshots.md)
- [Localization and Time](decisions/005-localization-and-time.md)
- [System Identity](decisions/006-system-identity.md)
- [Kernel](decisions/007-kernel.md)
- [Boot Image Format](decisions/008-boot-image-format.md) — work in progress, nothing decided yet
- [Bootloader](decisions/009-bootloader.md)
- [Pre-Boot Ownership Message](decisions/010-preboot-ownership-message.md)
- [Return Message on an Installed System](decisions/011-return-message-on-an-installed-system.md) — work in progress, nothing decided yet
- [mkinitcpio Hooks](decisions/012-mkinitcpio-hooks.md)
- [Recovery](decisions/013-recovery.md) — work in progress, nothing decided yet
- [Package Baseline](decisions/014-package-baseline.md) — work in progress, nothing decided yet
- [AUR](decisions/015-aur.md) — work in progress, nothing decided yet
- [Service Baseline](decisions/016-service-baseline.md) — work in progress, nothing decided yet
- [Network Stack](decisions/017-network-stack.md)
- [Audio Stack](decisions/018-audio-stack.md) — work in progress, nothing decided yet
- [Security Baseline](decisions/019-security-baseline.md) — work in progress, nothing decided yet
- [Dotfiles](decisions/020-dotfiles.md)
- [Oparch Tools](decisions/021-oparch-tools.md)

## Tools

- [oparch-installer](tools/oparch-installer/000-command.md)
  - [Installer Configuration File Format](tools/oparch-installer/001-config-file-format.md)
  - [Inputs and Bootstrap Baseline](tools/oparch-installer/002-inputs-and-bootstrap-baseline.md)
  - [Input Sources](tools/oparch-installer/003-input-sources.md)
- [oparch-return-message-render](tools/oparch-return-message-render/000-command.md)
  - [Return Message Template Package Format](tools/oparch-return-message-render/001-template-package-format.md)
  - [Return Message Values Format](tools/oparch-return-message-render/002-values-format.md)
  - [Return Message Theme Format](tools/oparch-return-message-render/003-theme-format.md)
  - [Return Message Themes](tools/oparch-return-message-render/004-themes.md)
- [oparch-dotfiles-sync](tools/oparch-dotfiles-sync/000-command.md)
  - [Dotfiles Map Format](tools/oparch-dotfiles-sync/001-map-format.md)
  - [Secret Store Archive](tools/oparch-dotfiles-sync/002-secret-store-archive.md)
- [oparch-work-context-create](tools/oparch-work-context-create/000-command.md)
- [oparch-work-context-remove](tools/oparch-work-context-remove/000-command.md)
- [oparch-snapshot-system-create](tools/oparch-snapshot-system-create/000-command.md)
- [oparch-snapshot-work-context-create](tools/oparch-snapshot-work-context-create/000-command.md)
- [oparch-snapshot-restore](tools/oparch-snapshot-restore/000-command.md)
- [oparch-password-rotate](tools/oparch-password-rotate/000-command.md)
- [oparch-password-rotate-interactive](tools/oparch-password-rotate-interactive/000-command.md)

The first three are written. The rest are specified and not implemented, which `state/001-remaining.md` carries as the first work.

## Development

- [BAML as Implementation Language](development/000-baml-as-implementation-language.md)
- [Host Bridge](development/001-host-bridge.md)
- [Repository Layout](development/002-repository-layout.md)
- [Where a Command Runs](development/003-where-a-command-runs.md)
- [Acting on Another System](development/004-acting-on-another-system.md)
- [BAML Working Notes](development/005-baml-working-notes.md)
- [End-to-End Testing](development/006-end-to-end-testing.md)
- [Installation Checks](development/007-installation-checks.md)

## Plans

- [Dotfiles Integration](plans/000-dotfiles-integration.md)

## State

- [What Is Built](state/000-what-is-built.md)
- [Remaining](state/001-remaining.md)
