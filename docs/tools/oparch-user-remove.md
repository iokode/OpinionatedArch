# oparch-user-remove

## Description

`oparch-user-remove` removes a login user, including account removal, home-subvolume removal, and mount/fstab cleanup. The `--preserve-home <target-user>` mode copies the removed user's data to `/home/<target-user>/other-users-home-data/<removed-user>` before removal.

## Why is needed

Manual user removal can leave stale fstab entries, mounted paths, or orphaned subvolumes. A dedicated removal tool keeps the operation deterministic while preserving data only through an explicit, repeatable path.

## Input parameters

- `<username>`: Mandatory. Login user to remove.
- `--preserve-home <target-user>`: Optional. Copy the removed user's home data under the selected target user's home before removal.
- `--preserve-snapshots`: Optional. Preserve the removed user's snapshot data instead of removing the user snapshot scope.
