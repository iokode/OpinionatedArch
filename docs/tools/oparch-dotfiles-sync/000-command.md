# oparch-dotfiles-sync

## Description

`oparch-dotfiles-sync` applies the shared dotfiles source to target user and system paths. It installs declared packages and links, copies, and renders managed targets as declared in the map. The default source is `/dotfiles`, the shared dotfiles tree mounted outside any individual user home, and the default map is `/dotfiles/main.dfmap`.

## Why is needed

Manual dotfile application is difficult to keep consistent across all users and machines. A dedicated tool applies the shared `/dotfiles` source repeatably from one declarative map and avoids per-user divergence.

## Requirements

What has to be installed where this runs, which is the machine whose dotfiles are being applied — this tool is entered rather than aimed, as `../../development/004-acting-on-another-system.md` decides, so that is the root it needs everything in.

- **`pacman`**, for the packages a map declares. A map that declares none does not use it, but nothing is arranged so that it is absent.
- **`glibc`**, for `getent` and `id`: the accounts to expand over are the members of the `dotfiles` group, and each target is owned by the user the map named.
- **`coreutils`**, for `install`, `ln`, `chown` and `rm`.

Every one of these is on any Arch system, live or installed, so there is nothing to add before a run. The list is here because it is the thing that would have to be checked if a target ever became something smaller than an Arch install, and because a tool that is copied into a system being built is a tool running somewhere nobody has looked.

There is no BAML runtime library in this list: this tool has no host, so `baml pack` makes it a standalone binary — the distinction is `../../development/001-host-bridge.md`.

## Input parameters

- `--source <path>`: Optional. Shared dotfiles source directory to apply. Default: `/dotfiles`.
- `--map <path>`: Optional. Map file path. Default: `main.dfmap` at the top of `--source`, which is `/dotfiles/main.dfmap` when the source is the default one.
- `--secrets-root <path>`: Optional. Root of the secret store the map's secrets are read from. Default: the store defined in `001-map-format.md`.
- `--hostname <name>`: Optional. The hostname host selectors are evaluated against. Default: this machine's.
- `--user <name>`: Optional, repeatable. An account to expand user targets over. Default: the members of the `dotfiles` group on this machine, which are the work contexts and whatever else was put in that group. The home directory and primary group of each name follow from it, as `../../decisions/000-work-contexts-and-accounts.md` decides.
- `--dry-run`: Optional. Print the plan without installing packages or changing filesystem targets. Dry-run output identifies secret references without printing their values.
- `--list-secrets`: Optional. Print what the plan requires of the secret store, one path per line, relative to its root, and change nothing. Whether those files exist is not checked, because the question is what a store would have to hold. An empty answer means the plan needs no store.

The machine is described from the arguments or from the system, never from both: given any `--user`, the `dotfiles` group is not consulted at all.

## Planning for another machine

The four options above are what let a map be planned for a machine that is not the one the tool is running on: one being installed, one whose hostname is about to change, or one being checked from elsewhere. They describe a machine; they do not aim the tool at it. What it writes, it still writes into its own root, as `../../development/004-acting-on-another-system.md` requires.

## Interactive usage

There is no interactive version. Synchronization behavior is fully declared by the map. Any interactive secret collection is a separate interface that populates the local Oparch secret store before `oparch-dotfiles-sync` runs.
