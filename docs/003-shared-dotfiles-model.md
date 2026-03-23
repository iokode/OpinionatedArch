# 003: Shared Dotfiles Model (Location and Permissions)

## Context and Decision

Dotfiles must be shared across multiple login users owned by the same physical person, without anchoring configuration to one home directory. The directory `/dotfiles` is the active shared configuration root, and managed configuration files are stored under `/dotfiles/config/...`.

This model also includes system-level configuration that may live under `/etc`, so those files can be versioned in the same managed dotfiles tree and linked from system paths.

Permissions are group-based on `/dotfiles` so intended login users can collaboratively maintain shared configuration.

## Why

- `/dotfiles` as the active config root is used so runtime links for all login users resolve to one stable path; if runtime config is spread across user homes, links and ownership handling become brittle.
- `/dotfiles/config/...` is used because managed configuration must stay under one shared tree consumed by all login users; if config files live outside it, runtime behavior diverges by user/session.
- Keeping dotfiles outside any user home is required because configuration is shared across multiple login users of the same person; if stored under one home, cross-home symlinks and ownership handling become brittle.
- Keeping dotfiles outside any user home also enables versioning of non-secret system configuration linked into `/etc`; if dotfiles are home-anchored, system-level config management depends on one user path and becomes harder to maintain safely.
- Group-based permissions on `/dotfiles` are used because intended login users need collaborative write access while service users should remain restricted by default; if permissions are not group-scoped, the result is either unsafe broad write access or unusable root-only maintenance.

## Implementation Plan

1. Create `/dotfiles` in the installed system.
2. Place managed runtime configuration content under `/dotfiles`.
3. Create the `dotfiles` group if missing.
4. Add intended login users to `dotfiles`.
5. Set ownership to `root:dotfiles` and mode `2775` on `/dotfiles`.
6. Apply default ACL inheritance for `dotfiles` group write access.
7. Create user configuration links from `/dotfiles/config/...`.
8. Grant service users read-only access only when explicitly required.

## Considerations

- Never create links from one login home to another login home.
- Avoid world-writable permissions on `/dotfiles`.
- Keep shared-permission changes auditable.
- Non-secret `/etc` configuration can be versioned in `/dotfiles/config` and linked into `/etc`.
- Secrets and private keys must not be stored in clear text inside the managed dotfiles tree.
