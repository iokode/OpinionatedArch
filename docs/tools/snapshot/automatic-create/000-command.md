# oparch-snapshot-automatic-create

## Description

`oparch-snapshot-automatic-create` creates an automatic snapshot of one scope, under `/snapshots/system/automatic` for the system and under `/snapshots/home/<work-context>/automatic` for the home of a work context, named `@<unix-seconds>` after the moment it is taken. In the same run it deletes the automatic snapshots of that scope that the retention policy of [Snapshots](../../../decisions/004-snapshots.md) no longer keeps: every one but the sixty whose names give the latest moments. What the directory holds that is not named `@<unix-seconds>` is left alone. The snapshot is taken first, and a snapshot that cannot be taken deletes nothing.

A system snapshot takes the boot artifacts of that moment with it, as [Snapshots](../../../decisions/004-snapshots.md) requires, in the way [oparch-snapshot-system-create](../system-create/000-command.md) takes them. Deleting a system snapshot removes its line from the table [Boot Artifacts Table Format](../system-create/002-boot-table-format.md) specifies, and once the old snapshots are deleted, every directory under `/snapshots/boot` that no line of the table points at is deleted too, so a set of boot artifacts goes with the last snapshot that points at it. For the system scope the whole run holds the lock [Snapshot Storage Lock](../system-create/003-storage-lock.md) specifies, and waits for it when another tool holds it. An automatic snapshot of a home writes nothing that lock covers, and does not take it.

It prints the path of the snapshot it made.

It is run at each moment [Snapshots](../../../decisions/004-snapshots.md) takes an automatic snapshot, by what its package installs. When the machine starts, `multi-user.target` wants `oparch-snapshot-automatic-system.service`, which runs it for the system. Before each package transaction that installs or upgrades a package, a pacman hook starts that same unit and waits for it to finish; in a chroot, where `systemctl` starts nothing, no snapshot is taken. When a work context logs in with no session open already, its user manager starts; a drop-in for `user@.service` wants `oparch-snapshot-automatic-home@<uid>.service` and starts after it, and that unit runs it for the home scope, given the work context's UID.

A snapshot that cannot be taken fails its unit and stops nothing else: the machine starts, the transaction goes on and the login completes. What the tool said is in the journal, under that unit.

## Why is needed

Automatic snapshots are taken with nobody there to take them, and they stay bounded only if something deletes the old ones. Taking and purging in one run makes the retention a consequence of taking: a scope never holds more than the policy keeps, and there is no second schedule to keep in step with the first.

## Requirements

What has to be installed where this runs, which is the machine whose snapshots are taken — this tool is entered rather than aimed, as [Acting on Another System](../../../development/004-acting-on-another-system.md) decides, so it snapshots the `/` and the homes it finds there, into the `/snapshots` [Disk Layout](../../../decisions/001-disk-layout.md) mounts.

It runs as root, because it snapshots and deletes subvolumes and writes under `/snapshots`; the units that start it run it as root. Run by any other user, it refuses with an error before doing anything else.

- **`btrfs-progs`**, for `btrfs`: a snapshot is a read-only snapshot of the subvolume of its scope, and an old one is deleted as the subvolume it is.
- **`coreutils`**, for `id`, which tells whether it runs as root, for `date`, which gives the moment a snapshot is named after, for `sha256sum`, `mktemp`, `cp` and `mv`, which hash the boot artifacts and store their set, and for `rm`, which deletes a set nothing points at.
- **`util-linux`**, for `flock`, which holds the lock.
- **`glibc`**, for `getent`, which finds the account a UID belongs to.
- **`systemd`**, which runs the units that start it, and whose `systemctl` the pacman hook starts the system's unit with.

`coreutils`, `util-linux`, `glibc` and `systemd` are part of `base`, and `btrfs-progs` is installed on every machine this project installs, so there is nothing to add before a run.

There is no BAML runtime library in this list: this tool has no host, so `baml pack` makes it a standalone binary — the distinction is [Host Bridge](../../../development/001-host-bridge.md).

## Input parameters

- `<scope>`: Mandatory. Snapshot scope. Accepted values: `system`, `home`.
- `<name>`: Mandatory for `home` scope, and refused with `system` scope. Work context whose home subvolume is snapshotted, given by its name or by its UID: a value made only of decimal digits is a UID, and the work context is the account that has it.
