# oparch-snapshot-system-create

## Description

`oparch-snapshot-system-create` creates a manual system-scope snapshot under `/snapshots/system/manual` and requires a human-readable justification in the snapshot name or label.

It takes the boot artifacts of that moment with it, as [Snapshots](../../decisions/004-snapshots.md) requires: it hashes them, stores the set under the name its hash gives it when that set is not there already, and records which set belongs to the snapshot it has just made.

## Why is needed

System-level manual checkpoints are required before risky non-package changes. Mandatory justification keeps long-lived manual snapshots understandable for later recovery and cleanup decisions.

## Input parameters

- `<justification>`: Mandatory. Human-readable reason to include in the snapshot name or label.
