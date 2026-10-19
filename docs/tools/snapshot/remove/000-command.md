# oparch-snapshot-remove

## Description

`oparch-snapshot-remove` removes one snapshot, of either scope, automatic or manual.

Removing a system snapshot also removes its line from the table [Boot Artifacts Table Format](../create/002-boot-table-format.md) specifies, and then deletes every set of boot artifacts that no line points at. Removing a manual snapshot also removes its justification from the labels file [Snapshot Labels File Format](../create/001-labels-file-format.md) defines.

It does all of it while holding the lock [Snapshot Storage Lock](../create/003-storage-lock.md) specifies, and waits for the lock when another tool holds it. The subvolume is deleted first, so a snapshot that cannot be deleted keeps its line and its label.

A path that is not the path of a snapshot under `/snapshots` is refused before anything is done. When the snapshot is removed, it prints nothing.

## Why is needed

Manual snapshots are never purged automatically, so the ones whose justification no longer holds are removed by hand, as [Snapshots](../../../decisions/004-snapshots.md) requires. A system snapshot is more than its subvolume: deleting the subvolume alone leaves its entry in the table that pairs it with its boot artifacts, and a set of them that may belong to nothing. One tool removes the whole of it.

## Requirements

What has to be installed where this runs, which is the machine whose snapshot is removed — this tool is entered rather than aimed, as [Acting on Another System](../../../development/004-acting-on-another-system.md) decides, so it removes from the `/snapshots` [Disk Layout](../../../decisions/001-disk-layout.md) mounts there.

It runs as root, because it deletes subvolumes and writes under `/snapshots`. Run by any other user, it refuses with an error before doing anything else.

- **`btrfs-progs`**, for `btrfs`: the snapshot is deleted as the subvolume it is.
- **`coreutils`**, for `id`, which tells whether it runs as root, and for `rm`, which deletes a set nothing points at.
- **`util-linux`**, for `flock`, which holds the lock.

`coreutils` and `util-linux` are part of `base`, and `btrfs-progs` is installed on every machine this project installs, so there is nothing to add before a run.

There is no BAML runtime library in this list: this tool has no host, so `baml pack` makes it a standalone binary — the distinction is [Host Bridge](../../../development/001-host-bridge.md).

## Input parameters

- `<snapshot>`: Mandatory. Path of the snapshot to remove, as `oparch-snapshot-list` prints it after the tab of the snapshot's line.
