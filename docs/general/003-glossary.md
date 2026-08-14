# Glossary

Terms used across the OpinionatedArch documentation.

## Accounts

- **Work context** — one area of the operator's activity, such as personal use or a specific client. It is a user account, with its own name, home, session and data. Member of the `work-contexts` group.
- **User**, **account** — a Linux account, whatever it is for. Every work context is one; not every one is a work context, which is why the word is still needed.
- `**work-contexts**` — group marking the accounts that are work contexts.
- `**dotfiles**` — group granting access to shared configuration under `/dotfiles`. Separate from the one above, so that something which is not a work context can still read what is there.
- **Shared secret** — the single value chosen at install time, used both as the LUKS passphrase and as the password of every work context.

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

- `**/dotfiles**` — the shared source of configuration for every work context, outside every home directory.
- **Dotfiles map** — the declarative `.dfmap` file describing how shared configuration is applied. It cannot execute commands.
- **Selector** — a clause restricting an entry to given users or hosts.
- **Operation** — what an entry does with a source path: `link`, `copy`, or `render`.

## Tools

- **Oparch tool** — a command for a recurring system operation, named `oparch-{entity}-{action}`.
- **Command-line tool** — owns the behavior and takes explicit parameters. Scriptable.
- **Interactive tool** — browses, filters, confirms, and collects input, then calls the matching command-line tool. Performs no system change itself.

## End-to-end testing

- **Harness** — the apparatus around what is being tested: it puts the real system into a state where it can run, starts it, feeds it its inputs, watches what comes back and decides whether the run passed. It is not the thing under test and it is not the assertions; it is what makes running them possible at all. Here it is `tests/e2e/run.sh`, and what it tests is the installer and the system the installer leaves behind. The word is the one used for a wiring harness — the thing that connects and drives — and not for anything to do with the tools this project is written with. Described in `../development/006-end-to-end-testing.md`.
