# Work Contexts and Accounts

## Context

The system is designed for one physical person. Several Linux accounts exist on it, and they do not represent several people.

## Decision

The accounts the operator logs into are **work contexts**: one per area of their activity, such as personal use or a given client. A work context is a user account — it is named, it has a home of its own, its own session and its own data — and the name of the context is the name of that account, so it has to be a valid username.

The installer asks for the complete list of work context names. Any other account on the machine is created by baseline policy and is never prompted for.

Two explicit groups are used:

- `work-contexts`: marks the accounts that are work contexts.
- `dotfiles`: grants access to the shared dotfiles according to the policy in `020-dotfiles.md`.

As specified in `001-disk-layout.md`, each work context's home is a dedicated subvolume. This applies both during initial installation and when a context is added later on an already installed system.

A work context's home directory is `/home/<name>`, and its primary group is a group named after it.

Authentication is unified: the installer asks one secret and uses it both for disk encryption and as the password of every work context.

Work contexts have passwordless sudo.

The `root` account has no password set and is not intended for interactive login.

## Why

- The accounts are called work contexts, and not login users, because that is what they are for and it is the only thing that distinguishes them from every other account on the machine. Naming them after the mechanism — that they can log in — says nothing about why there is more than one, which is the whole of this model.
- `work-contexts` and `dotfiles` are separate groups because being an area of the operator's activity and reaching the shared configuration are different permissions. A keymapper service may need to read `/dotfiles` without being anyone's work context.
- The word *user* is kept for accounts in general, rather than abolished, precisely because that separation exists: a tool that expands over the `dotfiles` group is expanding over accounts, and calling them work contexts would claim membership the group does not require.
- A unified secret for disk encryption and every work context is used because the system is operated by one person, so several passwords are unnecessary.
- Home and primary group are named after the context because a tool that is told which contexts a machine has must derive both from the name alone; if either could differ, describing a machine would take three fields where one is enough, and the three could disagree.
- Root is passwordless and non-interactive because privileged operations are performed through sudo from a work context.
- Passwordless sudo is used because the operator has already unlocked the disk and logged in, and this model has one physical operator who owns administrative privileges.

## Considerations

- The shared login secret and the disk-encryption secret are the same by design.
- The `work-contexts` and `dotfiles` groups must be kept explicit and consistent for every work context.
- Work contexts have passwordless sudo by design.
- Root remains non-interactive and passwordless by design.
- Root recovery procedures must be documented and available.
- A work context's name must be validated before the account is created.
- An account that is not a work context must not be given interactive login unless that is explicitly asked for.
- A work context must not be created through a raw `useradd` that bypasses the provisioning model defined in `001-disk-layout.md`.

## Critical Notes With Replies (Copy of Discussion)

1. Assistant critique: a single shared secret is a single point of compromise because one value unlocks both encrypted storage and every account.
   Reply: one strong memorized secret is preferred over multiple secrets that would likely be written down and leaked more easily.
2. Assistant critique: username-only post-boot login weakens local-session security because there is no second authentication step after disk unlock.
   Reply: local-session protection is enforced with lockscreen policy (for example `hyprlock`) so unattended sessions still require password unlock, and username-only mode is only enabled when supported by the selected session manager.
3. Assistant critique: shared credentials reduce account-level separation because credentials no longer differentiate the accounts.
   Reply: the separation is for session context (for example cookie/session isolation), not for different physical people.
4. Assistant critique: passwordless root requires a robust recovery flow because direct root login cannot be used as a fallback path.
   Reply: every work context is a sudoer; if sudo breaks, recovery is expected from live-environment chroot.
5. Assistant critique: a custom username-only session manager may become fragile because authentication stack and edge cases are easy to mis-handle outside mature components.
   Reply: initial implementation may use a standard password-based session manager, and later this implies developing a custom session manager specifically designed for username-only login.
6. Assistant critique: a single `@home` snapshot model is simpler but can cause cross-context rollback side effects.
   Reply: each work context gets a dedicated home subvolume so snapshot and rollback scope remains per context.
