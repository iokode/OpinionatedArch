# 005: Installation Blueprint

## Context and Decision

The installer must produce a reproducible system from an Arch live environment, using interactive prompts to adapt behavior by machine role and account inputs. Decision documents and implementation are kept close so the repository remains maintainable as requirements evolve.

The installed system keeps two separate paths: `/oparch` for this installer repository, and `/dotfiles` for active shared runtime configuration.

The installer flow assumes the known baseline state from a clean Arch live environment. It must not add defensive pre-existence handling for install paths that are impossible in that baseline.

## Why

- Reproducible installation from the Arch live environment is required because recovery and new-machine provisioning must produce the same baseline state; if reproducibility is weak, troubleshooting and rollback expectations become inconsistent across machines.
- Interactive prompts are required because machine role and account set are not constant across targets; if the flow is not interactive, one static path will misconfigure some machines.
- Keeping decisions and implementation close is required because this repository evolves by explicit design decisions; if docs and scripts drift apart, changes become hard to trust and harder to maintain safely.
- Separating `/oparch` from `/dotfiles` is required because installer maintenance and runtime config maintenance are different concerns; if both are mixed into one path, updates and troubleshooting cross-contaminate.
- Copying this repository into `/oparch` with `.git` is required because post-install review needs exact script sources plus history; if `.git` is missing, traceability and rollback analysis lose commit context.
- Avoiding defensive pre-existence handling is required because the installer always starts from the same clean-live baseline; if impossible-state guards are added anyway, script size and branching grow without adding real reliability, which increases maintenance cost and failure surface.

## Implementation Plan

1. Collect required user inputs at the entrypoint.
2. Execute installation and setup steps in deterministic order.
3. Copy this installer repository to `/oparch`, including `.git`.
4. Set `/oparch` ownership and permissions to `root:root`, read for all users, no execute on regular files.
5. Apply shared runtime configuration from `/dotfiles/config/`.
6. Keep decisions and scripts synchronized as changes are introduced.
7. Keep install commands baseline-linear, without "just in case" cleanup/check paths for impossible pre-existing state.

## Considerations

- Optional paths should be gated by explicit answers.
- The installer should not include defensive handling for impossible pre-existing install state in clean-live execution.
- New decisions should be documented before implementation changes.
