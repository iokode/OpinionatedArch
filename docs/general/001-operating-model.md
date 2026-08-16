# Operating Model

This document describes the model from the operator's side: what the system is for the person who uses it, and not how any of it is built. The rules that bind are in the decision documents linked from each section.

## Work Contexts

A **work context** is one area of the operator's activity — personal use, a given client, a side project. It is a user account: it has a name, a home directory of its own, its own session and its own data.

Contexts are not people. They exist so that what belongs to one activity stays out of another — sessions, credentials, browser state, files — for a single person who would otherwise keep all of it in one account and separate it by hand.

Authentication is unified. One secret, chosen at install time, unlocks the disk and is the password of every work context.

See [Work Contexts and Accounts](../decisions/000-work-contexts-and-accounts.md).

## Shared Configuration across Work Contexts

The contexts are areas of one person's activity, so how that person works is one thing and not several. A change to it belongs to all of them at once: the same shell, the same editor, the same keybindings. Held per context, that configuration would have to be edited as many times as there are contexts, and what told them apart would end up being drift rather than intent.

So it is kept once, at `/dotfiles`, outside every home directory, and it reaches every context from there.

Shared is not identical. What one context needs, another may have to do without — a client's git identity, credentials that belong to one activity and to no other. What one machine needs, another does not — the monitors it drives, the battery indicator a desktop has no battery for.

See [Dotfiles](../decisions/014-dotfiles.md).

## Snapshots and Recovery

The system keeps automatic snapshots of itself, and of each work context separately: the system's when the machine starts and on every package transaction; a context's when it is logged into. The operator can also take one manually.

The machine carries a recovery mode that can be started instead of the installed system. A damaged system is repaired from there: by hand, or by restoring one of its snapshots.

A snapshot is restored, never started.

See [Snapshots](../decisions/004-snapshots.md) and [Recovery](../decisions/011-recovery.md).

## Encryption

Encryption is mandatory: it cannot be turned off at install time, and there is no mode without it. The machine starts by unlocking the disk.

See [Encryption](../decisions/002-encryption.md).

## Pre-Boot Ownership Message

Whoever finds a lost machine gets no further than the passphrase prompt: the disk is encrypted, and there is nothing else to reach. So that prompt is where the machine can carry an ownership-and-return message — who it belongs to, and how to reach them to give it back.

See [Pre-Boot Ownership Message](../decisions/009-preboot-ownership-message.md).

