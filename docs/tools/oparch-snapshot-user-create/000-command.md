# oparch-snapshot-user-create

## Description

`oparch-snapshot-user-create` creates a manual user-scope snapshot under `/snapshots/home/<login-user>/manual` for a selected login user.

## Why is needed

User data operations can be destructive and are often user-specific. A per-user snapshot tool creates precise rollback anchors and avoids cross-user ambiguity during recovery.

## Input parameters

- `<user>`: Mandatory. Login user whose home subvolume is snapshotted.
- `<justification>`: Mandatory. Human-readable reason to include in the snapshot name or label.
