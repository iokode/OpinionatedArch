# oparch-snapshot-work-context-create

## Description

`oparch-snapshot-work-context-create` creates a manual snapshot of one work context's home, under `/snapshots/home/<work-context>/manual`.

## Why is needed

Operations on a person's own data are destructive and belong to one context at a time. A snapshot scoped to a single work context creates a precise rollback anchor, and leaves the other contexts out of what is being restored.

## Input parameters

- `<name>`: Mandatory. Work context whose home subvolume is snapshotted.
- `<justification>`: Mandatory. Human-readable reason to include in the snapshot name or label.
