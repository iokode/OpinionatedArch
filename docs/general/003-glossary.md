# Glossary

Terms used across the OpinionatedArch documentation.

## Accounts

- **Work context** — one area of the operator's activity, such as personal use or a specific client. Each work context gets its own login user.
- **Login user** — an interactive account representing one work context. Member of the `login-users` group.
- **Logical user** — a non-login account used to run a restricted background process. Created by baseline policy, never prompted for.
- `**login-users**` — group marking accounts intended for interactive login.
- `**dotfiles**` — group granting access to shared configuration under `/dotfiles`.
- **Shared secret** — the single value chosen at install time, used both as the LUKS passphrase and as the password of every login user.

## Installation

- **Install mode** — `wipe-all` destroys all data on the selected disk; `keep-homes` reinstalls while preserving selected existing home subvolumes.
- **Clean-live baseline** — the assumption that the installer always starts from an unmodified Arch live environment (archiso).

## Boot

- **Pre-boot return message** — the optional ownership-and-return text shown on the disk-unlock screen, in one or more languages.
- **Return message theme** — a directory declaring what the rendered message looks like: typography, colours, panels, spacing and the arrangement of the languages. Its format is defined in `../tools/oparch-return-message-render/003-theme-format.md`.
- **Return message template package** — a directory holding a manifest and one message file per language, defining the pre-boot return message and the data it needs. Its format is defined in `../tools/oparch-return-message-render/001-template-package-format.md`.

## Snapshots

- **Automatic snapshot** — created without operator action: at boot start, on a package transaction, or at login start. Retained up to a fixed count, then purged.
- **Manual snapshot** — created on explicit request, carrying a human-readable justification in its name. Never purged automatically.
- **Restore-based recovery** — repairing the system by restoring a snapshot from a chroot, rather than booting a snapshot directly.

## Dotfiles

- `**/dotfiles**` — the shared source of configuration for all login users, outside every home directory.
- **Dotfiles map** — the declarative `.dfmap` file describing how shared configuration is applied. It cannot execute commands.
- **Selector** — a clause restricting an entry to given users or hosts.
- **Operation** — what an entry does with a source path: `link`, `copy`, or `render`.

## Tools

- **Oparch tool** — a command for a recurring system operation, named `oparch-{entity}-{action}`.
- **Command-line tool** — owns the behavior and takes explicit parameters. Scriptable.
- **Interactive tool** — browses, filters, confirms, and collects input, then calls the matching command-line tool. Performs no system change itself.

