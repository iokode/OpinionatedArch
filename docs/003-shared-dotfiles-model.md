# 003: Shared Dotfiles Model (Location and Permissions)

## Context and Decision

Dotfiles must be shared across multiple login users owned by the same physical person, without anchoring configuration to one home directory. The directory `/dotfiles` is the exact repository checkout, and managed configuration files are stored under `/dotfiles/config/...` inside that repository.

This model also includes system-level configuration that may live under `/etc`, so those files can be versioned in the same repository and linked from system paths.

Permissions are group-based: `/dotfiles` is owned by `root:dotfiles`, login users are members of the `dotfiles` group, and group write behavior is enforced with setgid and default ACLs.

## Why

- `/dotfiles` as the repository root is used so runtime path and repository path are identical from every login context; if they diverge, link targets and automation become environment-dependent and fragile.
- `/dotfiles/config/...` is used because managed configuration must stay inside the tracked repository tree; if config files live outside it, changes stop being versioned consistently and reproducibility is lost.
- Keeping dotfiles outside any user home is required because configuration is shared across multiple login users of the same person; if stored under one home, cross-home symlinks and ownership handling become brittle.
- Keeping dotfiles outside any user home also enables versioning of non-secret system configuration linked into `/etc`; if dotfiles are home-anchored, system-level config management depends on one user path and becomes harder to maintain safely.
- Group-based permissions are used because intended login users need collaborative write access while service users should remain restricted by default; if permissions are not group-scoped, the result is either unsafe broad write access or unusable root-only maintenance.

## Implementation Plan

1. Create `/dotfiles` in the installed system.
2. Place repository content under `/dotfiles`.
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
- Secrets and private keys must not be stored in clear text inside the repository.
