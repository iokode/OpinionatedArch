# Documentation

This directory contains the OpinionatedArch documentation.

Every document belongs to exactly one document type. Each type has its own directory and defines the section order its documents follow. Every document is numbered inside its directory, and the number is part of the file name: `<number>-<name>.md`.

Implementation plans are not part of these documents. When a plan is needed, it is written as its own dedicated document.

## General

Documents describing what OpinionatedArch is and how it works.

Directory: `general/`

General documents have no fixed section order. They open with a summary paragraph and use free `##` sections.

- [What is OpinionatedArch](general/000-what-is-opinionatedarch.md)
- [Operating Model](general/001-operating-model.md)
- [Installation Overview](general/002-installation-overview.md)
- [Glossary](general/003-glossary.md)

## Decision

Documents defining one decision each.

Directory: `decisions/`

Section order:

1. Context
2. Decision
3. Why
4. Considerations (optional)

- [Installer Inputs and Bootstrap Baseline](decisions/000-installer-inputs-and-bootstrap-baseline.md)
- [User Model and Account Types](decisions/001-user-model-and-account-types.md)
- [Disk Layout](decisions/002-disk-layout.md)
- [Swap Strategy](decisions/003-swap-strategy.md)
- [Kernel Strategy](decisions/004-kernel-strategy.md)
- [Snapshot Strategy](decisions/005-snapshot-strategy.md)
- [Encryption Strategy](decisions/006-encryption-strategy.md)
- [Pre-Boot Ownership Message](decisions/007-preboot-ownership-message.md)
- [GRUB Boot Policy](decisions/008-grub-boot-policy.md)
- [mkinitcpio Hooks Policy](decisions/009-mkinitcpio-hooks-policy.md)
- [Network Stack Policy](decisions/010-network-stack-policy.md)
- [Localization and Time Policy](decisions/011-localization-and-time-policy.md)
- [System Identity Policy](decisions/012-system-identity-policy.md)
- [Oparch Tools](decisions/013-oparch-tools.md)
- [BAML as Implementation Language](decisions/014-baml-as-implementation-language.md)
- [Installer Host Bridge](decisions/015-installer-host-bridge.md)
- [BAML Repository Layout](decisions/016-baml-repository-layout.md)
- [Return Message Themes](decisions/017-return-message-themes.md)
- [Installer Input Sources](decisions/018-installer-input-sources.md)

## Tool

Documents defining one tool each. Every tool has its own directory, named after the command, and its documents are numbered inside it: `tools/<tool-name>/<number>-<name>.md`.

The first document of a tool is its command document, `000-command.md`, with this section order:

1. Description
2. Why is needed
3. Input parameters (when applicable)
4. Interactive usage (when applicable)

Any further document of a tool specifies part of what the tool defines — a format, a syntax, a protocol — with this section order:

1. Context
2. Specification
3. Why
4. Considerations (optional)

The `Specification` section uses free `###` subsections.

- [oparch-user-create](tools/oparch-user-create/000-command.md)
- [oparch-user-remove](tools/oparch-user-remove/000-command.md)
- [oparch-snapshot-system-create](tools/oparch-snapshot-system-create/000-command.md)
- [oparch-snapshot-user-create](tools/oparch-snapshot-user-create/000-command.md)
- [oparch-snapshot-restore](tools/oparch-snapshot-restore/000-command.md)
- [oparch-password-rotate](tools/oparch-password-rotate/000-command.md)
- [oparch-password-rotate-interactive](tools/oparch-password-rotate-interactive/000-command.md)
- [oparch-dotfiles-sync](tools/oparch-dotfiles-sync/000-command.md)
  - [Dotfiles Map Format](tools/oparch-dotfiles-sync/001-map-format.md)
- [oparch-return-message-render](tools/oparch-return-message-render/000-command.md)
  - [Return Message Template Package Format](tools/oparch-return-message-render/001-template-package-format.md)
  - [Return Message Values Format](tools/oparch-return-message-render/002-values-format.md)
  - [Return Message Theme Format](tools/oparch-return-message-render/003-theme-format.md)
- [oparch-installer](tools/oparch-installer/000-command.md)
  - [Installer Configuration File Format](tools/oparch-installer/001-config-file-format.md)

## Development

Documents describing how OpinionatedArch is built, tested and iterated on. They describe the project's own working environment, not the distribution it produces.

Directory: `development/`

Development documents have no fixed section order. They open with a summary paragraph and use free `##` sections.

- [End-to-End Testing](development/000-end-to-end-testing.md)
- [Installer Port Plan](development/001-installer-port-plan.md)
- [BAML Working Notes](development/002-baml-working-notes.md)

## Critical Notes With Replies (Copy of Discussion)

Any document may end with this optional section, whatever its type.

It records the critiques an LLM raised against the document during discussion, each one followed by the reply it received. Keeping both together makes it possible to review later whether the direction taken was the right one, and where it was deliberately argued against.

Entries are a numbered list. Each entry states the critique on the first line and the reply on the second:

```text
1. Assistant critique: <the objection raised>
   Reply: <the answer given>
```
