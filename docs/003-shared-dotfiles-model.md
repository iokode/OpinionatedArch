# 003: Shared Dotfiles Model (Location and Permissions)

## Context and Decision

Dotfiles must be shared across multiple login users owned by the same physical person, without anchoring configuration to one home directory. The installer prepares `/dotfiles` as an empty shared path for a separate dotfiles repository.

This model can include system-level configuration that may live under `/etc`, so those files can be versioned in the separate dotfiles repository and linked from system paths.

Permissions are group-based on `/dotfiles` so intended login users can maintain shared configuration.

## Why

- `/dotfiles` as the shared dotfiles path is used so runtime links for all login users can resolve to one stable location once the separate dotfiles repository is installed; if runtime config is spread across user homes, links and ownership handling become brittle.
- Keeping dotfiles content out of this installer repository is required because installer assets and runtime dotfiles have different ownership and lifecycle; if mixed, installation artifacts and runtime configuration scope become confused.
- Keeping dotfiles outside any user home is required because configuration is shared across multiple login users of the same person; if stored under one home, cross-home symlinks and ownership handling become brittle.
- Keeping dotfiles outside any user home also enables versioning of non-secret system configuration linked into `/etc`; if dotfiles are home-anchored, system-level config management depends on one user path and becomes harder to maintain safely.
- Group-based permissions on `/dotfiles` are used because intended login users need collaborative write access while service users should remain restricted by default; if permissions are not group-scoped, the result is either unsafe broad write access or unusable root-only maintenance.

## Implementation Plan

1. Create `/dotfiles` in the installed system.
2. Keep `/dotfiles` empty in this installer phase.
3. Create the `dotfiles` group if missing.
4. Add intended login users to `dotfiles`.
5. Set ownership to `root:dotfiles` and mode `2775` on `/dotfiles`.
6. Apply default ACL inheritance for `dotfiles` group write access.
7. Defer dotfiles content population and linking to the separate dotfiles repository workflow.
8. Grant service users read-only access only when explicitly required.

## Considerations

- Never create links from one login home to another login home.
- Avoid world-writable permissions on `/dotfiles`.
- Keep shared-permission changes auditable.
- Non-secret `/etc` configuration can be versioned in the dotfiles repository and linked into `/etc`.
- Secrets and private keys must not be stored in clear text inside the managed dotfiles tree.
