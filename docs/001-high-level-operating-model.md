# 001: High-Level Operating Model

## Context and Decision

This repository defines a system used by one physical person across multiple login contexts. The installation model is interactive and avoids coupling behavior to a single personal username.

The operating model is single-person, multi-account. Login users can represent separate work contexts for the same person, while non-login service users can be used to run restricted background processes. Active shared configuration is centralized at `/dotfiles` so all intended login users consume the same source of configuration. Active shared configuration is centralized at `/dotfiles` so all intended login users consume the same source of configuration.

The installer repository is persisted separately at `/usr/opinionatedarch`. This keeps installation logic and decision documents independent from active runtime configuration.

## Why

- The system is modeled as single-person multi-account because account separation is used to isolate work contexts (sessions, cookies, app state), not to separate different human owners; if treated as a multi-person system, policy and UX would add unnecessary friction for the actual usage model.
- Interactive installation is required because user list and installation-time inputs can vary by target; if fully static, the installer would produce wrong identities or wrong target-specific configuration on some machines.
- Avoiding hardcoded personal usernames is required because login-user names are inputs and can change over time; if usernames are hardcoded, provisioning and link logic break when names differ.
- Centralizing shared configuration at `/dotfiles` is required because the same person uses multiple login users and some managed config targets are system paths (for example `/etc`); if configuration is anchored to one home, cross-user linking and system-level config management become fragile.
- Keeping installer sources at `/usr/opinionatedarch` is required because installation logic must remain inspectable after deployment without coupling it to runtime config layout; if installer files are mixed into active config paths, maintenance and troubleshooting scopes become harder to separate.

## Implementation Plan

1. Keep high-level policy decisions in `docs/`.
2. Keep shared-dotfiles implementation in `003-shared-dotfiles-model.md`.
3. Persist the installer repository at `/usr/opinionatedarch`.

## Considerations

- Scripts must not hardcode personal usernames.
- Prompts should request only data that affects behavior.
