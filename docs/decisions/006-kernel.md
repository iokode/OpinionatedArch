# Kernel

## Context

Arch's repositories carry several kernels — `linux`, `linux-lts`, `linux-zen`, `linux-hardened` — and a machine can have more than one of them installed at once.

## Decision

An installation puts one kernel on the machine, `linux`, and no variant beside it.

Replacing it afterwards is the operator's; what this decision fixes is what an installation leaves.

## Why

- One kernel is installed because each one added is another set of headers to keep, another build of every external and DKMS module, and another way for an update to fail; a variant kept as a spare is paid for on every update and booted on almost none.
- `linux` is the one because it is Arch's own kernel, which is what everything in the repositories is built against.
- A second kernel is not kept as the way back from a bad update, because the machine already has one: [Snapshots](004-snapshots.md) copies the boot artifacts of each system snapshot and puts them back when it is restored, so what comes back is the kernel that was running, and [Disk Layout](001-disk-layout.md) gives recovery a partition of its own to do that from.

## Considerations

- The boot menu is a static `grub.cfg` with one entry for the installed system, as [Bootloader](008-bootloader.md) decides, so a kernel installed later is not offered by it.
