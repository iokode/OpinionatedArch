# oparch-dotfiles-sync

## Description

`oparch-dotfiles-sync` applies the shared dotfiles source to target user and system paths. It installs declared packages and links, copies, and renders managed targets as declared in the map. The default source is `/dotfiles`, the shared dotfiles tree mounted outside any individual user home, and the default map is `/dotfiles/main.dfmap`.

## Why is needed

Manual dotfile application is difficult to keep consistent across all users and machines. A dedicated tool applies the shared `/dotfiles` source repeatably from one declarative map and avoids per-user divergence.

## Input parameters

- `--source <path>`: Optional. Shared dotfiles source directory to apply. Default: `/dotfiles`.
- `--map <path>`: Optional. Map file path. Default: `/dotfiles/main.dfmap`.
- `--dry-run`: Optional. Print the plan without installing packages or changing filesystem targets. Dry-run output identifies secret references without printing their values.

## Interactive usage

There is no interactive version. Synchronization behavior is fully declared by the map. Any interactive secret collection is a separate interface that populates the local Oparch secret store before `oparch-dotfiles-sync` runs.
