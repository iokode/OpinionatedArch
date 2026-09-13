# oparch-snapshot-remove

## Description

`oparch-snapshot-remove` removes one snapshot, of either scope, automatic or manual. Removing a system snapshot also removes the set of boot artifacts it points at when no other snapshot points at that set.

## Why is needed

Manual snapshots are never purged automatically, so the ones whose justification no longer holds are removed by hand, as [Snapshots](../../decisions/004-snapshots.md) requires. A system snapshot is more than its subvolume: deleting the subvolume alone leaves its entry in the table that pairs it with its boot artifacts, and a set of them that may belong to nothing. One tool removes the whole of it.

## Input parameters

- `<snapshot>`: Mandatory. Path of the snapshot to remove, as `oparch-snapshot-list` prints it.
