# oparch-snapshot-system-create

## Description

`oparch-snapshot-system-create` creates a manual system-scope snapshot under `/snapshots/system/manual` and requires a human-readable justification in the snapshot name or label.

## Why is needed

System-level manual checkpoints are required before risky non-package changes. Mandatory justification keeps long-lived manual snapshots understandable for later recovery and cleanup decisions.

## Input parameters

- `<justification>`: Mandatory. Human-readable reason to include in the snapshot name or label.
