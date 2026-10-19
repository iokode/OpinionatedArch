# oparch-snapshot-list

## Description

`oparch-snapshot-list` lists snapshots, one per line. A line is the name of the work context whose home the snapshot is of, or `system` for the system scope, a tab, and the path of the snapshot:

```text
system	/snapshots/system/manual/@1778764800
work	/snapshots/home/work/automatic/@1778761500
```

The path is what identifies a snapshot to `oparch-snapshot-remove` and `oparch-snapshot-restore`, and it carries the scope, the work context and whether the snapshot is automatic or manual.

Given no parameter it lists every snapshot, and each parameter narrows the list to the snapshots that match it. The snapshots are listed by the moment their names give, earliest first, and two taken in the same second by their paths. When no snapshot matches, it prints nothing.

## Why is needed

Removing or restoring a snapshot starts from knowing which snapshots there are. A script has to be able to ask that of the machine, narrowed to the snapshots it is about, as an interface can.

## Requirements

Nothing has to be installed where this runs beyond the tool itself: it runs no command, and reads the names of the directories under the `/snapshots` of the machine it runs on, as [Acting on Another System](../../../development/004-acting-on-another-system.md) decides. It reads nothing inside the snapshots and writes nothing, so it takes no lock and does not have to be run as root.

There is no BAML runtime library in this list: this tool has no host, so `baml pack` makes it a standalone binary — the distinction is [Host Bridge](../../../development/001-host-bridge.md).

## Input parameters

- `--scope <scope>`: Optional. Lists only the snapshots of that scope. Accepted values: `system`, `home`.
- `--work-context <name>`: Optional, with `home` scope only: given without `--scope home`, it is refused. Lists only the snapshots of that work context's home.
- `--since <date>`: Optional. Lists only the snapshots taken at that moment or later. The date and time are written `YYYY-MM-DDTHH:MM:SS`, as `2026-09-14T10:00:00`, and read as UTC; a value carrying `Z` or an offset, or written any other way, is refused.
- `--until <date>`: Optional. Lists only the snapshots taken at that moment or earlier, written and read as `--since` is.
