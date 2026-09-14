# oparch-work-context-remove

## Description

`oparch-work-context-remove` removes a work context: its account, its home subvolume, and the mount and `fstab` entry that went with it. The `--preserve-home <target>` mode copies the removed context's data to `/home/<target>/other-contexts-home-data/<removed>` before removal.

## Why is needed

Removing it by hand can leave stale `fstab` entries, mounted paths, or orphaned subvolumes. A dedicated removal tool keeps the operation deterministic, and keeps data only through an explicit, repeatable path rather than by whatever the operator remembered to copy.

## Input parameters

- `<name>`: Mandatory. Work context to remove.
- `--preserve-home <target>`: Optional. Copy the removed context's home data under the home of the named work context before removal.
- `--preserve-snapshots`: Optional. Keep the removed context's snapshot data instead of removing its snapshot scope.
