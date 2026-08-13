# Dotfiles Policy

## Context

`/dotfiles` is the shared source of configuration for every login user, on a subvolume of its own outside every home directory, as `001-disk-layout.md` lays it out. `000-user-model-and-account-types.md` marks who reaches it with the `dotfiles` group, and says that group grants access according to this policy.

What that access is was never stated. A group that reads and a group that writes produce different machines: one where shared configuration is edited with `sudo` and ends up owned by `root`, and one where it is edited by the person whose machine it is.

## Decision

`/dotfiles` is owned `root:dotfiles` with mode `2775`.

Members of the `dotfiles` group may write there, and that stays true for everything created under it. A default ACL grants the group write access to what is created:

```bash
setfacl -d -m g::rwx /dotfiles
```

Content an installation places under `/dotfiles` is left with directories at `2775` and files at `664`.

`/dotfiles` is listed in git's system-wide `safe.directory`.

## Why

- The group writes rather than only reads because the machine has one physical operator and the shared configuration is theirs to edit; if it were read-only, every change would be a `sudo` operation and would land owned by `root`, which is the state the mode exists to prevent.
- Ownership stays with `root` rather than with a login user because the tree is shared by a group and belongs to no one account; if it belonged to one, adding a second login user would make the shared source asymmetric between two contexts of the same person.
- The setgid bit is not enough on its own because it carries the group downwards and not the permission to write: a file created under it comes out owned by the group and writable only by its owner.
- A default ACL is required because the permissions of a new file are asked for by whatever creates it and cut by that process's umask, so without one the rule holds only for the programs that happen to ask correctly. The ACL is inherited by new directories in turn, so it keeps holding all the way down.
- Installed content has its modes set explicitly, rather than left to that ACL, because a copy carries the modes of what it was copied from, and a default ACL cannot widen a file whose creator asked for something narrower.
- `safe.directory` is required because git refuses to work in a repository owned by a user other than the one running it, and here the owner is `root` by design. Without it every git command in `/dotfiles` stops and asks for the path to be added; and the obvious way around that — running git under `sudo` — writes as `root` and undoes the ownership the rest of this policy arranges.

## Considerations

- `/dotfiles` is a Git repository only when the package it was installed from was one. A package taken as a directory or an archive leaves files, and the restore path `001-disk-layout.md` describes does not exist on that machine until someone makes it a repository.
- The `dotfiles` group is a boundary between the accounts of one person and not between people, as `000-user-model-and-account-types.md` establishes. Shared write access to shared configuration is the point of it, not a concession.
- Secrets are not kept here. Their store is outside `/dotfiles`, at the path `../tools/oparch-dotfiles-sync/001-map-format.md` specifies, with its own owner and modes, and it is not part of what this policy opens to the group.
- What `oparch-dotfiles-sync` writes is the targets a map declares and its own state under `/var/lib/oparch/`. Its permission to read `/dotfiles` is the group's, and nothing here asks it to write there.
