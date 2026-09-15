# Snapshot Storage Lock

## Context

Three things under `@snapshots` are shared by every tool that takes or removes snapshots: the boot table and the sets of boot artifacts that [Boot Artifacts Table Format](002-boot-table-format.md) specifies, and the labels file that [Snapshot Labels File Format](001-labels-file-format.md) specifies. Each is changed by reading what is there and writing it back, and the tools that change them start on their own: when the machine starts, before a package transaction, when a work context logs in, and when the operator asks.

## Specification

### Where it is

`lock`, at the top of the `@snapshots` subvolume, which the installed system reaches as `/snapshots/lock`. It is an empty file, created by the first tool that takes the lock.

### What it is

An exclusive `flock(2)` lock on that file.

### Who holds it

A tool that writes the boot table, the labels file or a set of boot artifacts takes the lock before it reads any of them, and before it reads the moment a snapshot it takes is named after, and holds it until it has written the last of them. A tool that finds the lock held waits for it, for as long as it is held.

The lock belongs to the process holding it, and it is released when that process ends, however it ends.

[oparch-snapshot-create](000-command.md) holds it for the whole of each system snapshot it takes, with the deleting that follows an automatic one, and for the whole of each manual snapshot of a work context's home it takes and labels. [oparch-snapshot-remove](../remove/000-command.md) holds it for the whole of each removal, and [oparch-snapshot-interactive](../interactive/000-command.md) for the whole of each manual snapshot it takes and of each removal.

## Why

- There is one lock for all three because one operation changes more than one of them: a system snapshot stores a set, adds a line to the table and adds a label, and removing a system snapshot removes its line and then every set no line points at. A lock for each would let one run delete a set between the moment another run stored it and the moment it wrote the line that points at it.
- A tool waits for the lock rather than giving up because the runs that find it held are the ones nobody is watching: an automatic snapshot at boot or before a transaction, refused because the operator was taking one by hand at the same moment, is a rollback point missing on the day it is wanted.
- The moment is read under the lock so that the order of the names is the order in which the snapshots were written into the table.
- The lock is a `flock(2)` lock because the kernel releases it when its holder ends. A lock that had to be removed by the tool that took it would be left behind by a tool killed half way, and every snapshot after it would wait for ever.

## Considerations

- A process that holds the lock and stops without ending keeps it, and every tool that needs it waits until that process is ended.
