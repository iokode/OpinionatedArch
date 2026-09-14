# oparch-snapshot-list

## Description

`oparch-snapshot-list` lists snapshots, one path per line. The path is what identifies a snapshot to `oparch-snapshot-remove` and `oparch-snapshot-restore`, and it carries the scope, the work context and whether the snapshot is automatic or manual.

Given no parameter it lists every snapshot, and each parameter narrows the list to the snapshots that match it.

## Why is needed

Removing or restoring a snapshot starts from knowing which snapshots there are. A script has to be able to ask that of the machine, narrowed to the snapshots it is about, as an interface can.

## Input parameters

- `--scope <scope>`: Optional. Lists only the snapshots of that scope. Accepted values: `system`, `home`.
- `--work-context <name>`: Optional, with `home` scope only. Lists only the snapshots of that work context's home.
- `--since <date>`: Optional. Lists only the snapshots taken at that moment or later, given as an ISO 8601 date and time.
- `--until <date>`: Optional. Lists only the snapshots taken at that moment or earlier, given as an ISO 8601 date and time.
