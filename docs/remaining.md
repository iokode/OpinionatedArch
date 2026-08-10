# Remaining

This file lists what is not documented yet: topics that still need their own document under `docs/`, and tools that have no specification.

It is a backlog, not a specification. Nothing listed here is decided.

## Pending Decisions

- **Package baseline** — what is always installed (`base` dev tools, firmware, core tools) and what remains optional.
- **AUR policy** — whether to use `paru`, how to install it, and which build user to use.
- **Default systemd services** — which units are always enabled at install time.
- **Base security policy** — firewall, SSH (if applicable), sudo policy.
- **Real session/login strategy** — initial display manager and fallback until custom implementation exists.
- **Rebuilding the return message on an installed system** — nothing is installed for it today. The installer renders from the live medium, so an installation needs nothing on the target; but the tool reads the body of the Plymouth script, and the default template package and theme, from its assets directory, and no assets directory is put on the installed system. Until one is, editing `/etc/opinionatedarch/return-message.yaml` and running the tool again does not work there, although `../tools/oparch-return-message-render/000-command.md` describes that as the reason the tool exists apart from the installer. Deciding to support it also decides whether the package and theme the operator actually used are kept, and so whether the values file keeps naming where each came from or is rewritten to name local copies.

## Pending Work

- **Recovery system** — a read-only BTRFS subvolume with an Arch installation with tools to chroot the system.
- Generate archiso with the installer and the recovery scripts.
- Pack tools in pacman packages and create the oparch repository.
- Create the oparchiso image with installer.
- Remove `snapper` and `snap-pac`; replace by snapshot manager tools.
- Add a `-r|--reboot` option to the installer script to reboot when installation finishes.
- Handle long addresses in 4-languages layout and fix presentation in 2-languages and 3-languages layouts. Test 1-language layout.
- Add `imagemagick` to the ISO and to the installed system: `oparch-return-message-render` composes the message image with it. The build must be the one with the Pango delegate, which is what draws the text and finds a font for a script the chosen family does not cover.
- Add `noto-fonts` to the ISO and to the installed system: it is the family the message is drawn with, and the one the fallback draws from.

## Tools Pending Specification

- **`oparch-network-manager`** — wifi and wired network manager.
- **`oparch-pacman`** — browser across pacman repositories and package installer.
- **`oparch-aur`** (with PKGBUILD analytics) — browser across AUR repository, PKGBUILD inspector (LLM-based) and package installer, using `paru`.

## Recovery Tools Pending Specification

- **`oparch-chroot`** — select disk where oparch is installed, mount it and chroot it.
- **`oparch-snapshot`** — snapshot browser and restorer.

