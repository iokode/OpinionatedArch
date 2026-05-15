# 004: Disk Layout

## Context and Decision

The installer uses the full target disk with a deterministic layout. Manual partitioning is out of scope for this project phase.

The partition layout is:

- 1 GiB FAT32 EFI system partition labeled `EFI`.
- Remaining disk space as one LUKS2 encrypted container named `OpinionatedArch`, containing one Btrfs filesystem.

The EFI system partition contains project-owned boot artifacts plus any unrelated third-party EFI artifacts that already exist or are installed by other operating systems. OpinionatedArch owns only these paths:

- `EFI/OpinionatedArch/recovery.efi`
- `EFI/OpinionatedArch/grubx64.efi`
- `OpinionatedArch/initramfs-linux.img`
- `OpinionatedArch/vmlinuz-linux`
- `OpinionatedArch/<ucode-image>.img`, when a CPU microcode image is selected

Directories such as `EFI/Microsoft` are examples of third-party EFI executable locations and are not required by this layout. The microcode filename in the diagram is also an example; the actual file depends on the selected microcode package and may be absent when no microcode package is selected.

Example EFI system partition layout:

```text
.
├── EFI/
│   ├── Microsoft/
│   │   └── [...]
│   └── OpinionatedArch/
│       ├── recovery.efi
│       └── grubx64.efi
└── OpinionatedArch/
    ├── initramfs-linux.img
    ├── vmlinuz-linux
    └── amd-ucode.img
```

The Btrfs layout uses subvolumes as explicit snapshot and rollback boundaries:

- `@` is the normal system root subvolume.
- `@recovery` is a separate recovery root subvolume. It is not part of the normal system.
- `home` is a container for login-user home subvolumes.
- `home/@<login-user>` is one dedicated home subvolume per login user.
- `@snapshots` is the snapshot-storage subvolume.
- `@snapshots/system/{automatic,manual}` contains automatic and manual snapshots for the `@` subvolume.
- `@snapshots/home/<login-user>/{automatic,manual}` contains automatic and manual snapshots for each `home/@<login-user>` subvolume.
- `@log` stores system logs.
- `@pkg` stores the pacman package cache.
- `@dotfiles` stores shared dotfiles.
- `@swap` stores persistent swapfiles.

Example Btrfs subvolume layout:

```text
Btrfs top-level id=5
├── @
├── @recovery
│
├── home
│   ├── @personal
│   ├── @work
│   └── @iokode
│
├── @snapshots
│   ├── system
│   │   ├── automatic
│   │   │   ├── @1778761200
│   │   │   └── @1778847600
│   │   └── manual
│   │       ├── @1778764800-before-kernel-upgrade
│   │       └── @1778851200-clean-base-install
│   │
│   └── home
│       ├── personal
│       │   ├── automatic
│       │   │   └── @1778761600
│       │   └── manual
│       │       └── @1778765200-before-photo-library-cleanup
│       │
│       ├── work
│       │   ├── automatic
│       │   │   └── @1778761500
│       │   └── manual
│       │       └── @1778765100-before-client-project-import
│       │
│       └── iokode
│           ├── automatic
│           │   └── @1778761800
│           └── manual
│               └── @1778765400-before-blog-redesign
│
├── @log
├── @pkg
├── @dotfiles
└── @swap
```

Mount policy:

- The EFI system partition is mounted at `/boot`.
- `@` is mounted at `/`.
- `home/@<login-user>` subvolumes are mounted at `/home/<login-user>`.
- `@snapshots` is mounted at `/snapshots`.
- `@log` is mounted at `/var/log`.
- `@pkg` is mounted at `/var/cache/pacman/pkg`.
- `@dotfiles` is mounted at `/dotfiles`.
- `@swap` is mounted at `/swap`.

Btrfs mount options are not customized in this phase. The installer uses Btrfs default mount behavior and does not set explicit tuning options such as `compress`, `noatime`, `ssd`, or per-subvolume mount overrides.

The installer supports only a destructive `wipe-all` mode for now. A partial reinstall mode that keeps existing home subvolumes (`keep-homes`) is explicitly deferred.

## Why

- Full-disk deterministic partitioning is used because this installer prioritizes predictable behavior over partition-layout flexibility; if multiple layout branches are supported early, validation and failure handling become harder to trust.
- EFI plus one encrypted Btrfs partition is used because the boot artifacts that must remain available to firmware stay on the EFI system partition, while operating-system state, user data, snapshots, dotfiles, logs, package cache, and persistent swap remain inside one encrypted filesystem.
- Omitting a swap partition keeps the partition table fixed and avoids repartitioning for persistent swap changes; if disk swap is a partition, changing its size later requires a more invasive storage operation than changing swapfiles.
- The EFI layout keeps project-owned boot artifacts under `EFI/OpinionatedArch` and `OpinionatedArch` so they do not mix with third-party or vendor-owned EFI directories.
- `@` keeps normal operating-system root state in one rollback domain.
- `@recovery` provides a separate recovery root-state domain instead of mixing recovery state with normal boot state.
- `home/@<login-user>` isolates login-user data and allows per-user rollback without touching other users; if omitted, one rollback operation can revert unrelated user data.
- `@snapshots` stores all snapshot data in one dedicated container while separating system snapshots from home snapshots; if omitted, snapshot storage layout becomes fragmented or ambiguous.
- `@log` keeps logs out of root-state rollback scope because logs are high-churn operational data; if logs stay in `@`, snapshot diffs and retention are dominated by log noise instead of meaningful system-state changes.
- `@pkg` keeps package cache out of root-state rollback scope because cache lifecycle is not configuration state; if cache is inside `@`, snapshots capture irrelevant cache churn and waste snapshot space/history.
- `@dotfiles` gives shared dotfiles their own rollback and mount boundary; if dotfiles are kept inside `@`, system rollback and dotfile rollback cannot be controlled independently.
- `@swap` keeps persistent swapfiles outside root snapshots; if swapfiles are inside `@`, snapshots and rollback can interact with swapfile storage in undesirable ways.
- Using Btrfs mount defaults is required because no concrete issue requires tuning overrides yet; if custom options are introduced without a real problem to solve, policy becomes arbitrary and adds maintenance/debug surface without proven benefit.
- `keep-homes` is deferred because preserving existing homes requires complex discovery and safety logic; if implemented now, complexity and error surface would rise sharply and conflict with the project's simplicity goal.

## Implementation Plan

1. Ask for target disk and require explicit destructive confirmation.
2. Wipe the partition table on the selected disk.
3. Create GPT with a 1 GiB FAT32 EFI system partition and a remaining-space LUKS2 partition.
4. Open the LUKS2 container as `OpinionatedArch` and format it as Btrfs.
5. Create the selected Btrfs subvolumes.
6. Mount the EFI system partition and Btrfs subvolumes to their target mount points without custom Btrfs tuning flags.
7. Persist mount configuration in fstab.
8. Provision login-user home subvolumes under `home/@<login-user>` and initialize snapshot paths under `/snapshots/system` and `/snapshots/home/<login-user>`.

## Considerations

- Do not add extra partitions or subvolumes
- There is no swap partition. Persistent disk swap lives inside the Btrfs `@swap` subvolume as zero or more swapfiles, as defined in `006-swap-strategy.md`.
- Snapshot policy must remain compatible with the selected mount layout.
- User provisioning must include home-subvolume creation and per-user snapshot-path creation for install-time and post-install users.
- Any data preservation requirement must be handled as backup/restore outside the current installer mode.
- Future Btrfs tuning remains possible only after a concrete performance or reliability issue is identified.
