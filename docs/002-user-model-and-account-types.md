# 002: User Model and Account Types

## Context and Decision

The system is designed for one physical person. Multiple Linux users may exist, but they do not represent multiple people. Two account types are used: logical non-login users for service isolation, and login users for interactive work contexts.

The installer asks for the complete list of login user names. Logical users are not prompted and are always created by baseline policy.

Two explicit groups are used:

- `dotfiles`: grants access to shared dotfiles according to the dotfiles policy.
- `login-users`: marks accounts intended for interactive login.

As specified in `004-disk-layout.md`, each login user home is a dedicated subvolume. This applies both during initial installation and when adding a new login user later on an already installed system.

Authentication is unified: the installer asks one password and uses it both for disk encryption and for all login users.

Post-boot login behavior is conditional: if the selected session manager supports username-only login after disk unlock, that mode is used. If it does not support that flow, post-boot login remains username plus password until a compatible session manager is available. All login users share the same password value.

The `root` account has no password set and is not intended for interactive login.

## Why

- Two account types (`logical` and `login`) are required because service accounts must run background processes with restricted privileges and must not appear as human login identities.
- The installer asks for the full login-user list because login identities are machine-specific operational choices and cannot be inferred safely from baseline defaults.
- `dotfiles` and `login-users` are separate groups because a service account may need to read configuration from `/dotfiles` (for example, a keymapper service reading its config file) without being an interactive login account.
- Per-user rollback scope is required in this user model; as specified in `004-disk-layout.md`, this is implemented with one home subvolume per login user.
- A unified password for disk encryption and login users is used because the operator explicitly prioritizes one strong memorized secret over multiple secrets that would likely be written down.
- Conditional post-boot login behavior is required because some session managers do not support username-only login mode safely or natively.
- Root is passwordless and non-interactive because privileged operations are intended to be executed through sudo from login users, and direct root login is intentionally excluded from normal operation.

## Implementation Plan

1. Define baseline logical users in installer policy.
2. Prompt for the complete login user list.
3. Create all requested login users and add them to `login-users` and `dotfiles`.
4. Always create baseline logical users.
5. Prompt once for a shared secret and apply it to disk encryption and all login users.
6. Configure login flow according to session-manager capability: username-only when supported, otherwise username plus password.
7. Leave `root` without password and disable interactive root login.
9. Ensure each login user is provisioned according to `004-disk-layout.md` (one home subvolume per login user).
10. Provide a standard user-provisioning command/script for post-install user creation so home-subvolume and user creation remain coupled.

## Considerations

- The shared login password and disk-encryption password are the same by design.
- Post-boot login is username-only only when supported by the selected session manager.
- When username-only is not supported, post-boot login must require password.
- `dotfiles` and `login-users` groups must be kept explicit and consistent for every login user.
- Root remains non-interactive and passwordless by design.
- Root recovery procedures must be documented and available.
- Login usernames should be validated before creation.
- Logical users must not be enabled for interactive login unless explicitly requested.
- Login users should not be created through raw `useradd` flows that bypass the provisioning model defined in `004-disk-layout.md`.

## Critical Notes With Replies (Copy of Discussion)

1. Assistant critique: a single shared password is a single point of compromise because one secret unlocks both encrypted storage and all login users.
   Decision response: one strong memorized secret is preferred over multiple secrets that would likely be written down and leaked more easily.
2. Assistant critique: username-only post-boot login weakens local-session security because there is no second authentication step after disk unlock.
   Decision response: local-session protection is enforced with lockscreen policy (for example `hyprlock`) so unattended sessions still require password unlock, and username-only mode is only enabled when supported by the selected session manager.
3. Assistant critique: shared credentials reduce account-level separation because credentials no longer differentiate interactive users.
   Decision response: account separation is for session context (for example cookie/session isolation), not for different physical users.
4. Assistant critique: passwordless root requires robust recovery flow because direct root login cannot be used as a fallback path.
   Decision response: all login users are sudoers; if sudo breaks, recovery is expected from live-environment chroot.
5. Assistant critique: a custom username-only session manager may become fragile because authentication stack and edge cases are easy to mis-handle outside mature components.
   Decision response: initial implementation may use a standard password-based session manager, and later this implies developing a custom session manager specifically designed for username-only login.
6. Assistant critique: a single `@home` snapshot model is simpler but can cause cross-user rollback side effects.
   Decision response: each login user gets a dedicated home subvolume so snapshot and rollback scope remains per user.
