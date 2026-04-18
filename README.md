# OpinionatedArch

OpinionatedArch is a strongly opinionated Arch Linux system inspired by Omarchy.

Its documentation explains the reason behind each design decision.

## Main opinions

- the system is designed for one physical person, with multiple login accounts used as separate work contexts
- the system includes a pre-boot ownership and return message
- the storage model is fixed around `btrfs`, using the full disk without multiple partitions for other operating systems
- the storage model includes one home subvolume per login account
- system snapshots are created at boot and on package install/update operations, and home snapshots are created at login
- snapshot recovery is restore-based rather than snapshot-boot-based
- encryption is mandatory and uses `LUKS2`
- the baseline kernel is `linux` only, no other kernels are supported
- the system language is fixed to English, except for the pre-boot ownership message, which may be multilingual

## Installation

1. Boot an Arch Linux live environment (archiso).
2. Clone or copy this repository into that environment.
3. From the repository root, run:

```bash
./installer/install.sh
```

4. Answer the interactive prompts.

## Repository layout

```text
├── installer/
├── assets/
└── docs/
```

- `installer/`: installation logic
- `assets/`: managed project assets
- `docs/`: decision documents that define the operating model

## Documentation

- Decision documents live in `docs/`.
- Documentation conventions for those decision documents live in [`docs/README.md`](docs/README.md).
