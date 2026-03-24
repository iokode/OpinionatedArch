# OpinionatedArch Installer

This repository is the source of truth for a full Arch Linux setup driven from a live environment. The final target machine keeps this repository at `/oparch`, while active shared runtime configuration lives at `/dotfiles`; the installer applies configuration mainly through symbolic links.

## Repository layout

```text
├── installer/
├── assets/
└── docs/
```

- `installer/`: executable logic for installation and setup.
- `assets/`: managed assets copied or linked into system target.
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
