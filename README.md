# OpinionatedArch

OpinionatedArch is an Arch-based system for one physical person who wants multiple work contexts without maintaining separate system configurations for each login account.

For a longer introduction, read [Introducing OpinionatedArch](https://iokode.blog/posts/opinionated-arch/).

## Status

OpinionatedArch is in a very early stage, and not a finished general-purpose distribution.

How far along it is stays out of this file, because it moves: [What Is Built](docs/state/000-what-is-built.md) says what the project has, and [Remaining](docs/state/001-remaining.md) what it has not.

## Operating Model

Login accounts are work contexts for the same person, not different people. Shared configuration lives at `/dotfiles`, outside every home directory.

OpinionatedArch is opinionated about the operating model, disk layout, encryption, snapshots, recovery, dotfiles, and maintenance invariants. It does not try to decide the desktop environment, window manager, shell workflow, or day-to-day user interface.

See [Operating Model](docs/general/001-operating-model.md) for the full description.

## Installation

The system is installed by `oparch-installer`, run from an Arch Linux live environment. It asks for everything it needs on screen, or takes the same answers from a file with `--config`, and produces a reboot-ready system in one run.

There is no medium to boot yet. The ISO that will carry the installer and its assets is built with `archiso` and is the last thing this project builds, so today the installer is built from this repository and put on a live environment by hand.

See [Installation Overview](docs/general/002-installation-overview.md) for what it asks and what it does, and [oparch-installer](docs/tools/oparch-installer/000-command.md) for the command itself.

## Repository layout

```text
├── src/
├── tests/
├── assets/
└── docs/
```

- `src/`: one directory per tool, and the code they share
- `tests/`: the end-to-end harness; the unit tests live with the code they test
- `assets/`: managed project assets
- `docs/`: project documentation

Why the sources and the tests are laid out this way is [Repository Layout](docs/development/002-repository-layout.md).

## Documentation

Documentation lives in [`docs/`](docs/INDEX.md), organized by type. The [Index](docs/INDEX.md) lists every document; [Document Types](docs/README.md) defines what a document may be and the shape each type takes.

- [General](docs/general/) — what OpinionatedArch is and how it works
- [Decisions](docs/decisions/) — one decision per document, with its reasoning
- [Tools](docs/tools/) — one document per `oparch-` command, with the formats it defines
- [Development](docs/development/) — how the project itself is built and tested
- [Plans](docs/plans/) — work that is going to be done, and in what order
- [State](docs/state/) — [what is built](docs/state/000-what-is-built.md) and [what remains](docs/state/001-remaining.md)

