# 005: Installation Blueprint

## Context and Decision

The installer must produce a reproducible system from an Arch live environment, using interactive prompts for target-specific inputs.

The installer flow assumes the known baseline state from a clean Arch live environment. It must not add defensive pre-existence handling for install paths that are impossible in that baseline.

## Why

- Installation starts from the Arch live environment because archiso provides the tools used by the OpinionatedArch installer and recovery scripts.
- Interactive prompts are used because answering prompts is easier for the user than preparing a configuration file.
- Avoiding defensive pre-existence handling is required because the installer always starts from the same clean-live baseline; if impossible-state guards are added anyway, script size and branching grow without adding real reliability, which increases maintenance cost and failure surface.

## Implementation Plan

1. Collect installer input.
2. Prepare target disk and mount points.
3. Install base system.
4. Generate system configuration required for first boot.
5. Run chroot configuration.
6. Finalize installation to reboot-ready state.

## Considerations

- Optional paths should be gated by explicit answers.
- The installer should not include defensive handling for impossible pre-existing install state in clean-live execution.
- New decisions should be documented before implementation changes.
