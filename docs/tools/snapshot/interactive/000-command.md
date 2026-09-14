# oparch-snapshot-interactive

## Description

`oparch-snapshot-interactive` is the interactive interface for the snapshots of the machine. It lists them and narrows the list down, creates a manual snapshot, removes one and restores one, carrying each operation out through the snapshot library, which the snapshot command-line tools are built on too.

It runs on the installed system and on the recovery system, and it restores only from the recovery system, as [Snapshots](../../../decisions/004-snapshots.md) decides.

## Why is needed

Snapshots accumulate in every scope, and the one wanted is found by when it was taken and what it was taken for rather than by its path. The interactive tool shows them readably and narrows them down, and the operations remain owned by the snapshot library.

## Requirements

What has to be installed where this runs, which is the machine whose snapshots are shown — this tool is entered rather than aimed, as [Acting on Another System](../../../development/004-acting-on-another-system.md) decides, so it acts on the `/snapshots` [Disk Layout](../../../decisions/001-disk-layout.md) mounts there.

It runs as root, because it snapshots and deletes subvolumes and writes under `/snapshots`. Run by any other user, it refuses with an error before it takes the terminal over.

Everything [oparch-snapshot-create](../create/000-command.md) and [oparch-snapshot-remove](../remove/000-command.md) require, because it takes and removes snapshots through the same library. On top of that:

- **`glibc`**, for `getent`, which reads the members of `work-contexts`: the work contexts a snapshot of a home is offered for.
- **The BAML runtime library.** This tool has a host, so its binary loads a shared library of about 25 MB rather than carrying it. Where it comes from is [Host Bridge](../../../development/001-host-bridge.md). It comes in a package of its own, `oparch-baml-runtime`, which this tool's package depends on. What goes on `PATH` is a wrapper that names the library with `BAML_LIBRARY_PATH`, along with `BAML_LIBRARY_DISABLE_DOWNLOAD`, which turns a missing library into a failure instead of a silent download.

`glibc` is part of `base`, so it is on every machine this project installs.

## Interactive usage

- Shows the snapshots readably: scope, work context, automatic or manual, when it was taken, and its justification. When it was taken is shown in UTC, written `YYYY-MM-DDTHH:MM:SS`.
- Narrows the list by scope; by work context, when the scope is `home`; by the dates it was taken between, typed in UTC and written `YYYY-MM-DDTHH:MM:SS`; and by automatic or manual. Typing filters the rows, which is how a snapshot is found by the text of its justification.
- Create a manual snapshot:
  - Mandatory input: scope.
  - Mandatory input for `home` scope: work context whose home is snapshotted, chosen from the members of `work-contexts`.
  - Mandatory input: justification.
- Remove a snapshot:
  - Mandatory input: snapshot to remove, chosen from the list.
  - Mandatory input: confirmation.
- Restore a snapshot:
  - On the installed system, choosing it fails with an error saying that restores run from the recovery system.
  - Mandatory input: snapshot to restore, chosen from the list.
  - Mandatory input: confirmation.
- Carry out the chosen operation through the snapshot library with the collected values.
