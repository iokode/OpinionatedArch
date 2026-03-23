# OpinionatedArch Installer

This repository is the source of truth for a full Arch Linux setup driven from a live environment. The final target machine keeps this repository at `/oparch`, while active shared runtime configuration lives at `/dotfiles`; the installer applies configuration mainly through symbolic links.

## Repository layout

```text
├── scripts/
├── config/
└── docs/
```

- `scripts/`: executable logic for installation and setup.
- `config/`: managed configuration files linked into user and system targets.
- `docs/`: decision documents.

## Usage

1. Boot the Arch Linux live environment.
2. Run the installer entrypoint.
3. Answer the interactive prompts.

That is the full user workflow.

## Document Structure

Decision documents use this section order:

1. Context and Decision
2. Why
3. Implementation Plan
4. Considerations
5. Critical Notes With Replies (Copy of Discussion)
