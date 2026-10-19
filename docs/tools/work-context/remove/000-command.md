# oparch-work-context-remove

## Description

`oparch-work-context-remove` removes a work context: its account, its home subvolume, and the mount and `fstab` entry that went with it. The `--preserve-home <target>` mode copies the removed context's data to `/home/<target>/other-contexts-home-data/<removed>` before removal.

Before anything is done, it refuses with an error:

- a context that is not a work context of the machine, a member of `work-contexts`, and a target of `--preserve-home` that is not one;
- the last work context of the machine;
- a target of `--preserve-home` that is the context being removed.

It works in this order, and stops at the first step that fails, leaving what was done before that step done:

1. With `--preserve-home <target>`, the copy: the whole of `/home/<removed>`, hidden files included, copied with its modes, links and timestamps into `/home/<target>/other-contexts-home-data/<removed>`. When that path is already taken, the copy goes to `<removed>-0` beside it, and when that is taken too, to `<removed>-1`, and so on, the first of them that is free. Everything under the copy is owned by `<target>:<target>`, and so is `/home/<target>/other-contexts-home-data` when the copy is what creates it. The tool prints the path of the copy.
2. The mount of `/home/<removed>`.
3. The account, and the group named after it.
4. The `fstab` entry of that mount, with the comment line `genfstab` writes above it and the blank line below it.
5. The directory `/home/<removed>` the home was mounted on.
6. The subvolume `home/@<removed>`. The top level of the Btrfs filesystem is mounted on a temporary directory while the subvolume is deleted, and unmounted and that directory removed afterwards.
7. The snapshot scope of the context, unless `--preserve-snapshots` is given: every snapshot of its home, each removed as [oparch-snapshot-remove](../../snapshot/remove/000-command.md) removes one, under the lock [Snapshot Storage Lock](../../snapshot/create/003-storage-lock.md) specifies and with its label, and then `/snapshots/home/<removed>/automatic`, `/snapshots/home/<removed>/manual` and `/snapshots/home/<removed>`.

It runs as root. Run by any other user, it refuses with an error before doing anything else. Beyond the path of a copy, it prints nothing.

## Why is needed

Removing it by hand can leave stale `fstab` entries, mounted paths, or orphaned subvolumes. A dedicated removal tool keeps the operation deterministic, and keeps data only through an explicit, repeatable path rather than by whatever the operator remembered to copy.

## Requirements

What has to be installed where this runs, which is the machine the work context is removed from — this tool is entered rather than aimed, as [Acting on Another System](../../../development/004-acting-on-another-system.md) decides.

It runs as root, because it removes an account, a mount, subvolumes and snapshots, and writes `/etc/fstab` and under `/snapshots`.

- **`shadow`**, for `userdel`.
- **`glibc`**, for `getent`: the work contexts are read from the `work-contexts` group.
- **`util-linux`**, for `mount`, `umount` and `findmnt`, and for `flock`, which holds the snapshot storage lock.
- **`btrfs-progs`**, for `btrfs`: the home and its snapshots are deleted as the subvolumes they are.
- **`coreutils`**, for `id`, `cp`, `chown`, `mktemp` and `rmdir`.

Every one of these is on an installed system, so there is nothing to add before a run.

There is no BAML runtime library in this list: this tool has no host, so `baml pack` makes it a standalone binary — the distinction is [Host Bridge](../../../development/001-host-bridge.md).

## Input parameters

- `<name>`: Mandatory. Work context to remove.
- `--preserve-home <target>`: Optional. Copy the removed context's home data under the home of the named work context before removal.
- `--preserve-snapshots`: Optional. Keep the removed context's snapshot data instead of removing its snapshot scope.
