# oparch-work-context-create

## Description

`oparch-work-context-create` creates a new work context: the account that carries it, its groups, its password, its home subvolume and the mount of that home, the initial ownership of that home, and its snapshot paths. It makes each of them as an installation makes them for the contexts it is given.

- The account `<name>` has `/home/<name>` as its home directory, `<name>` as its primary group, `wheel`, `dotfiles` and `work-contexts` as its other groups, and `/bin/bash` as its shell.
- Its password is the one every work context has. The account is given the password hash of an existing work context, so the tool is given no secret.
- Its home is the subvolume `home/@<name>` in the top level of the Btrfs filesystem, mounted at `/home/<name>` and written into `fstab` in the form `genfstab` gives the other mounts. The top level is mounted on a temporary directory while the subvolume is created, and unmounted and that directory removed afterwards.
- The home is owned by `<name>:<name>`.
- Its snapshot paths are `/snapshots/home/<name>/automatic` and `/snapshots/home/<name>/manual`.

It runs as root. Run by any other user, it refuses with an error before doing anything else.

## Why is needed

Creating the account by hand is error-prone and can break assumptions used by snapshot and permission policies. A work context is not one `useradd`: it is an account, a membership in two groups, a dedicated subvolume and a mount that has to survive a reboot. One tool owns the whole of it, so a context added later matches the ones the installation made.

## Requirements

What has to be installed where this runs, which is the machine the work context is created on.

- **`shadow`**, for `useradd` and `chpasswd`.
- **`glibc`**, for `getent`: the existing work contexts are read from the `work-contexts` group, and the password hash of one of them from the shadow database.
- **`util-linux`**, for `mount`, `umount`, `findmnt` and `lsblk`.
- **`btrfs-progs`**, for `btrfs`.
- **`coreutils`**, for `id`, `mktemp`, `rmdir` and `chown`.

Every one of these is on an installed system, so there is nothing to add before a run.

There is no BAML runtime library in this list: this tool has no host, so `baml pack` makes it a standalone binary — the distinction is [Host Bridge](../../../development/001-host-bridge.md).

## Input parameters

- `<name>`: Mandatory. Name of the work context to create. It is also the name of the account that carries it, so it has to be a valid username: one to thirty-two characters, starting with a lowercase letter or `_`, and holding only lowercase letters, digits, `_` and `-`. The name `system` is reserved. The name is checked before anything is created.
