# Documentation

This directory contains the OpinionatedArch documentation.

Every document belongs to exactly one document type. Each type has its own directory and its own section order. Every document is numbered inside its directory, and the number is part of the file name: `<number>-<name>.md`.

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

## Specification

Documents defining a normative format, syntax, or protocol.

Directory: `specs/`

Section order:

1. Context
2. Specification
3. Why
4. Considerations (optional)

The `Specification` section uses free `###` subsections.

- [Dotfiles Sync](specs/000-dotfiles-sync.md)

## Tool

Documents defining one command each. The file name is `<number>-<tool-name>.md`, where `<tool-name>` is the command name.

Directory: `tools/`

Section order:

1. Description
2. Why is needed
3. Input parameters (when applicable)
4. Interactive usage (when applicable)

- [oparch-user-create](tools/000-oparch-user-create.md)
- [oparch-user-remove](tools/001-oparch-user-remove.md)
- [oparch-snapshot-system-create](tools/002-oparch-snapshot-system-create.md)
- [oparch-snapshot-user-create](tools/003-oparch-snapshot-user-create.md)
- [oparch-snapshot-restore](tools/004-oparch-snapshot-restore.md)
- [oparch-password-rotate](tools/005-oparch-password-rotate.md)
- [oparch-password-rotate-interactive](tools/006-oparch-password-rotate-interactive.md)
- [oparch-dotfiles-sync](tools/007-oparch-dotfiles-sync.md)

## Critical Notes With Replies (Copy of Discussion)

Any document may end with this optional section, whatever its type.

It records the critiques an LLM raised against the document during discussion, each one followed by the reply it received. Keeping both together makes it possible to review later whether the direction taken was the right one, and where it was deliberately argued against.

Entries are a numbered list. Each entry states the critique on the first line and the reply on the second:

```text
1. Assistant critique: <the objection raised>
   Reply: <the answer given>
```
