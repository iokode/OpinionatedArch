# OpinionatedArch

OpinionatedArch is an Arch-based system for one physical person who wants multiple work contexts without maintaining separate system configurations for each login account.

For a longer introduction, read [Introducing OpinionatedArch](https://iokode.blog/posts/opinionated-arch/).

## Status

OpinionatedArch is in a very early stage. The repository defines the operating model, installation direction, documentation, and early tooling, but it is not a finished general-purpose distribution.

## Operating Model

- the system is designed for one physical person, with multiple login accounts used as separate work contexts
- shared configuration lives at `/dotfiles`, outside every login user's home directory
- the system is designed for whole-disk installation, not installation beside another operating system on the same disk
- system snapshots are created at boot and on package install/update operations, and home snapshots are created at login
- snapshot recovery is restore-based rather than snapshot-boot-based, with recovery tooling planned around explicit restore flows
- encryption is mandatory
- the system can include a pre-boot ownership and return message on the disk-unlock screen
- the baseline kernel is `linux` only, no other kernels are supported
- the system language is fixed to English, except for the pre-boot ownership message, which may be multilingual

OpinionatedArch is opinionated about the operating model, disk layout, encryption, snapshots, recovery, dotfiles, and maintenance invariants. It does not try to decide the desktop environment, window manager, shell workflow, or day-to-day user interface.

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
├── bin/
├── installer/
├── lib/
├── assets/
└── docs/
```

- `bin/`: executable project tools
- `installer/`: installation logic
- `lib/`: shared shell library code
- `assets/`: managed project assets
- `docs/`: decision documents that define the operating model

## Documentation

- Decision documents live in `docs/`.
- Documentation conventions for those decision documents live in [`docs/README.md`](docs/README.md).
