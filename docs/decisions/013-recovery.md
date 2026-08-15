# Recovery

**Work in progress. Nothing here is decided yet.**

This document will own what recovery is in this system, which paths there are and what each one is for, and what the recovery system has to be able to do.

That is spread today, and in no document is it the subject: [Disk Layout](001-disk-layout.md) gives it a partition of its own, outside the encrypted container, [Bootloader](009-bootloader.md) gives it its entry and decides that a snapshot is restored rather than booted, [Snapshots](004-snapshots.md) describes the severe path through it, and [Kernel](007-kernel.md) expects a bad kernel to be answered through it. Two more defer an obligation to a document that did not exist: [Encryption](002-encryption.md) leaves the LUKS header backup and its workflow to be written down later, and [Work Contexts and Accounts](000-work-contexts-and-accounts.md) requires root recovery procedures to be documented.

The recovery system itself is not built. [Remaining](../state/001-remaining.md) carries it as pending work, so this document decides what recovery must be able to do rather than describing what it does.

One option to weigh when it is written: an unlock file for the container, written during installation onto a medium the operator mounts, and kept on that removable medium rather than on the machine. The recovery system starts without the passphrase, so from there the file would open the container and the passphrase could be changed — which is the only way back from forgetting it that this design can have. What it costs is a second thing that opens the disk, no safer than wherever it ends up living, and an installer that has to be able to write it.
