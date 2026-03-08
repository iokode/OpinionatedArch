# 008: Snapshot Strategy

## Context and Decision

Snapshot policy is split by scope:

- System scope (`@`): snapshot on each package installation/update transaction and on explicit manual request.
- User scope (`/home/<login-user>` subvolume): snapshot at login start for that specific user and on explicit manual request.

Home snapshots are per-user because rollback scope must be isolated per login user. Because Btrfs snapshots are created at subvolume level, each login user home is a dedicated subvolume.

### Snapshot Retention Policy

- `@`: keep the last 60 automatic snapshots.
- `@home-<login-user>`: keep the last 60 automatic snapshots per user.
- Manual snapshots are never auto-purged for either `@` or `@home-<login-user>`.
- Every manual snapshot must include a human-readable justification in its name or label.
- Manual snapshot cleanup is explicitly manual when justification is no longer valid.

## Why

- `@` snapshots on package transactions are used because package install/update is the main source of system-state risk; if skipped, there is no immediate rollback anchor after a bad package transaction.
- Manual `@` snapshots are used because rare manual system changes still happen outside package tooling; if missing, those changes cannot be rolled back to a known pre-change state.
- Per-user home snapshots are created at login start because accidental deletion or overwrite risk appears during active user work; if the snapshot is not created before the session starts, there is no guaranteed rollback point for mistakes made early in that session.
- Manual per-user home snapshots are used because some user operations are intentionally high-risk (for example bulk moves or destructive cleanup); if omitted, those operations have no explicit pre-change recovery anchor.
- Dedicated home subvolumes are required because Btrfs can snapshot only at subvolume boundaries; if homes are not split per user subvolume, isolated per-user rollback cannot be implemented.
- Keeping 60 automatic snapshots in `@` and 60 per-user home snapshots is used because recovery history must be long enough to be useful but still bounded; if too low, useful rollback points disappear too quickly, and if unbounded, disk usage grows without control.
- Never auto-purging manual snapshots is used because manual snapshots are deliberate operator checkpoints; if auto-purged, explicitly chosen recovery anchors can disappear without operator intent.
- Requiring a human-readable justification in manual snapshot name/label is used because indefinite retention requires future audit and cleanup decisions; if unlabeled, old manual snapshots become hard to evaluate and safe cleanup becomes guesswork.

## Implementation Plan

1. Configure root snapshot automation for package install/update operations.
2. Expose a manual command/script for on-demand root snapshots.
3. Trigger a user-home snapshot when a login session starts.
4. Expose a manual command/script for on-demand per-user home snapshots.
5. Ensure user-provisioning flow registers new login users for login-time and manual home snapshots.

## Considerations

- Root and home snapshot flows should remain independent.
- Login snapshots should not block login if snapshot creation fails.
- Snapshot naming should make session boundaries easy to identify.
- If `/boot` is outside Btrfs, snapshot rollback does not cover boot artifacts.

## Critical Notes With Replies (Copy of Discussion)

1. Assistant critique: snapshotting a single `@home` subvolume at login can cause rollback side effects across users.
   Decision response: switch to per-user home subvolumes so rollback scope stays isolated per login user.
2. Assistant critique: per-user home subvolumes add lifecycle complexity when creating users after installation.
   Decision response: handle user creation through a dedicated provisioning command/script that always creates the user home subvolume.
