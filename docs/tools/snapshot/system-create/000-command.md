# oparch-snapshot-system-create

## Description

`oparch-snapshot-system-create` creates a manual system-scope snapshot under `/snapshots/system/manual`, named `@<unix-seconds>` after the moment it is taken, and records the human-readable justification it is given in the labels file [Snapshot Labels File Format](001-labels-file-format.md) defines.

It takes the boot artifacts of that moment with it, as [Snapshots](../../../decisions/004-snapshots.md) requires: it hashes them, stores the set under the name its hash gives it when that set is not there already, and records which set belongs to the snapshot it has just made, as [Boot Artifacts Table Format](002-boot-table-format.md) specifies.

It does all of it while holding the lock [Snapshot Storage Lock](003-storage-lock.md) specifies, and waits for the lock when another tool holds it.

It prints the path of the snapshot it made.

## Why is needed

System-level manual checkpoints are required before risky non-package changes. Mandatory justification keeps long-lived manual snapshots understandable for later recovery and cleanup decisions.

## Requirements

What has to be installed where this runs, which is the machine whose system is snapshotted — this tool is entered rather than aimed, as [Acting on Another System](../../../development/004-acting-on-another-system.md) decides, so it snapshots the `/` it runs under and copies the `/boot` it finds there, into the `/snapshots` [Disk Layout](../../../decisions/001-disk-layout.md) mounts.

It runs as root, because it snapshots the subvolume mounted at `/` and writes under `/snapshots`. Run by any other user, it refuses with an error before doing anything else.

- **`btrfs-progs`**, for `btrfs`: the snapshot is a read-only snapshot of the subvolume mounted at `/`.
- **`coreutils`**, for `id`, which tells whether it runs as root, for `date`, which gives the moment the snapshot is named after, and for `sha256sum`, `mktemp`, `cp` and `mv`, which hash the boot artifacts and store their set.
- **`util-linux`**, for `flock`, which holds the lock.

`coreutils` and `util-linux` are part of `base`, and `btrfs-progs` is installed on every machine this project installs, so there is nothing to add before a run.

There is no BAML runtime library in this list: this tool has no host, so `baml pack` makes it a standalone binary — the distinction is [Host Bridge](../../../development/001-host-bridge.md).

## Input parameters

- `<justification>`: Mandatory. Human-readable reason for the snapshot, recorded in the labels file. It may be any Unicode text, line breaks included, and it is refused when it is empty or holds only whitespace.
