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

The tool takes over the terminal and opens on the list of snapshots, which fills the screen. It holds every snapshot under `/snapshots`, earliest first, one row each: the date and time it was taken, in UTC and written `YYYY-MM-DDTHH:MM:SS`, its scope, the work context whose home it is, whether it is automatic or manual, and its justification, with its line breaks shown as spaces. Two rows come before the snapshots, one that narrows the list and one that takes a manual snapshot. The list is read again every time it is shown, so it holds what an operation has just done. Typing filters the rows.

Narrowing the list opens a screen of what it can be narrowed by, each with what it narrows to now: the scope, the work context once the scope is `home`, the earliest and the latest moment a snapshot shown was taken at, and the kind. Choosing one asks it. The scope and the kind are chosen from a list that also offers both; the work context from the work contexts whose homes have snapshots, or all of them. The two moments are typed as a date and time in UTC written `YYYY-MM-DDTHH:MM:SS`, both included, and an empty field is no bound. What is answered narrows the list at once, and going back from that screen shows it.

Taking a manual snapshot asks the scope, then, for `home`, the work context, chosen from the members of `work-contexts`, and then the justification. The field takes one line, because `Enter` accepts it. When the snapshot has been taken, a box gives the path of the snapshot made, or says what failed and what the failing command wrote.

Choosing a snapshot from the list asks, in a box over it, whether to remove it, and shows the whole of it: its scope, its work context, its kind, when it was taken, its justification and its path. Once that is confirmed, it is removed, and a box says so, or says what failed.

An answer that is not taken is reported on the screen it was given on, and that screen is asked again: a justification that is empty or holds only whitespace, and a moment that is not a date and time written as above, which is asked again as it was typed. What stops the list from being read, such as a labels file that is not one, is reported on the list, and what stops the work contexts from being read is reported on the scope.

| Key | Action |
| --- | --- |
| `↑` `↓` | Move within a list |
| Typing | Filter a list, or type into a field |
| `Enter` | Select, or accept a field |
| `Esc`, `F1` | Go back one screen; the list of snapshots has nothing behind it and stays |
| `Enter`, `y` | Answer yes to whether to remove a snapshot, or close a box |
| `Esc`, `n` | Answer no to whether to remove a snapshot, or close a box |
| `F6` | Leave, after a confirmation, from a list or a field |
| `F8` | Read the runtime log |

The exit status is `0` when the operator leaves, and `1` when the run was refused, when the terminal could not be taken over, or when the screens stopped on an error.
