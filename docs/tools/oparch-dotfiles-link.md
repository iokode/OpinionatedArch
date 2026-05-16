# oparch-dotfiles-link

## Description

`oparch-dotfiles-link` creates and refreshes links from the shared dotfiles source into target user or system paths. The default source is `/dotfiles`, which is the shared dotfiles tree mounted outside any individual user home.

## Why is needed

Manual dotfile linking is difficult to apply consistently across all users. A dedicated tool applies the shared `/dotfiles` source repeatably and avoids per-user divergence.

## Input parameters

- `<source>`: Optional. Shared dotfiles tree to apply. Default: `/dotfiles`.
