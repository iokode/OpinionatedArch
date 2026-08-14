# Disk Layout

## Context

Manual partitioning is out of scope for this project phase.

## Decision

The installer uses the full target disk with a deterministic layout.

The disk uses a GPT partition table. The partition layout is:

- 1 GiB FAT32 EFI system partition labeled `EFI`.
- Remaining disk space as one LUKS2 encrypted container labeled `OpinionatedArch`, containing one Btrfs filesystem.

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
- `home/@<work-context>` is one dedicated home subvolume per work context.
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

Mount configuration is persisted in fstab.

Btrfs mount options are not customized in this phase. The installer uses Btrfs default mount behavior and does not set explicit tuning options such as `compress`, `noatime`, `ssd`, or per-subvolume mount overrides.

The installer supports two install modes: `wipe-all` and `keep-homes`.

In `wipe-all` mode, the selected disk is repartitioned and all previous data on that disk is destroyed.

In `keep-homes` mode, the system is reinstalled while preserving selected existing `home/@<work-context>` subvolumes. The installer asks which of the existing homes to preserve, recreates those work contexts with the homes they had, and also creates any further context named in the work contexts step.

Snapshot paths under `/snapshots/system` and `/snapshots/home/<login-user>` are initialized when the corresponding subvolumes are provisioned.

## Why

- Full-disk deterministic partitioning is used because it is the easiest way to force the GPT layout and create the partitions required by the installer. Writing an installer that reuses existing partitions while maintaining invariants is not trivial.
- `keep-homes` is used because system reinstall can preserve selected user home data while rebuilding the rest of the system.
- EFI plus one encrypted Btrfs partition is used because the boot artifacts that must remain available to firmware stay on the EFI system partition, while operating-system state, user data, snapshots, dotfiles, logs, package cache, and swap remain inside one encrypted filesystem.
- There is no relevant swap performance difference between swapfiles and swap partitions on modern SSDs, so using swapfiles is simpler than creating a swap partition.
- The EFI layout keeps project-owned boot artifacts under `EFI/OpinionatedArch` and `OpinionatedArch` so they do not mix with third-party or vendor-owned EFI directories.
- `@` is isolated because system rollback needs a root-state boundary that excludes recovery state, user homes, snapshots, logs, package cache, dotfiles, and swap.
- `@recovery` is isolated because it is its own root and bootable system, and recovery must remain available independently from normal root rollback or normal root failure.
- `home/@<login-user>` isolates login-user data and allows per-user rollback without touching other users; if omitted, one rollback operation can revert unrelated user data.
- `@snapshots` is a dedicated container because all snapshot data must live under one mounted path while preserving separate system and home snapshot scopes.
- `@log` keeps logs out of root-state rollback scope because logs are high-churn operational data; if logs stay in `@`, snapshot diffs and retention are dominated by log noise instead of meaningful system-state changes.
- `@pkg` keeps package cache out of root-state rollback scope because cache lifecycle is not configuration state; if cache is inside `@`, snapshots capture irrelevant cache churn and waste snapshot space/history.
- `@dotfiles` has its own subvolume so dotfiles are not affected by system snapshots. Restore is managed directly through Git because this subvolume is also a Git repository.
- `@swap` is separate because persistent swapfiles must stay outside root snapshots and must be mounted with specific properties.

## Considerations

- Do not add extra partitions or subvolumes
- There is no swap partition. Persistent disk swap lives inside the Btrfs `@swap` subvolume as zero or more swapfiles, as defined in `002-swap-strategy.md`.
- Snapshot policy must remain compatible with the selected mount layout.
- User provisioning must include home-subvolume creation and per-user snapshot-path creation for install-time and post-install users.
- `keep-homes` preserves only the selected existing login-user home subvolumes.
- Future Btrfs tuning remains possible only after a concrete performance or reliability issue is identified.
