# Index

Every document in this directory, by type. What the types are and what shape each document takes is [Document Types](README.md).

## General

- [What is OpinionatedArch](general/000-what-is-opinionatedarch.md)
- [Operating Model](general/001-operating-model.md)
- [Installation Overview](general/002-installation-overview.md)

## Decisions

- [Work Contexts and Accounts](decisions/000-work-contexts-and-accounts.md)
- [Disk Layout](decisions/001-disk-layout.md)
- [Encryption](decisions/002-encryption.md)
- [Swap](decisions/003-swap.md)
- [Snapshots](decisions/004-snapshots.md)
- [Localization and Time](decisions/005-localization-and-time.md)
- [Kernel](decisions/006-kernel.md)
- [Boot Image Format](decisions/007-boot-image-format.md)
- [Bootloader](decisions/008-bootloader.md)
- [Pre-Boot Ownership Message](decisions/009-preboot-ownership-message.md)
- [mkinitcpio Hooks](decisions/010-mkinitcpio-hooks.md)
- [Recovery](decisions/011-recovery.md) — work in progress, nothing decided yet
- [Network Stack](decisions/012-network-stack.md)
- [Audio Stack](decisions/013-audio-stack.md) — work in progress, nothing decided yet
- [Dotfiles](decisions/014-dotfiles.md)
- [Oparch Tools](decisions/015-oparch-tools.md)
- [Package Repository](decisions/016-package-repository.md)
- [Installation Script](decisions/017-installation-script.md)
- [Installation ISO](decisions/018-installation-iso.md)
- [Signing Key](decisions/019-signing-key.md)

## Tools

- [oparch-installer](tools/installer/unattended/000-command.md)
  - [Installer Configuration File Format](tools/installer/unattended/001-config-file-format.md)
  - [Inputs and Bootstrap Baseline](tools/installer/unattended/002-inputs-and-bootstrap-baseline.md)
  - [Input Sources](tools/installer/unattended/003-input-sources.md)
- [oparch-installer-interactive](tools/installer/interactive/000-command.md)
- [oparch-return-message-render](tools/return-message/render/000-command.md)
  - [Return Message Template Package Format](tools/return-message/render/001-template-package-format.md)
  - [Return Message Values Format](tools/return-message/render/002-values-format.md)
  - [Return Message Theme Format](tools/return-message/render/003-theme-format.md)
  - [Return Message Themes](tools/return-message/render/004-themes.md)
- [oparch-dotfiles-sync](tools/dotfiles/sync/000-command.md)
  - [Dotfiles Map Format](tools/dotfiles/sync/001-map-format.md)
  - [Secret Store Archive](tools/dotfiles/sync/002-secret-store-archive.md)
- [oparch-work-context-create](tools/work-context/create/000-command.md)
- [oparch-work-context-remove](tools/work-context/remove/000-command.md)
- [oparch-work-context-list](tools/work-context/list/000-command.md)
- [oparch-work-context-interactive](tools/work-context/interactive/000-command.md)
- [oparch-snapshot-create](tools/snapshot/create/000-command.md)
  - [Snapshot Labels File Format](tools/snapshot/create/001-labels-file-format.md)
  - [Boot Artifacts Table Format](tools/snapshot/create/002-boot-table-format.md)
  - [Snapshot Storage Lock](tools/snapshot/create/003-storage-lock.md)
- [oparch-snapshot-list](tools/snapshot/list/000-command.md)
- [oparch-snapshot-remove](tools/snapshot/remove/000-command.md)
- [oparch-snapshot-restore](tools/snapshot/restore/000-command.md)
- [oparch-snapshot-interactive](tools/snapshot/interactive/000-command.md)
- [oparch-password-rotate](tools/password/rotate/000-command.md)
- [oparch-password-rotate-interactive](tools/password/rotate-interactive/000-command.md)

The first four, `oparch-work-context-create`, `oparch-work-context-list` and `oparch-snapshot-create` are written. The rest are specified and not implemented, which [Remaining](state/001-remaining.md) carries as the first work.

## Development

- [BAML as Implementation Language](development/000-baml-as-implementation-language.md)
- [Host Bridge](development/001-host-bridge.md)
- [Repository Layout](development/002-repository-layout.md)
- [Where a Command Runs](development/003-where-a-command-runs.md)
- [Acting on Another System](development/004-acting-on-another-system.md)
- [BAML Working Notes](development/005-baml-working-notes.md)
- [End-to-End Testing](development/006-end-to-end-testing.md)
- [Installation Checks](development/007-installation-checks.md)
- [Building and Publishing](development/008-building-and-publishing.md)
- [Trying a Working Tree](development/009-trying-a-working-tree.md)

## Plans

- [Dotfiles Integration](plans/000-dotfiles-integration.md)

## State

- [What Is Built](state/000-what-is-built.md)
- [Remaining](state/001-remaining.md)
