# 009: Partitioning Strategy

## Context and Decision

The installer is designed to use the full target disk with a deterministic partition layout. Manual partitioning is out of scope for this project phase.

The selected disk layout is:

- EFI partition: stores GRUB and the Arch netboot/live EFI entry.
- Swap partition: size is provided interactively in GB at install time.
- Btrfs partition: uses the remaining disk space.

The installer supports only a destructive `wipe-all` mode for now. A partial reinstall mode that keeps existing home subvolumes (`keep-homes`) is explicitly deferred.

## Why

- Full-disk deterministic partitioning is used because this installer prioritizes predictable behavior over partition-layout flexibility; if multiple layout branches are supported early, validation and failure handling become harder to trust.
- EFI + swap + Btrfs is used because it matches the already decided boot, swap, and subvolume model in a single consistent disk plan; if the disk model diverges from those decisions, later scripts must handle conflicting assumptions.
- Swap size is asked interactively because hardware capacity and workload vary per machine; if hardcoded, swap can be wrong for the real target.
- `keep-homes` is deferred because preserving existing homes requires complex discovery and safety logic (unknown extra partitions, multiple swap devices, pre-existing Btrfs layouts, identity mapping, rollback coupling); if implemented now, complexity and error surface would rise sharply and conflict with the project's simplicity goal.
- A destructive `wipe-all` mode is kept as the only install path because one clear path is easier to verify end-to-end; if partial-preserve branches are added too early, installer reliability drops.

## Implementation Plan

1. Ask for target disk and require explicit destructive confirmation.
2. Ask for swap partition size in GB.
3. Wipe partition table on the selected disk.
4. Create GPT with EFI, swap, and Btrfs partitions.
5. Continue installation flow on top of this fixed partition layout.

## Considerations

- `keep-homes` may be added later only with strict preconditions and explicit abort rules when layout checks fail.
- Any data preservation requirement must be handled as backup/restore outside this installer mode.
