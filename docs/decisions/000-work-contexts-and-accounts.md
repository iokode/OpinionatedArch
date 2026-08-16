# Work Contexts and Accounts

## Context

The system is designed for one physical person. Several Linux accounts exist on it, and they do not represent several people.

## Decision

The accounts the operator logs into are **work contexts**: one per area of their activity, such as personal use or a given client. A work context is a user account — it is named, it has a home of its own, its own session and its own data — and the name of the context is the name of that account, so it has to be a valid username.

The work contexts of a machine are the ones the operator names, at installation or on a running system. Other accounts exist — the ones the base system and its packages bring, and any the operator creates for something else, such as running a service under an identity of its own — and none of them is a work context.

Two explicit groups are used:

- `work-contexts`: marks the accounts that are work contexts.
- `dotfiles`: grants access to the shared dotfiles according to the policy in [Dotfiles](018-dotfiles.md).

As specified in [Disk Layout](001-disk-layout.md), each work context's home is a dedicated subvolume. This applies both during initial installation and when a context is added later on an already installed system.

A work context named `<name>` has `/home/<name>` as its home directory and `<name>` as its primary group.

Every work context has the same password, and that password is also the secret that unlocks the encrypted container required by [Encryption](002-encryption.md).

Work contexts have passwordless sudo.

The `root` account has no password set and is not intended for interactive login.

## Why

- `work-contexts` and `dotfiles` are separate groups because being an area of the operator's activity and reaching the dotfiles are different permissions. A keymapper service may need to read `/dotfiles` without being anyone's work context.
- The word *user* is kept for accounts in general, rather than abolished, precisely because that separation exists: a tool that expands over the `dotfiles` group is expanding over accounts, and calling them work contexts would claim membership the group does not require.
- One secret for the disk and for every work context is used because one strong memorized secret is preferable to several that would likely end up written down somewhere; split into many, this model gains no separation — the accounts are one person's — and raises the practical risk of handling them.
- Home and primary group are named after the context because a tool that is told which contexts a machine has must derive both from the name alone; if either could differ, describing a machine would take three fields where one is enough, and the three could disagree.
- Root is passwordless and non-interactive because privileged operations are performed through sudo from a work context.
- Passwordless sudo is used because the operator has already unlocked the disk and logged in, and this model has one physical operator who owns administrative privileges.

## Considerations

- The `work-contexts` and `dotfiles` groups must be kept explicit and consistent for every work context.
- Work contexts have passwordless sudo by design.
- Root remains non-interactive and passwordless by design.
- Root recovery procedures must be documented and available.
- A work context's name must be validated before the account is created.
- An account that is not a work context must not be given interactive login unless that is explicitly asked for.
- A work context must not be created through a raw `useradd` that bypasses the provisioning model defined in [Disk Layout](001-disk-layout.md).

