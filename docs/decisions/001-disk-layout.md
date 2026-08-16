# Disk Layout

## Context

The system is installed onto the disk of a machine, and everything it needs afterwards has to fit there: a root that is encrypted, a recovery system that stays available when that root will not start and when what holds it will not open, snapshots whose scope is the system or one work context, and the boot artifacts the firmware has to read before any of it is decrypted.

## Decision

OpinionatedArch takes the whole of the target disk and lays it out the same way every time. There is no manual partitioning and no way to install onto a layout someone else made.

The disk uses a GPT partition table with three partitions: the EFI system partition, the recovery partition, and one encrypted container holding everything else.

Mount configuration is persisted in fstab.

### The EFI system partition

1 GiB, FAT32, labeled `EFI`, and mounted at `/boot`.

It contains project-owned boot artifacts plus any unrelated third-party EFI artifacts that already exist or are installed by other operating systems. OpinionatedArch owns only these paths:

- `EFI/OpinionatedArch/recovery.efi`
- `EFI/OpinionatedArch/grubx64.efi`
- `EFI/OpinionatedArch/netbootx64.efi`
- `OpinionatedArch/grub/`, where GRUB reads its own files from
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
│       ├── grubx64.efi
│       └── netbootx64.efi
└── OpinionatedArch/
    ├── grub/
    │   ├── fonts/
    │   ├── locale/
    │   ├── x86_64-efi/
    │   ├── grubenv
    │   ├── grub.cfg
    │   └── oparch.cfg
    ├── initramfs-linux.img
    ├── vmlinuz-linux
    └── amd-ucode.img
```

### The recovery partition

4 GiB, ext4, labeled `RECOVERY`, holding the recovery system: an Arch installation of its own, started in place of the installed system rather than beside it.

It is not encrypted and the installed system does not mount it. What recovery is and what it has to be able to do is [Recovery](012-recovery.md).

### The encrypted partition

The remaining disk space is one LUKS2 encrypted container labeled `OpinionatedArch`, containing one Btrfs filesystem.

A name beginning with `@` is a subvolume, and a name without it is an ordinary directory. The Btrfs filesystem holds these subvolumes:

- `@` is the normal system root subvolume.
- `home/@<work-context>` is one dedicated home subvolume per work context, inside the `home` directory.
- `@snapshots` is the snapshot-storage subvolume. The snapshots inside it are subvolumes too, at these paths:
  - `@snapshots/system/{automatic,manual}` holds the automatic and manual snapshots of the `@` subvolume.
  - `@snapshots/home/<work-context>/{automatic,manual}` holds the automatic and manual snapshots of each `home/@<work-context>` subvolume.
  - `@snapshots/boot` holds one directory per distinct set of boot artifacts, named by the hash of its contents, and the table that pairs each system snapshot with the set that belongs to it, as [Snapshots](004-snapshots.md) decides. These are files rather than subvolumes: what they copy lives on the EFI system partition, outside Btrfs.
- `@log` stores system logs.
- `@pkg` stores the pacman package cache.
- `@dotfiles` stores shared dotfiles.
- `@swap` stores persistent swapfiles.

Example Btrfs subvolume layout:

```text
Btrfs top-level id=5
├── @
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
│   ├── home
│   │   ├── personal
│   │   │   ├── automatic
│   │   │   │   └── @1778761600
│   │   │   └── manual
│   │   │       └── @1778765200-before-photo-library-cleanup
│   │   │
│   │   ├── work
│   │   │   ├── automatic
│   │   │   │   └── @1778761500
│   │   │   └── manual
│   │   │       └── @1778765100-before-client-project-import
│   │   │
│   │   └── iokode
│   │       ├── automatic
│   │       │   └── @1778761800
│   │       └── manual
│   │           └── @1778765400-before-blog-redesign
│   │
│   └── boot
│       ├── table
│       ├── 2c6d281a7198da35893e6b5bfcb1fc2d3499169c27055adc47430645652f2050
│       │   ├── vmlinuz-linux
│       │   ├── initramfs-linux.img
│       │   └── amd-ucode.img
│       └── 2d07898b568b0949d5863b8d4949b3f2d505c9c36e80426d72897a66c41f46be
│           ├── vmlinuz-linux
│           ├── initramfs-linux.img
│           └── amd-ucode.img
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

- Full-disk deterministic partitioning is used because the alternative is a hard program to write and to keep correct: an installer that fits this layout into the partitioning someone else left, while keeping every invariant the layout promises.
- The three partitions each hold what has to survive something the others do not: the boot artifacts the firmware reads before anything is decrypted, the recovery system that has to start when the container does not open, and operating-system state, work-context data, snapshots, dotfiles, logs, package cache and swap, which stay inside one encrypted filesystem.
- There is no relevant swap performance difference between swapfiles and swap partitions on modern SSDs, so using swapfiles is simpler than creating a swap partition.
- The EFI layout keeps project-owned boot artifacts under `EFI/OpinionatedArch` and `OpinionatedArch` so they do not mix with third-party or vendor-owned EFI directories.
- `@` is isolated because system rollback needs a root-state boundary that excludes the homes of the work contexts, snapshots, logs, package cache, dotfiles, and swap.
- The recovery system is a partition of its own, outside the container, because it has to survive what it recovers from. As a subvolume it shared one Btrfs filesystem and one LUKS header with the system it exists to repair, so a damaged filesystem or a damaged header took both at once, and a forgotten passphrase left nothing to start. Outside, neither failure reaches it and it boots without the secret.
- The recovery partition is ext4 because it holds one root that is never snapshotted and never rolled back, so subvolumes would buy nothing and a simpler filesystem is one less thing to go wrong on the disk that is meant to still work.
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
- The recovery partition is not encrypted, so nothing that has to stay secret can be kept on it.
- Future Btrfs tuning remains possible only after a concrete performance or reliability issue is identified.

