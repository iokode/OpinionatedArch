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
3. if install mode is `wipe-all`: destructive confirmation
4. if install mode is `keep-homes`: existing home users to preserve, selected with a `gum` multi-select
5. startup policy (`manual` or `automatic`)
6. ucode package (`intel-ucode`, `amd-ucode`, or `none`)
7. GPU driver (`nvidia`, `nvidia-open`, `nouveau`, or `none`)
8. zram swap size in GB
9. disk swapfile size in GB (if 0, do not create any swapfile)
10. login usernames list (in `keep-homes`, this creates additional users beyond the preserved-home users)
11. shared secret (used for root LUKS unlock and login-user password)
12. console keymap
13. timezone
14. hostname
15. public dotfiles repository clone (`yes/no`)
16. if public dotfiles repository clone is enabled: dotfiles repository URL
17. pre-boot return message inclusion (`yes/no`)
18. if return message is enabled: pre-boot ownership fields:
  - owner name
    - phone
    - email
    - return address
19. if return message is enabled: return-message languages, selecting 1 to 4 templates
20. if return message is enabled: logo inclusion (`yes/no`)
21. if logo is enabled: `logo_url` (retry or explicit continue-without-logo on download failure)

### Temporary Paths for Installer Staging

- Live installer temporary path for transient installation files: `/tmp/oparch`.
- Target chroot temporary path for transient installation files: `/usr/opinionatedarch/tmp`.
- Transient files needed inside the target are copied from `/tmp/oparch` to `/usr/opinionatedarch/tmp` before the chroot steps that consume them.
- Remove `/usr/opinionatedarch/tmp` at the end of the installer script.

### Public Dotfiles Repository Clone

When the public dotfiles repository clone is enabled, the installer clones the given repository into `/dotfiles` and then runs `oparch-dotfiles-sync`.

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
- The preserved-home user selection uses a `gum` multi-select because `keep-homes` can preserve any subset of existing user homes.
- Ucode package selection is required because CPU microcode must be installed before reboot when the target hardware needs it; if deferred until after first boot, the first run can start without the CPU fixes expected for correct hardware operation.
- GPU driver selection is required because the target graphics driver must be installed before reboot when the hardware needs it; if deferred until after first boot, the first run can start with missing or incorrect graphics support.
- Public dotfiles repository clone is requested during installation so public dotfiles can be cloned into `/dotfiles` and synchronized before first boot.
- Return-message language selection is requested during installation so the pre-boot return message is available on first boot instead of requiring post-install setup.
- The minimum service baseline is enabled before first boot so baseline system functionality is available immediately.

## Considerations

- Conditional prompts must remain explicit (for example logo URL only when logo is enabled).
- Any new mandatory prompt, bootstrap package, or baseline service must be added here first.
- Optional package groups are intentionally outside this baseline and are handled in later decision documents.

