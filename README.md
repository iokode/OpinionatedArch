# OpinionatedArch

OpinionatedArch is an Arch-based system for one physical person who wants multiple work contexts without maintaining a separate system configuration for each.

## Status

OpinionatedArch is in a very early stage, and not a finished general-purpose distribution.

How far along it is stays out of this file, because it moves: [What Is Built](docs/state/000-what-is-built.md) says what the project has, and [Remaining](docs/state/001-remaining.md) what it has not.

## Why It Exists

Arch decides almost nothing, and it offers no method for what comes after. A machine built on it is whatever its owner chose on whichever day they chose it, maintained by hand and from memory, differently each time.

It exists **to supply that method**: the choices Arch leaves to you are taken once and written down, and there is a way of working that keeps them true as the machine changes. What that buys is a machine you can still account for a year later.

It is also what makes work contexts affordable. Separating personal use from client work is what accounts are for, and on a hand-maintained machine every account is one more to configure and keep in step with the others. Under one method the configuration is already there, so a context costs an account and nothing else.

See [What is OpinionatedArch](docs/general/000-what-is-opinionatedarch.md) for more.

## Installation

There is no medium to boot yet, eventually, there will be an ISO.

The system is installed by running `oparch-installer`, from an Arch Linux live environment.

See [Installation Overview](docs/general/002-installation-overview.md) for what it asks and what it does, and [oparch-installer](docs/tools/oparch-installer/000-command.md) for the installer tool itself.

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

