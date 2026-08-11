# Installer Inputs and Bootstrap Baseline

## Context

Installer prompts, the bootstrap package set, and the services enabled before first boot are each consumed by separate parts of the installer and referenced by several other decision documents.

## Decision

The installer flow assumes the known baseline state from a clean Arch live environment. It must not add defensive pre-existence handling for install paths that are impossible in that baseline.

This document is the centralized list of:

- installer prompts
- bootstrap package list
- minimum services enabled in chroot

### Installer Prompts

The installer asks for:

1. target disk
2. install mode (`wipe-all` or `keep-homes`)
3. if install mode is `keep-homes`: existing home users to preserve, selected from a multiple-choice list
4. ucode package (`intel-ucode`, `amd-ucode`, or `none`)
5. GPU driver (`nvidia`, `nvidia-open`, `nouveau`, or `none`)
6. zram swap size in GB
7. disk swapfile size in GB (if 0, do not create any swapfile)
8. login usernames list (in `keep-homes`, this creates additional users beyond the preserved-home users)
9. shared secret (used for root LUKS unlock and login-user password)
10. console keymap
11. timezone
12. hostname
13. public dotfiles package (`yes/no`)
14. if the public dotfiles package is enabled: where it comes from, as `018-installer-input-sources.md` defines a package source
15. pre-boot return message inclusion (`yes/no`)
16. if return message is enabled: where the template package comes from, the project's own among the origins, as `018-installer-input-sources.md` defines a package source
17. if return message is enabled: where the theme comes from, the project's own among the origins, as the same document defines it and `017-return-message-themes.md` decides it
18. if return message is enabled: a value for each field the template package declares. The project's own package declares owner name, phone, email and return address
19. if return message is enabled: return-message languages, selecting as many as the theme accepts
20. if return message is enabled: logo inclusion (`yes/no`)
21. if logo is enabled: where the logo file comes from, as `018-installer-input-sources.md` defines a file source (retry or explicit continue-without-logo when it cannot be obtained)

### Temporary Paths for Installer Staging

- Live installer temporary path for transient installation files: `/tmp/oparch`.
- Nothing is staged inside the target. The target filesystem is mounted while the installation runs, so the installer writes into it directly; only the commands that need the target's own context are run there.

### Public Dotfiles Package

When a public dotfiles package is enabled, the installer puts its content into `/dotfiles` and then runs `oparch-dotfiles-sync`. Where that content comes from — a directory, an archive or a repository — is defined in `018-installer-input-sources.md`.

### Bootstrap Package List

Installed with `pacstrap`:

- `base`
- `linux`
- `linux-headers`
- `linux-firmware`
- `mkinitcpio`
- `iptables-nft`
- `btrfs-progs`
- `cryptsetup`
- `grub`
- `efibootmgr`
- `sudo`
- `networkmanager`
- `zram-generator` (if the zram swap size is greater than zero)
- `intel-ucode` (if selected as the ucode package)
- `amd-ucode` (if selected as the ucode package)
- `nvidia` (if GPU driver is `nvidia`)
- `nvidia-open` (if GPU driver is `nvidia-open`)
- `plymouth` (if pre-boot return message is enabled)

### Minimum Services Enabled in Chroot

- `NetworkManager.service`
- `systemd-resolved.service`

These services must be enabled in the target system before first boot, not only installed.

## Why

- Avoiding defensive pre-existence handling is required because the installer always starts from the same clean-live baseline; if impossible-state guards are added anyway, script size and branching grow without adding real reliability, which increases maintenance cost and failure surface.
- Installing the baseline package set with `pacstrap` is required so installation scripts have one package source of truth and avoid running two package installation operations.
- The preserved-home user selection allows multiple choices because `keep-homes` can preserve any subset of existing user homes.
- Ucode package selection is required because CPU microcode must be installed before reboot when the target hardware needs it; if deferred until after first boot, the first run can start without the CPU fixes expected for correct hardware operation.
- GPU driver selection is required because the target graphics driver must be installed before reboot when the hardware needs it; if deferred until after first boot, the first run can start with missing or incorrect graphics support.
- A public dotfiles package is requested during installation so public dotfiles can be placed in `/dotfiles` and synchronized before first boot.
- Return-message language selection is requested during installation so the pre-boot return message is available on first boot instead of requiring post-install setup.
- The minimum service baseline is enabled before first boot so baseline system functionality is available immediately.

## Considerations

- Conditional prompts must remain explicit (for example logo URL only when logo is enabled).
- Any new mandatory prompt, bootstrap package, or baseline service must be added here first.
- Optional package groups are intentionally outside this baseline and are handled in later decision documents.

