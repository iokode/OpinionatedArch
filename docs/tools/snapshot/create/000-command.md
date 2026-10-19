# oparch-snapshot-create

## Description

`oparch-snapshot-create` creates a snapshot of one scope: the system, or the home of one work context. The scope of a work context's home is the subvolume of that home, `home/@<work-context>`, mounted at `/home/<work-context>`. A snapshot is named `@<unix-seconds>` after the moment it is taken, and the tool prints the path of the snapshot it made.

A snapshot is manual or automatic:

- A manual snapshot, taken with `--justification`, goes under `/snapshots/system/manual` for the system and under `/snapshots/home/<work-context>/manual` for the home of a work context. The tool records the human-readable justification it is given in the labels file [Snapshot Labels File Format](001-labels-file-format.md) defines. A manual snapshot is never purged.
- An automatic snapshot, taken with `--automatic`, goes under `/snapshots/system/automatic` for the system and under `/snapshots/home/<work-context>/automatic` for the home of a work context. In the same run the tool deletes the automatic snapshots of that scope that the retention policy of [Snapshots](../../../decisions/004-snapshots.md) no longer keeps: every one but the latest sixty. The snapshot is taken first, and a snapshot that cannot be taken deletes nothing. With `--automatic`, the tool is run at each moment [Snapshots](../../../decisions/004-snapshots.md) takes an automatic snapshot.

A system snapshot takes the boot artifacts of that moment with it, as [Snapshots](../../../decisions/004-snapshots.md) requires: the tool hashes them, stores the set under the name its hash gives it when that set is not there already, and records which set belongs to the snapshot it has just made, as [Boot Artifacts Table Format](002-boot-table-format.md) specifies. When `--automatic` deletes system snapshots, their lines leave that table, and every set of boot artifacts no line points at is deleted.

It holds the lock [Snapshot Storage Lock](003-storage-lock.md) specifies whenever it writes the boot table, the labels file or a set of boot artifacts, as that document says, and waits for the lock when another tool holds it.

## Why is needed

System-level manual checkpoints are required before risky non-package changes. Mandatory justification keeps long-lived manual snapshots understandable for later recovery and cleanup decisions.

Operations on a person's own data are destructive and belong to one context at a time. A snapshot scoped to a single work context creates a precise rollback anchor, and leaves the other contexts out of what is being restored.

Automatic snapshots are taken with nobody there to take them, and they stay bounded only if something deletes the old ones. Taking and purging in one run makes the retention a consequence of taking: a scope never holds more than the policy keeps, and there is no second schedule to keep in step with the first.

## Requirements

What has to be installed where this runs, which is the machine whose snapshots are taken — this tool is entered rather than aimed, as [Acting on Another System](../../../development/004-acting-on-another-system.md) decides, so it snapshots the `/` and the homes it finds there, and copies the `/boot` it finds there, into the `/snapshots` [Disk Layout](../../../decisions/001-disk-layout.md) mounts.

It runs as root, because it snapshots and deletes subvolumes and writes under `/snapshots`. Run by any other user, it refuses with an error before doing anything else.

- **`btrfs-progs`**, for `btrfs`: a snapshot is a read-only snapshot of the subvolume of its scope, and an automatic snapshot the retention no longer keeps is deleted as the subvolume it is.
- **`coreutils`**, for `id`, which tells whether it runs as root, for `date`, which gives the moment a snapshot is named after, for `sha256sum`, `mktemp`, `cp` and `mv`, which hash the boot artifacts and store their set, and for `rm`, which deletes a set nothing points at.
- **`util-linux`**, for `flock`, which holds the lock.
- **`glibc`**, for `getent`, which finds the account a UID belongs to.

`coreutils`, `util-linux` and `glibc` are part of `base`, and `btrfs-progs` is installed on every machine this project installs, so there is nothing to add before a run.

There is no BAML runtime library in this list: this tool has no host, so `baml pack` makes it a standalone binary — the distinction is [Host Bridge](../../../development/001-host-bridge.md).

## Input parameters

- `<scope>`: Mandatory. Snapshot scope. Accepted values: `system`, `home`.
- `<name>`: Mandatory for `home` scope, and refused with `system` scope. Work context whose home subvolume is snapshotted, given by its name or by its UID: a value made only of decimal digits is a UID, and the work context is the account that has it.
- `--justification <text>`: Takes a manual snapshot. `<text>` is the argument that follows `--justification`, whatever it holds, text that starts with `--` included. It is the human-readable reason for the snapshot, recorded in the labels file. It may be any Unicode text, line breaks included, and it is refused when it is empty or holds only whitespace. When `<name>` is a UID, the work context is resolved from it before a blank justification is refused.
- `--automatic`: Takes an automatic snapshot, and deletes the automatic snapshots of its scope beyond the latest sixty.

Options may come before or after `<scope>` and `<name>`.

Exactly one of `--justification` and `--automatic` is given: neither, both, or either of them given twice, is refused.

Any other argument that starts with `--` is an unknown option, and is refused with exit code 2.
