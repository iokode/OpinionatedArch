# oparch-snapshot-interactive

## Description

`oparch-snapshot-interactive` is the interactive interface for the snapshots of the machine. It lists them and narrows the list down, creates a manual snapshot, removes one and restores one, carrying each operation out through the snapshot library, which the snapshot command-line tools are built on too.

It runs on the installed system and on the recovery system, and it restores only from the recovery system, as [Snapshots](../../../decisions/004-snapshots.md) decides.

## Why is needed

Snapshots accumulate in every scope, and the one wanted is found by when it was taken and what it was taken for rather than by its path. The interactive tool shows them readably and narrows them down, and the operations remain owned by the snapshot library.

## Interactive usage

- Shows the snapshots readably: scope, work context, automatic or manual, when it was taken, and its justification.
- Narrows the list by scope; by work context, when the scope is `home`; by the dates it was taken between; by automatic or manual; and by text in the justification.
- Create a manual snapshot:
  - Mandatory input: scope.
  - Mandatory input for `home` scope: work context whose home is snapshotted.
  - Mandatory input: justification.
- Remove a snapshot:
  - Mandatory input: snapshot to remove, chosen from the list.
  - Mandatory input: confirmation.
- Restore a snapshot:
  - On the installed system, choosing it fails with an error saying that restores run from the recovery system.
  - Mandatory input: snapshot to restore, chosen from the list.
  - Mandatory input: confirmation.
- Carry out the chosen operation through the snapshot library with the collected values.
