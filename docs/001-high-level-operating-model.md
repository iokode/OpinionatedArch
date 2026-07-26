# 001: High-Level Operating Model

## Context and Decision

This repository defines a system used by one physical person across multiple login contexts. The installation model is interactive and avoids coupling behavior to a single personal username.

The operating model is single-person, multi-account. Login users can represent separate work contexts for the same person, while non-login service users can be used to run restricted background processes. Active shared configuration is centralized at `/dotfiles` so all intended login users consume the same source of configuration.

## Why

- The system is modeled as single-person multi-account because account separation is used to isolate work contexts, not to separate different human owners.
- Shared configuration is centralized at `/dotfiles` because multiple login users consume the same runtime configuration source, including system-level configuration targets.

## Implementation Plan

1. Keep high-level policy decisions in `docs/`.
2. Keep shared-dotfiles implementation in `003-dotfiles-sync.md`.

## Considerations

- Scripts must not hardcode personal usernames.
- Prompts should request only data that affects behavior.