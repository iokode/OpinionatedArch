# Remaining

This file lists what is not documented yet: topics that still need their own document under `docs/`, and tools that have no specification.

It is a backlog, not a specification. Nothing listed here is decided.

## Pending Decisions

- **Package baseline** — what is always installed (`base` dev tools, firmware, core tools) and what remains optional.
- **AUR policy** — whether to use `paru`, how to install it, and which build user to use.
- **Default systemd services** — which units are always enabled at install time.
- **Base security policy** — firewall, SSH (if applicable), sudo policy.
- **Real session/login strategy** — initial display manager and fallback until custom implementation exists.
- **Rebuilding the return message on an installed system** — nothing is installed for it today. The installer renders from the live medium, so an installation needs nothing on the target; but the tool reads the body of the Plymouth script, and the default template package and theme, from its assets directory, and no assets directory is put on the installed system. Until one is, editing `/etc/opinionatedarch/return-message.yaml` and running the tool again does not work there, although `tools/oparch-return-message-render/000-command.md` describes that as the reason the tool exists apart from the installer. Deciding to support it also decides whether the package and theme the operator actually used are kept, and so whether the values file keeps naming where each came from or is rewritten to name local copies.
- **Kernel image in boot** — UKI for Recovery, vmlinuz for OpinionatedArch.

## Pending Work

- **Recovery system** — a read-only BTRFS subvolume with an Arch installation with tools to chroot the system.
- Generate archiso with the installer and the recovery scripts.
- Pack tools in pacman packages and create the oparch repository.
- Create the oparchiso image with installer.
- Remove `snapper` and `snap-pac`; replace by snapshot manager tools.
- Add a `-r|--reboot` option to the installer script to reboot when installation finishes.
- Implement the `keep-homes` install mode. The screen offers it and the configuration file documents it, and `prepare_layout` answers it with `keep-homes install mode is not supported yet.` before touching the disk. The prompt that goes with it is missing too: which of the existing home subvolumes to preserve. `tools/oparch-installer/002-inputs-and-bootstrap-baseline.md` lists it, and the configuration file already carries it as `preserved_home_users`, so a file can express what no screen asks.
- Handle long addresses in 4-languages layout and fix presentation in 2-languages and 3-languages layouts. Test 1-language layout.
- Add `imagemagick` and `pango` to the ISO and to the installed system: `oparch-return-message-render` composes the message image with the first and draws its text through the second. `pango` is an optional dependency of `imagemagick` on Arch, by that package's own metadata, so installing the one does not bring the other. Whether the drawing fails without it has not been observed: the end-to-end run that looked for it failed earlier, on a live environment too old for the ImageMagick its mirrors offered.
- Reimplement `oparch-user-remove` in BAML. Its current `sh` implementation is obsolete, and every built-in tool is written in the language `development/003-baml-as-implementation-language.md` decides. Whether it needs a host is answered the same way as for any other tool, in `development/004-host-bridge.md`.
- Add `noto-fonts` to the ISO and to the installed system: it is the family the message is drawn with, and the one the fallback draws from.

## Tools Pending Specification

- `**oparch-network-manager**` — wifi and wired network manager.
- `**oparch-pacman**` — browser across pacman repositories and package installer.
- `**oparch-aur**` (with PKGBUILD analytics) — browser across AUR repository, PKGBUILD inspector (LLM-based) and package installer, using `paru`.

## Recovery Tools Pending Specification

- `**oparch-chroot**` — select disk where oparch is installed, mount it and chroot it.
- `**oparch-snapshot**` — snapshot browser and restorer.

## Issues

- The dotfiles package is brought here when the installation is driven by a file, and not when it is driven by the screens. `bring_every_source` runs inside `check_config`, which only the configuration-file path calls; the form records where the package comes from and nothing fetches it. Nothing consumes it yet either, so it shows up nowhere — but once `oparch-dotfiles-sync` exists, an installation answered by hand will find nothing in `/tmp/oparch/dotfiles` while one answered by file will.
- The logo of the return message is asked for as if it were a set of files. It is one file, and the origins offered for it are the right two — a URL, or something on this machine — but the second is worded as `a directory or a .tar on this machine`, which is the wording a package gets. The label is shared: `origin_label` in `form.baml` answers by origin and not by what is being asked for, so `local` reads the same whether the answer is a package or a single file. The picker underneath already behaves correctly, offering files rather than directories and archives.
- The netboot binary on the EFI system partition is copied once, during installation, and nothing refreshes it afterwards. `tools/oparch-installer/002-inputs-and-bootstrap-baseline.md` puts `/EFI/OpinionatedArch/netbootx64.efi` there from `/usr/share/ipxe/x86_64/ipxe-arch.efi`, but when pacman later updates `ipxe` the copy stays at whichever build the installation took. So the external recovery path that `decisions/007-grub-boot-policy.md` requires ages in place, and it ages unnoticed: it is the path used when the machine is already broken, which is the moment it is first exercised. The drift is older than the package it now comes from — the download it replaced never tracked its source either, and left nothing on the machine to refresh from. What is new is that the source is now installed on the target, so the copy can be refreshed at all; a pacman hook on `ipxe` is the obvious candidate, and choosing it also decides whether the ESP copy is owned by the hook or by the installer that first wrote it.
- The installer ask for some inputs before the keymap. That could be problematic for user who want to enter data using it own keymap. Specially the shared secret: it is prompted by the installer with default en-us keymap and they can't see it due it's masked. Even worse, the Plymouth uses the selected keymap, so they'll enter different secret and won't boot.

