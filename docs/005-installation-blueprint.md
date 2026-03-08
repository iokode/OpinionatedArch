# 005: Installation Blueprint

## Context and Decision

The installer must produce a reproducible system from an Arch live environment, using interactive prompts to adapt behavior by machine role and account inputs. Decision documents and implementation are kept close so the repository remains maintainable as requirements evolve.

## Why

- Reproducible installation from the Arch live environment is required because recovery and new-machine provisioning must produce the same baseline state; if reproducibility is weak, troubleshooting and rollback expectations become inconsistent across machines.
- Interactive prompts are required because machine role and account set are not constant across targets; if the flow is not interactive, one static path will misconfigure some machines.
- Keeping decisions and implementation close is required because this repository evolves by explicit design decisions; if docs and scripts drift apart, changes become hard to trust and harder to maintain safely.

## Implementation Plan

1. Collect required user inputs at the entrypoint.
2. Execute installation and setup steps in deterministic order.
3. Apply shared configuration from `/dotfiles/config/`.
4. Keep decisions and scripts synchronized as changes are introduced.

## Considerations

- Optional paths should be gated by explicit answers.
- The installer should favor idempotent operations where possible.
- New decisions should be documented before implementation changes.
