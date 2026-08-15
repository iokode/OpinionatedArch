# Disk Layout

## Context

The system is installed onto the disk of a machine, and everything it needs afterwards has to fit there: a root that is encrypted, a recovery system that stays available when that root will not start, snapshots whose scope is the system or one work context, and the boot artifacts the firmware has to read before any of it is decrypted.

## Decision

OpinionatedArch takes the whole of the target disk and lays it out the same way every time. There is no manual partitioning and no way to install onto a layout someone else made.

The disk uses a GPT partition table with two partitions: the EFI system partition, and one encrypted container holding everything else.

Mount configuration is persisted in fstab.

### The EFI system partition

1 GiB, FAT32, labeled `EFI`, and mounted at `/boot`.

It contains project-owned boot artifacts plus any unrelated third-party EFI artifacts that already exist or are installed by other operating systems. OpinionatedArch owns only these paths:

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

### The encrypted partition

The remaining disk space is one LUKS2 encrypted container labeled `OpinionatedArch`, containing one Btrfs filesystem.

A name beginning with `@` is a subvolume, and a name without it is an ordinary directory. The Btrfs filesystem holds these subvolumes:

- `@` is the normal system root subvolume.
- `@recovery` is a separate recovery root subvolume. It is not part of the normal system.
- `home/@<work-context>` is one dedicated home subvolume per work context, inside the `home` directory.
- `@snapshots` is the snapshot-storage subvolume. The snapshots inside it are subvolumes too, at these paths:
  - `@snapshots/system/{automatic,manual}` holds the automatic and manual snapshots of the `@` subvolume.
  - `@snapshots/home/<work-context>/{automatic,manual}` holds the automatic and manual snapshots of each `home/@<work-context>` subvolume.
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

Mount points:

- `@` is mounted at `/`.
- `home/@<work-context>` subvolumes are mounted at `/home/<work-context>`.
- `@snapshots` is mounted at `/snapshots`.
- `@log` is mounted at `/var/log`.
- `@pkg` is mounted at `/var/cache/pacman/pkg`.
- `@dotfiles` is mounted at `/dotfiles`.
- `@swap` is mounted at `/swap`.

Btrfs mount options are not customized. The layout uses Btrfs default mount behavior and sets no explicit tuning options such as `compress`, `noatime`, `ssd`, or per-subvolume mount overrides.

Snapshot paths under `/snapshots/system` and `/snapshots/home/<work-context>` are initialized when the corresponding subvolumes are provisioned.

## Why

- Full-disk deterministic partitioning is used because it is the easiest way to force the GPT layout and create the partitions required by the installer. Writing an installer that reuses existing partitions while maintaining invariants is not trivial.
- EFI plus one encrypted Btrfs partition is used because the boot artifacts that must remain available to firmware stay on the EFI system partition, while operating-system state, user data, snapshots, dotfiles, logs, package cache, and swap remain inside one encrypted filesystem.
- There is no relevant swap performance difference between swapfiles and swap partitions on modern SSDs, so using swapfiles is simpler than creating a swap partition.
- The EFI layout keeps project-owned boot artifacts under `EFI/OpinionatedArch` and `OpinionatedArch` so they do not mix with third-party or vendor-owned EFI directories.
- `@` is isolated because system rollback needs a root-state boundary that excludes recovery state, the homes of the work contexts, snapshots, logs, package cache, dotfiles, and swap.
- `@recovery` is isolated because it is its own root and bootable system, and recovery must remain available independently from normal root rollback or normal root failure.
- `home/@<work-context>` isolates the data of one work context and allows rolling it back without touching the others; if omitted, one rollback operation can revert data that belongs to another area of the operator's activity.
- `@snapshots` is a dedicated container because all snapshot data must live under one mounted path while preserving separate system and home snapshot scopes.
- `@log` keeps logs out of root-state rollback scope because logs are high-churn operational data; if logs stay in `@`, snapshot diffs and retention are dominated by log noise instead of meaningful system-state changes.
- `@pkg` keeps package cache out of root-state rollback scope because cache lifecycle is not configuration state; if cache is inside `@`, snapshots capture irrelevant cache churn and waste snapshot space/history.
- `@dotfiles` has its own subvolume so dotfiles are not affected by system snapshots. Restore is managed directly through Git because this subvolume is also a Git repository.
- `@swap` is separate because persistent swapfiles must stay outside root snapshots and must be mounted with specific properties.

## Considerations

- Do not add extra partitions or subvolumes
- There is no swap partition. Persistent disk swap lives inside the Btrfs `@swap` subvolume as zero or more swapfiles, as defined in [Swap](003-swap.md).
- Snapshot policy must remain compatible with the selected mount layout.
- Provisioning a work context must include creating its home subvolume and its snapshot paths, whether it is created during installation or later.
- Only a work context's home is a subvolume of its own. The home of any other account lives inside `@`, so it is captured by system snapshots and a rollback of `@` takes it back with the rest.
- Future Btrfs tuning remains possible only after a concrete performance or reliability issue is identified.

