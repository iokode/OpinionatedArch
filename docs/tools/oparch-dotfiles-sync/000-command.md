# oparch-dotfiles-sync

## Description

`oparch-dotfiles-sync` applies the shared dotfiles source to target user and system paths. It installs declared packages and links, copies, and renders managed targets as declared in the map. The default source is `/dotfiles`, the shared dotfiles tree mounted outside any individual user home, and the default map is `/dotfiles/main.dfmap`.

## Why is needed

Manual dotfile application is difficult to keep consistent across all users and machines. A dedicated tool applies the shared `/dotfiles` source repeatably from one declarative map and avoids per-user divergence.

## Input parameters

- `--source <path>`: Optional. Shared dotfiles source directory to apply. Default: `/dotfiles`.
- `--map <path>`: Optional. Map file path. Default: `main.dfmap` at the top of `--source`, which is `/dotfiles/main.dfmap` when the source is the default one.
- `--secrets-root <path>`: Optional. Root of the secret store the map's secrets are read from. Default: the store defined in `001-map-format.md`.
- `--hostname <name>`: Optional. The hostname host selectors are evaluated against. Default: this machine's.
- `--user <name>`: Optional, repeatable. A login user to expand user targets over. Default: the members of the `dotfiles` group on this machine. The home directory and primary group of each name follow from it, as `../../decisions/000-user-model-and-account-types.md` decides.
- `--dry-run`: Optional. Print the plan without installing packages or changing filesystem targets. Dry-run output identifies secret references without printing their values.
- `--list-secrets`: Optional. Print what the plan requires of the secret store, one path per line, relative to its root, and change nothing. Whether those files exist is not checked, because the question is what a store would have to hold. An empty answer means the plan needs no store.

The machine is described from the arguments or from the system, never from both: given any `--user`, the `dotfiles` group is not consulted at all.

## Planning for another machine

The four options above are what let a map be planned for a machine that is not the one the tool is running on: one being installed, one whose hostname is about to change, or one being checked from elsewhere. They describe a machine; they do not aim the tool at it. What it writes, it still writes into its own root, as `../../development/008-acting-on-another-system.md` requires.

## Interactive usage

There is no interactive version. Synchronization behavior is fully declared by the map. Any interactive secret collection is a separate interface that populates the local Oparch secret store before `oparch-dotfiles-sync` runs.
