# Dotfiles

## Context

`/dotfiles` is the shared source of configuration for every work context, and the system. [Work Contexts and Accounts](000-work-contexts-and-accounts.md) marks who reaches it with the `dotfiles` group, and says that group grants access according to this policy.

## Decision

The configuration of the machine is one source, and every work context takes what it needs from it. There is no second copy of a file for a second context.

What one context or one machine needs and another does not is declared, not kept apart: a rule says which contexts and which machines it applies to, and the same source produces all of them. The syntax of those rules is [Dotfiles Map Format](../tools/oparch-dotfiles-sync/001-map-format.md).

`/dotfiles` is owned `root:dotfiles` with mode `2775`.

Members of the `dotfiles` group may write there, and that stays true for everything created under it. A default ACL grants the group write access to what is created:

```bash
setfacl -d -m g::rwx /dotfiles
```

Content an installation places under `/dotfiles` is left with directories at `2775` and files at `664`.

`/dotfiles` is listed in git's system-wide `safe.directory`.

Secret values are not kept in `/dotfiles`. They live in a store of their own, `/etc/oparch/dotfiles-sync/secrets/`, owned `root:root` with mode `0700`, which the `dotfiles` group does not reach. What that store holds and how it is read is [Dotfiles Map Format](../tools/oparch-dotfiles-sync/001-map-format.md).

A change under `/dotfiles` reaches a linked target at once, because that target is a link to it. Everything the map copies or renders is produced by [oparch-dotfiles-sync](../tools/oparch-dotfiles-sync/000-command.md), and changes when it is run.

## Why

- The configuration is one source because the same person works from every context on that machine, and a preference copied into three places is three places to change and two of them forgotten. Declaring what differs keeps the difference visible: a rule that names a context or a machine says so where anyone reading the source can see it, while a second copy says nothing about why it exists.
- Secrets stay out of `/dotfiles` because the group writes there and, when the tree came from a repository, what is there is published: a credential kept among the configuration travels with the first push, and is readable by every context in the meantime.
- The group writes rather than only reads because the machine has one physical operator and the shared configuration is theirs to edit; if it were read-only, every change would be a `sudo` operation and would land owned by `root`, which is the state the mode exists to prevent.
- Ownership stays with `root` rather than with a work context because the tree is shared by a group and belongs to no one account; if it belonged to one, adding a second context would make the shared source asymmetric between two areas of the same person's activity.
- The setgid bit is not enough on its own because it carries the group downwards and not the permission to write: a file created under it comes out owned by the group and writable only by its owner.
- A default ACL is required because the permissions of a new file are asked for by whatever creates it and cut by that process's umask, so without one the rule holds only for the programs that happen to ask correctly. The ACL is inherited by new directories in turn, so it keeps holding all the way down.
- Installed content has its modes set explicitly, rather than left to that ACL, because a copy carries the modes of what it was copied from, and a default ACL cannot widen a file whose creator asked for something narrower.
- `safe.directory` is required because git refuses to work in a repository owned by a user other than the one running it, and here the owner is `root` by design. Without it every git command in `/dotfiles` stops and asks for the path to be added; and the obvious way around that — running git under `sudo` — writes as `root` and undoes the ownership the rest of this policy arranges.

## Considerations

- `/dotfiles` is a Git repository only when the package it was installed from was one. A package taken as a directory or an archive leaves files, and the restore path [Disk Layout](001-disk-layout.md) describes does not exist on that machine until someone makes it a repository.
- The `dotfiles` group is a boundary between the accounts of one person and not between people, as [Work Contexts and Accounts](000-work-contexts-and-accounts.md) establishes. Shared write access to shared configuration is the point of it, not a concession.
- What [oparch-dotfiles-sync](../tools/oparch-dotfiles-sync/000-command.md) writes is the targets a map declares and its own state under `/var/lib/oparch/`. Its permission to read `/dotfiles` is the group's, and nothing here asks it to write there.

