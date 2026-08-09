# Oparch Tools

## Context

OpinionatedArch operational tools are small commands for recurring system operations.

## Decision

This document defines the common policy for those tools; it does not enumerate the tool inventory.

Tool-specific documents live in `docs/tools/`. Each tool has one Markdown document named after the command, prefixed by its number: `docs/tools/<number>-<tool-name>.md`. That file defines the concrete tool description, reason for existence, input parameters, and interactive usage when applicable.

Tool names use the `oparch-{entity}-{action}` format. The `entity` identifies the system object or operational domain managed by the tool. The `action` identifies the operation performed on that entity.

Command-line tools own behavior and perform the actual operation. Interactive tools are interfaces only: they browse choices, filter lists, ask for confirmation, collect input, and then call the matching command-line tool with explicit parameters.

Interactive tools are composed by combining `fzf` and `gum` unless a specific need requires another approach. Tools are written in `sh` unless a specific need requires another language.

## Why

- The `oparch-{entity}-{action}` naming format is required so commands remain discoverable and script-friendly; if naming varies by tool, operators must memorize exceptions.
- Separating command-line behavior from interactive selection is required so every operation remains scriptable and testable; if interactive tools perform actions directly, behavior becomes duplicated and harder to verify.
- `fzf` and `gum` are used because they combine easily with `sh` and provide a simple way to create interactive interfaces in `sh`.
- Defaulting tools to `sh` is required to keep runtime dependencies minimal in the installed system.

## Considerations

- Do not duplicate the concrete tool inventory in this document.
- Do not put filesystem changes, account changes, snapshot operations, or other system mutations in interactive tools.
- Do not introduce a different interactive stack unless the tool requirement cannot be met with `fzf` and `gum`.
- Do not introduce a different implementation language unless the tool requirement cannot be met with `sh`.
- Keep exceptions explicit in the affected tool document.
