# Recovery

**Work in progress. Nothing here is decided yet.**

This document will own what recovery is in this system, which paths there are and what each one is for, and what the recovery system has to be able to do.

That is spread today, and in no document is it the subject: `001-disk-layout.md` places `@recovery` as its own bootable root, `009-bootloader.md` gives it its entry and decides that a snapshot is restored rather than booted, `004-snapshots.md` describes the severe path through it, and `007-kernel.md` expects a bad kernel to be answered through it. Two more defer an obligation to a document that did not exist: `002-encryption.md` leaves the LUKS header backup and its workflow to be written down later, and `000-work-contexts-and-accounts.md` requires root recovery procedures to be documented.

The recovery system itself is not built. `../state/001-remaining.md` carries it as pending work, so this document decides what recovery must be able to do rather than describing what it does.
