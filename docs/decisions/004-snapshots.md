# Snapshots

## Context

System state and the data in a work context's home change independently and have different rollback scopes.

## Decision

Snapshot policy is split by scope:

- **System scope** (`@`): snapshot at boot start, on each package installation/update transaction, and on explicit manual request.
- **Work context scope** (`home/@<work-context>` subvolume): snapshot when that context is logged into, and on explicit manual request.

The scopes are independent of one another, and there are as many as the machine has work contexts, plus the system: three contexts make four. A snapshot holds the state of exactly one scope, and what is done to one — taking it, restoring it, deleting it — reaches nothing of the rest.

All snapshots are stored in a single `@snapshots` subvolume mounted at `/snapshots` with structured paths:

- `/snapshots/system/automatic`
- `/snapshots/system/manual`
- `/snapshots/home/<work-context>/automatic`
- `/snapshots/home/<work-context>/manual`

A system snapshot carries the boot artifacts of its moment. They cannot be inside the snapshot, because the EFI system partition is FAT32 and outside Btrfs, so what is kept is a copy of them under `@snapshots` and a table pairing each system snapshot with the set that belongs to it. A set is stored once, under the hash of its contents: a snapshot whose artifacts hash to a set already there points at that one instead of copying it again. Restoring a system snapshot puts its set back on the EFI system partition.

A snapshot is read only. Once it is made it is closed, and nothing writes to it again.

Snapshot strategy is restore-only. Snapshots are not boot targets in GRUB.

Restoring a snapshot makes the state it holds the current one, for `@` or for the home of one work context. Every snapshot taken after it is deleted, because it hangs from a state the machine no longer has.

Restoring cannot be undone. What the machine held at that moment is not kept: the snapshots covering it are later than the one being restored, so they go with the rest.

Every restore runs from the recovery system. Neither `@` nor the home of a work context is restored while the installed system is running.

A snapshot that cannot be taken does not stop what it was taken for. The machine starts, and a work context logs in, whether or not its snapshot was made. What it does not do is fail quietly: a snapshot that did not happen is reported to the operator.

### Snapshot Retention Policy

- `@`: keep the last 60 automatic snapshots.
- `home/@<work-context>`: keep the last 60 automatic snapshots per work context.
- Manual snapshots are never auto-purged for either `@` or `home/@<work-context>`.
- Every manual snapshot must include a human-readable justification in its name or label.
- Manual snapshot cleanup is explicitly manual when justification is no longer valid.
- A set of boot artifacts is removed when the last snapshot pointing at it is, in the same pass that purges them.

## Why

- `@` snapshots at boot start are used so the operator can restore the system later if they break it during that work session.
- `@` snapshots on package transactions are used because package install/update is the main source of system-state risk; if skipped, there is no immediate rollback anchor after a bad package transaction.
- Manual `@` snapshots are used because rare manual system changes still happen outside package tooling; if missing, those changes cannot be rolled back to a known pre-change state.
- A context's home is snapshotted when it is logged into because that is when the risk of deleting or overwriting its data appears; taken any later, the mistakes made early in the session are already inside it.
- Manual snapshots of a home are used because some of the work done there is deliberately risky — a bulk move, a destructive cleanup — and without one those operations have no anchor to come back to.
- Only a work context has a home that can be snapshotted at all, because Btrfs snapshots at subvolume boundaries and only a work context's home is a subvolume of its own, as [Disk Layout](001-disk-layout.md) lays it out; homes sharing one subvolume could only be rolled back together.
- A single snapshot storage subvolume (`@snapshots`) is required because this model centralizes snapshot data while keeping a simple mount layout; if omitted, storage layout drifts from the chosen single-container policy.
- Structured paths (`system`, `home/<work-context>`, `automatic`, and `manual`) inside `/snapshots` are required because the system history and each context's history must remain targetable independently without reserving names; if omitted, create/restore operations are easier to misapply.
- Keeping 60 automatic snapshots in `@` and 60 in each context's home is used because recovery history must be long enough to be useful but still bounded: too few and useful rollback points disappear before they are wanted, unbounded and disk usage grows with nothing to stop it. Sixty itself is arbitrary. It was not derived from anything, and it moves the day something shows what the number should be.
- A snapshot that fails does not block boot or login because a snapshot exists to make work recoverable, and a machine that refuses to start protects nothing. This is the opposite of what an installation does, where a step that fails stops the run, and the difference is that an installation can be begun again from nothing while a machine in use cannot. It is reported because a rollback point that was never made is otherwise discovered on the day it is wanted, which is the one day nothing can be done about it.
- Never auto-purging manual snapshots is used because manual snapshots are deliberate operator checkpoints; if auto-purged, explicitly chosen recovery anchors can disappear without operator intent.
- Requiring a human-readable justification in manual snapshot name/label is used because indefinitely retained snapshots need future cleanup decisions; if unlabeled, old manual snapshots become hard to evaluate and safe cleanup becomes guesswork.
- Restore-only is required because booting a snapshot opens more questions than it answers, and they arrive together. The boot menu would have to carry an entry per snapshot, generated rather than written, which is not the menu this project keeps. A snapshot is read only, so what it would mean to change a file inside one that is running has no answer here. And the kernel and the initramfs live on the EFI partition: a system snapshot has its own set, but only restoring puts a set back, so a snapshot booted directly would be an old root under today's kernel. Restoring raises none of the three: the state comes back where it was, and what starts afterwards is an ordinary machine.
- The boot artifacts are kept and restored with the system because a root and the kernel that ran it are one state. Restoring `@` alone leaves yesterday's system under today's kernel, looking for modules that are not there.
- Identical sets are stored once because most snapshots share theirs: between two boots the kernel rarely changes, and a copy for each would spend gigabytes, and the time to write them, on saying the same thing sixty times.
- A snapshot is read only because nothing ever boots one. Writing to a snapshot is what makes sense when a system is started from it and carried on from there, and this policy restores instead, so there is nothing left for writing to be for.
- Restoring cannot be undone because keeping a way back would mean keeping the state being left behind, and that state is exactly what the operator is choosing to discard. Restoring one snapshot and then another is how a mistaken choice is answered, not an undo.
- Restores run from the recovery system because what is being replaced is in use while the machine runs: a session holds files open, and processes go on reading and writing what the restore is swapping underneath them, which for a lock held over a replaced file has no good answer. Started from recovery, the installed system is not running and nothing holds anything.

## Considerations

- What a snapshot is called is not decided here. The name has to carry the justification a manual snapshot requires, and beyond that its form belongs to the tools that create and list them.
- Snapshot storage must remain separated by domain inside `/snapshots`: `system` for system snapshots and `home/<work-context>` for each work context's.
- `/boot` is outside Btrfs, so its content is copied rather than snapshotted, and what pairs a copy with a snapshot is the table rather than the filesystem.
