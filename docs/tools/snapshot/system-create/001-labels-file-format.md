# Snapshot Labels File Format

## Context

Every manual snapshot carries a human-readable justification, as [Snapshots](../../../decisions/004-snapshots.md) requires, so that whether it is still worth keeping can be judged long after it was taken. A snapshot is named `@<unix-seconds>`, after the moment it was taken, and its justification is kept apart from its name: in one file at the top of `@snapshots`, for every manual snapshot of the machine.

## Specification

### Where it is

`labels.json`, at the top of the `@snapshots` subvolume, which the installed system reaches as `/snapshots/labels.json`.

### What it holds

One JSON object, encoded in UTF-8. Each member is one manual snapshot:

- its name is the path of the snapshot inside `@snapshots`: `system/manual/@<unix-seconds>` for the system, and `home/<work-context>/manual/@<unix-seconds>` for the home of a work context;
- its value is the justification, as a JSON string.

A justification may be any Unicode text, line breaks included, and it is never empty or made only of whitespace.

```json
{"system/manual/@1778764800":"before a kernel upgrade","home/work/manual/@1778765100":"before the client project import"}
```

A machine with no labels file has no labelled snapshot.

### How it is written

A tool that labels a snapshot holds the lock [Snapshot Storage Lock](003-storage-lock.md) specifies, reads the file, adds the member for that snapshot, and writes the whole object back, keeping every member it held. A file that is there and cannot be read, or that is not a JSON object whose values are strings, is an error, and it is not written over.

[oparch-snapshot-system-create](000-command.md) writes a member for each manual system snapshot it takes, and [oparch-snapshot-work-context-create](../work-context-create/000-command.md) one for each manual snapshot of a work context's home.

## Why

- The justification is kept out of the name because a name is a path segment and a justification is any text: a slash, a line break or a long sentence cannot be part of one. A name that is only the moment the snapshot was taken is also one that sorts by that moment and reads back without guessing where the moment ends.
- The labels are in a file of their own outside the snapshots because a snapshot is read only once it is made, and a justification written inside one would have to exist before the snapshot did. One file for all of them keeps the directories of each scope holding snapshots and nothing else.
- The file is not the boot table because the two answer different questions about different snapshots: the table pairs each system snapshot, automatic or manual, with the boot artifacts it is restored with, and this pairs each manual snapshot, of any scope, with the reason it was taken.
- A snapshot is named by its path inside `@snapshots` because that is where the file itself is, so what it says holds wherever the subvolume is mounted.
- The format is JSON because a justification is any text, and a JSON string carries every character of it, line breaks and quotes included, in a form any JSON parser reads back exactly.
- A file that cannot be read is never written over because writing a label rewrites the whole file: taken for an empty one, it would replace the justification of every manual snapshot on the machine with the one being added.
