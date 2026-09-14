# Boot Artifacts Table Format

## Context

A system snapshot carries the boot artifacts of its moment, as [Snapshots](../../../decisions/004-snapshots.md) requires. They are on the EFI system partition, outside Btrfs, so they are copied under `@snapshots/boot` rather than snapshotted: one directory for each distinct set of them, named by the hash of its contents, and a table pairing each system snapshot with its set.

## Specification

### What a set is

A set of boot artifacts is the whole content of the EFI system partition, mounted at `/boot`, at the moment a system snapshot is taken. It is stored as a directory `@snapshots/boot/<hash>/` holding every file of the partition at the path it has under `/boot`.

### The hash

The name of a set is the SHA-256 of its manifest, written as 64 lowercase hexadecimal digits.

The manifest is UTF-8 text with one line for every regular file under `/boot`, at any depth. A line is the SHA-256 of the file's content in 64 lowercase hexadecimal digits, two spaces, the path of the file relative to `/boot` with its components separated by `/`, and a line feed. The lines are ordered by that path, in byte order.

Nothing else is part of it: not the directories themselves, and not the modes, owners or timestamps of the files. A partition with no files has an empty manifest.

For a partition holding `OpinionatedArch/vmlinuz-linux` and `EFI/OpinionatedArch/grubx64.efi`, the manifest is:

```text
590c0ceb7e659f76f8f102c8e0d78b7df150474fd0560baa4bdbb5b16aab42b3  EFI/OpinionatedArch/grubx64.efi
a0c936696eb7d5ee3192bf53b9d281cecbb40ca9db520de72cb95817ad92ac72  OpinionatedArch/vmlinuz-linux
```

and the set is stored as `@snapshots/boot/5d4b9941488420e4ce8bf420f73fa197bbe2857d238ac375d155af8c3bbde357/`, the SHA-256 of those two lines.

### Storing a set

A set whose directory is already under `@snapshots/boot` is not copied again. Otherwise the content of `/boot` is copied into a new directory under `@snapshots/boot` with a name of its own, and that directory is renamed to the hash once the copy is whole.

### The table

`@snapshots/boot/table` is UTF-8 text with one line for each system snapshot, in the order they were taken. A line is the path of the snapshot inside `@snapshots`, one space, the hash of its set, and a line feed:

```text
system/automatic/@1778761200 2c6d281a7198da35893e6b5bfcb1fc2d3499169c27055adc47430645652f2050
system/manual/@1778764800 2c6d281a7198da35893e6b5bfcb1fc2d3499169c27055adc47430645652f2050
system/automatic/@1778847600 2d07898b568b0949d5863b8d4949b3f2d505c9c36e80426d72897a66c41f46be
```

A set is stored before its snapshot is taken, and the line pairing the two is added once the snapshot has been. [oparch-snapshot-system-create](000-command.md) and [oparch-snapshot-automatic-create](../automatic-create/000-command.md) add one for each system snapshot they take.

A line is removed when its snapshot is deleted. Every directory under `@snapshots/boot` that no line points at is then deleted, which is how a set goes with the last snapshot that points at it, and how a copy left unnamed by a run that stopped half way is cleared. [oparch-snapshot-automatic-create](../automatic-create/000-command.md) does both for the automatic snapshots it deletes.

### Writing them

The table and the sets are read and written only while holding the lock [Snapshot Storage Lock](003-storage-lock.md) specifies.

## Why

- The hash is taken over paths as well as contents because restoring a set puts each file back where it was: the same bytes at another path start a different machine.
- The files are hashed one by one and listed in a fixed order because the name has to follow from the contents alone. Hashed in whatever order the partition lists them, the same set could be stored twice under two names, which is the copy the hash exists to avoid.
- Modes, owners and timestamps are left out because the partition is FAT32, which keeps no owners or modes of its own, and because what a restored set is for is the files it puts back, not when they were written.
- A copy is named by its hash only once it is whole because a stored set is never copied again. A copy that stopped half way under that name would be taken for the set by every later snapshot with the same contents, and restoring any of them would put back part of a partition.
- The table is plain lines because the question it answers is one: which set a snapshot is restored with. It is found by the snapshot's path, and a line is all that takes.
- A line names the snapshot by its path rather than by its name because an automatic and a manual system snapshot taken in the same second have the same name, and only the directory they are in tells them apart.
