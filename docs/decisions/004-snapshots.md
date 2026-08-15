# Snapshots

## Context

System state and per-user home data change independently and have different rollback scopes.

## Decision

Snapshot policy is split by scope:

- System scope (`@`): snapshot at boot start, on each package installation/update transaction, and on explicit manual request.
- User scope (`home/@<login-user>` subvolume): snapshot at login start for that specific user and on explicit manual request.

Home snapshots are per-context because rollback scope must be isolated per work context. Because Btrfs snapshots are created at subvolume level, each work context's home is a dedicated subvolume.
All snapshots are stored in a single `@snapshots` subvolume mounted at `/snapshots` with structured paths:

- `/snapshots/system/automatic`
- `/snapshots/system/manual`
- `/snapshots/home/<login-user>/automatic`
- `/snapshots/home/<login-user>/manual`

Snapshot strategy is restore-only. Snapshots are not boot targets in GRUB.

### Snapshot Retention Policy

- `@`: keep the last 60 automatic snapshots.
- `home/@<login-user>`: keep the last 60 automatic snapshots per user.
- Manual snapshots are never auto-purged for either `@` or `home/@<login-user>`.
- Every manual snapshot must include a human-readable justification in its name or label.
- Manual snapshot cleanup is explicitly manual when justification is no longer valid.

## Why

- `@` snapshots at boot start are used so the operator can restore the system later if they break it during that work session.
- `@` snapshots on package transactions are used because package install/update is the main source of system-state risk; if skipped, there is no immediate rollback anchor after a bad package transaction.
- Manual `@` snapshots are used because rare manual system changes still happen outside package tooling; if missing, those changes cannot be rolled back to a known pre-change state.
- Per-user home snapshots are created at login start because accidental deletion or overwrite risk appears during active user work; if the snapshot is not created before the session starts, there is no guaranteed rollback point for mistakes made early in that session.
- Manual per-user home snapshots are used because some user operations are intentionally high-risk (for example bulk moves or destructive cleanup); if omitted, those operations have no explicit pre-change recovery anchor.
- Dedicated home subvolumes are required because Btrfs can snapshot only at subvolume boundaries; if homes are not split per user subvolume, isolated per-user rollback cannot be implemented.
- A single snapshot storage subvolume (`@snapshots`) is required because this model centralizes snapshot data while keeping a simple mount layout; if omitted, storage layout drifts from the chosen single-container policy.
- Structured paths (`system`, `home/<work-context>`, `automatic`, and `manual`) inside `/snapshots` are required because the system history and each context's history must remain targetable independently without reserving names; if omitted, create/restore operations are easier to misapply.
- Keeping 60 automatic snapshots in `@` and 60 per-user home snapshots is used because recovery history must be long enough to be useful but still bounded; if too low, useful rollback points disappear too quickly, and if unbounded, disk usage grows without control.
- Never auto-purging manual snapshots is used because manual snapshots are deliberate operator checkpoints; if auto-purged, explicitly chosen recovery anchors can disappear without operator intent.
- Requiring a human-readable justification in manual snapshot name/label is used because indefinitely retained snapshots need future cleanup decisions; if unlabeled, old manual snapshots become hard to evaluate and safe cleanup becomes guesswork.
- Restore-only snapshot policy is required because GRUB snapshot boot entries add complexity and do not align well with `/boot` outside snapshot scope; if snapshot boot is enabled, recovery semantics become less predictable.

## Considerations

- Root and home snapshot flows should remain independent.
- Boot snapshots should not prevent the system from starting if snapshot creation fails.
- Login snapshots should not block login if snapshot creation fails.
- Snapshot naming should make session boundaries easy to identify.
- Snapshot storage must remain separated by domain inside `/snapshots`: `system` for system snapshots and `home/<login-user>` per user.
- Since `/boot` is outside Btrfs, snapshot rollback does not cover boot artifacts.
- Severe recovery path is: boot `Recovery`, chroot, then execute snapshot restore.

## Restore Procedure (Reference)

Create/restore command interface for this single-`@snapshots` path model is intentionally deferred to dedicated snapshot scripts.
