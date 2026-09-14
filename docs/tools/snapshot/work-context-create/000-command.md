# oparch-snapshot-work-context-create

## Description

`oparch-snapshot-work-context-create` creates a manual snapshot of one work context's home, under `/snapshots/home/<work-context>/manual`, named `@<unix-seconds>` after the moment it is taken, and records the human-readable justification it is given in the labels file [Snapshot Labels File Format](../system-create/001-labels-file-format.md) defines.

The scope is the subvolume of that context's home, `home/@<work-context>`, mounted at `/home/<work-context>`.

It takes the snapshot and writes its label while holding the lock [Snapshot Storage Lock](../system-create/003-storage-lock.md) specifies, and waits for the lock when another tool holds it.

It prints the path of the snapshot it made.

## Why is needed

Operations on a person's own data are destructive and belong to one context at a time. A snapshot scoped to a single work context creates a precise rollback anchor, and leaves the other contexts out of what is being restored.

## Requirements

What has to be installed where this runs, which is the machine whose work context is snapshotted — this tool is entered rather than aimed, as [Acting on Another System](../../../development/004-acting-on-another-system.md) decides, so it snapshots the home it finds mounted there, into the `/snapshots` [Disk Layout](../../../decisions/001-disk-layout.md) mounts.

It runs as root, because it snapshots the subvolume mounted at the context's home and writes under `/snapshots`. Run by any other user, it refuses with an error before doing anything else.

- **`btrfs-progs`**, for `btrfs`: the snapshot is a read-only snapshot of the subvolume mounted at the context's home.
- **`coreutils`**, for `id`, which tells whether it runs as root, and for `date`, which gives the moment the snapshot is named after.
- **`util-linux`**, for `flock`, which holds the lock.

`coreutils` and `util-linux` are part of `base`, and `btrfs-progs` is installed on every machine this project installs, so there is nothing to add before a run.

There is no BAML runtime library in this list: this tool has no host, so `baml pack` makes it a standalone binary — the distinction is [Host Bridge](../../../development/001-host-bridge.md).

## Input parameters

- `<name>`: Mandatory. Work context whose home subvolume is snapshotted.
- `<justification>`: Mandatory. Human-readable reason for the snapshot, recorded in the labels file. It may be any Unicode text, line breaks included, and it is refused when it is empty or holds only whitespace.
