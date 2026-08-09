# User Model and Account Types

## Context

The system is designed for one physical person. Multiple Linux users may exist, but they do not represent multiple people.

## Decision

Two account types are used: logical non-login users for service isolation, and login users for interactive work contexts.

The installer asks for the complete list of login user names. Logical users are not prompted and are always created by baseline policy.

Two explicit groups are used:

- `dotfiles`: grants access to shared dotfiles according to the dotfiles policy.
- `login-users`: marks accounts intended for interactive login.

As specified in `002-disk-layout.md`, each login user home is a dedicated subvolume. This applies both during initial installation and when adding a new login user later on an already installed system.

Authentication is unified: the installer asks one password and uses it both for disk encryption and for all login users.

Login users have passwordless sudo.

The `root` account has no password set and is not intended for interactive login.

## Why

- Two account types (`logical` and `login`) are required because service accounts need restricted execution identities that are not interactive human login accounts.
- `dotfiles` and `login-users` are separate groups because dotfiles access and interactive login identity are different permissions. For example, a keymapper service may need to read configuration from `/dotfiles` without being an interactive login account.
- A unified password for disk encryption and login users is used because the system is operated by one person, so multiple login passwords are unnecessary.
- Root is passwordless and non-interactive because privileged operations are performed through sudo from login users.
- Passwordless sudo is used because the user has already unlocked the disk and logged in, and this model has one physical operator who owns administrative privileges.

## Considerations

- The shared login password and disk-encryption password are the same by design.
- `dotfiles` and `login-users` groups must be kept explicit and consistent for every login user.
- Login users have passwordless sudo by design.
- Root remains non-interactive and passwordless by design.
- Root recovery procedures must be documented and available.
- Login usernames should be validated before creation.
- Logical users must not be enabled for interactive login unless explicitly requested.
- Login users should not be created through raw `useradd` flows that bypass the provisioning model defined in `002-disk-layout.md`.

## Critical Notes With Replies (Copy of Discussion)

1. Assistant critique: a single shared password is a single point of compromise because one secret unlocks both encrypted storage and all login users.
   Reply: one strong memorized secret is preferred over multiple secrets that would likely be written down and leaked more easily.
2. Assistant critique: username-only post-boot login weakens local-session security because there is no second authentication step after disk unlock.
   Reply: local-session protection is enforced with lockscreen policy (for example `hyprlock`) so unattended sessions still require password unlock, and username-only mode is only enabled when supported by the selected session manager.
3. Assistant critique: shared credentials reduce account-level separation because credentials no longer differentiate interactive users.
   Reply: account separation is for session context (for example cookie/session isolation), not for different physical users.
4. Assistant critique: passwordless root requires robust recovery flow because direct root login cannot be used as a fallback path.
   Reply: all login users are sudoers; if sudo breaks, recovery is expected from live-environment chroot.
5. Assistant critique: a custom username-only session manager may become fragile because authentication stack and edge cases are easy to mis-handle outside mature components.
   Reply: initial implementation may use a standard password-based session manager, and later this implies developing a custom session manager specifically designed for username-only login.
6. Assistant critique: a single `@home` snapshot model is simpler but can cause cross-user rollback side effects.
   Reply: each login user gets a dedicated home subvolume so snapshot and rollback scope remains per user.
