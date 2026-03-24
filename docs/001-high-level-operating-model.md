# 001: High-Level Operating Model

## Context and Decision

This repository defines a system used by one physical person across multiple machines and multiple login contexts. The installation model is interactive and role-aware, and it avoids coupling behavior to a single personal username.

The operating model is single-person, multi-account. Login users can represent separate work contexts for the same person, while non-login service users can be used to run restricted background processes. Active shared configuration is centralized at `/dotfiles` so all intended login users consume the same source of configuration. Active shared configuration is centralized at `/dotfiles` so all intended login users consume the same source of configuration.

The installer repository is persisted separately at `/oparch`. This keeps installation logic and decision documents independent from active runtime configuration.

### Machine Roles

- `Main PC`: primary machine with full setup and a role-specific GRUB configuration.
- `Laptop`: travel machine with full setup and a GRUB configuration variant adapted to laptop constraints.
- Future role (not active yet): server profile without a graphical stack.

## Why

- The system is modeled as single-person multi-account because account separation is used to isolate work contexts (sessions, cookies, app state), not to separate different human owners; if treated as a multi-person system, policy and UX would add unnecessary friction for the actual usage model.
- Explicit machine roles (`Main PC`, `Laptop`, future server) are required because hardware and boot constraints differ by machine; if role awareness is removed, one profile would either misconfigure some machines or force repeated manual fixes.
- Interactive installation is required because user list and role-specific options are machine-time inputs; if fully static, the installer would produce wrong identities or wrong optional components on some targets.
- Avoiding hardcoded personal usernames is required because login-user names are inputs and can change over time; if usernames are hardcoded, provisioning and link logic break when names differ.
- Centralizing shared configuration at `/dotfiles` is required because the same person uses multiple login users and some managed config targets are system paths (for example `/etc`); if configuration is anchored to one home, cross-user linking and system-level config management become fragile.
- Keeping installer sources at `/oparch` is required because installation logic must remain inspectable after deployment without coupling it to runtime config layout; if installer files are mixed into active config paths, maintenance and troubleshooting scopes become harder to separate.

## Implementation Plan

1. Keep high-level policy decisions in `docs/`.
2. Ask for machine role early in the installer flow.
3. Apply role-specific branches only where needed (for example, GRUB behavior).
4. Keep shared-dotfiles implementation in `003-shared-dotfiles-model.md`.
5. Persist the installer repository at `/oparch`.

## Considerations

- Scripts must not hardcode personal usernames.
- Role branching should be explicit and minimal.
- Prompts should request only data that affects behavior.
