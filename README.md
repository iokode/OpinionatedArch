# OpinionatedArch

OpinionatedArch is an Arch-based system for one physical person who wants multiple work contexts without maintaining separate system configurations for each login account.

For a longer introduction, read [Introducing OpinionatedArch](https://iokode.blog/posts/opinionated-arch/).

## Status

OpinionatedArch is in a very early stage. The repository defines the operating model, installation direction, documentation, and early tooling, but it is not a finished general-purpose distribution.

## Operating Model

Login accounts are work contexts for the same person, not different people. Shared configuration lives at `/dotfiles`, outside every home directory. Encryption is mandatory, snapshots are automatic, and recovery is restore-based.

OpinionatedArch is opinionated about the operating model, disk layout, encryption, snapshots, recovery, dotfiles, and maintenance invariants. It does not try to decide the desktop environment, window manager, shell workflow, or day-to-day user interface.

See [Operating Model](docs/general/001-operating-model.md) for the full description.

## Installation

1. Boot an Arch Linux live environment (archiso).
2. Clone or copy this repository into that environment.
3. From the repository root, run:

```bash
./installer/install.sh
```

4. Answer the interactive prompts.

See [Installation Overview](docs/general/002-installation-overview.md) for what the installer asks and what it does.

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
- `docs/`: project documentation

## Documentation

Documentation lives in [`docs/`](docs/README.md), organized by type:

- [General](docs/general/) — what OpinionatedArch is and how it works
- [Decisions](docs/decisions/) — one decision per document, with its reasoning
- [Specifications](docs/specs/) — normative formats and protocols
- [Tools](docs/tools/) — one document per `oparch-` command
