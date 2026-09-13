# oparch-snapshot-automatic-create

## Description

`oparch-snapshot-automatic-create` creates an automatic snapshot of one scope, under `/snapshots/system/automatic` for the system and under `/snapshots/home/<work-context>/automatic` for the home of a work context. In the same run it deletes the automatic snapshots of that scope that the retention policy of [Snapshots](../../decisions/004-snapshots.md) no longer keeps.

A system snapshot takes the boot artifacts of that moment with it, as [Snapshots](../../decisions/004-snapshots.md) requires, and a set of boot artifacts is deleted with the last snapshot that points at it.

It is run at each moment [Snapshots](../../decisions/004-snapshots.md) takes an automatic snapshot.

## Why is needed

Automatic snapshots are taken with nobody there to take them, and they stay bounded only if something deletes the old ones. Taking and purging in one run makes the retention a consequence of taking: a scope never holds more than the policy keeps, and there is no second schedule to keep in step with the first.

## Input parameters

- `<scope>`: Mandatory. Snapshot scope. Accepted values: `system`, `home`.
- `<name>`: Mandatory for `home` scope. Work context whose home subvolume is snapshotted.
