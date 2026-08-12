# Operating Model

OpinionatedArch is single-person and multi-account. Login accounts separate work contexts for the same person, and shared configuration is centralized outside every home directory so all login users consume the same source.

This document describes the model as a whole. The normative rules live in the decision documents linked from each section.

## Accounts and Work Contexts

Two account types exist:

- **Login users** are interactive accounts, one per work context.
- **Logical users** are non-login accounts used to run restricted background processes.

Two explicit groups mark what an account is allowed to do: `login-users` for interactive login, and `dotfiles` for access to shared configuration. The two are separate because a background service can need shared configuration without being an interactive account.

Authentication is unified. One secret, chosen at install time, unlocks the disk and serves as the password for every login user.

See [User Model and Account Types](../decisions/000-user-model-and-account-types.md).

## Shared Configuration

Active shared configuration lives at `/dotfiles`, outside every login user's home directory. A declarative map file states how that configuration reaches each account, and `oparch-dotfiles-sync` applies it.

Because the map is evaluated per user and per host, one source can produce different results per work context and per machine without duplicating the source.

See [Dotfiles Map Format](../tools/oparch-dotfiles-sync/001-map-format.md).

## Storage

The system is installed on the whole disk with a deterministic layout: an EFI system partition and one LUKS2 container holding a single Btrfs filesystem.

See [Disk Layout](../decisions/001-disk-layout.md).

## Encryption

Encryption is mandatory and cannot be disabled from the installer. The Btrfs filesystem always sits inside a LUKS2 container, and the EFI partition stays unencrypted so firmware can read boot artifacts before the root filesystem is decrypted.

See [Encryption Strategy](../decisions/005-encryption-strategy.md).

## Snapshots and Recovery

Snapshots are taken automatically at boot start, on every package install or update transaction, and at login start for the user logging in. Manual snapshots can be taken on request and are never purged automatically.

Recovery is restore-based. Snapshots are not boot entries in GRUB; a damaged system is repaired by booting recovery, entering a chroot, and restoring a snapshot.

Because `/boot` sits on the unencrypted EFI partition and outside Btrfs, restoring a system snapshot does not roll back the kernel or initramfs.

See [Snapshot Strategy](../decisions/004-snapshot-strategy.md) and [GRUB Boot Policy](../decisions/007-grub-boot-policy.md).

## Pre-Boot Ownership Message

The disk-unlock screen can carry an ownership-and-return message, optionally with a logo, in as many languages as its theme lays out. It is the one part of the system that is not English-only, because it addresses whoever finds a lost machine.

See [Pre-Boot Ownership Message](../decisions/006-preboot-ownership-message.md).

## System Baseline

- The kernel is `linux`, and it is the only kernel installed. See [Kernel Strategy](../decisions/003-kernel-strategy.md).
- The system language is English, fixed at install time. See [Localization and Time Policy](../decisions/010-localization-and-time-policy.md).
- The network stack is `NetworkManager` with `systemd-resolved`. See [Network Stack Policy](../decisions/009-network-stack-policy.md).

## Tooling

Recurring operations are performed by `oparch-` commands. Command-line tools own the behavior and take explicit parameters; interactive tools only browse, filter, confirm, and collect input before calling them.

See [Oparch Tools](../decisions/012-oparch-tools.md) and the [tool documents](../tools/).
