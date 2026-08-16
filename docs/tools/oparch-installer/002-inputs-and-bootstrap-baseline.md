# Installer Inputs and Bootstrap Baseline

## Context

Installer prompts, the bootstrap package set, and the services enabled before first boot are each consumed by separate parts of the installer and referenced by several other decision documents.

## Specification

The installer flow assumes the known baseline state from a clean Arch live environment. It must not add defensive pre-existence handling for install paths that are impossible in that baseline.

This document is the centralized list of:

- installer prompts
- bootstrap package list
- minimum services enabled in chroot

### Installer Prompts

The installer asks for:

1. console keymap, applied to the console as soon as it is given, so that every answer below it is typed with it
2. target disk
3. install mode (`wipe-all` or `keep-homes`)
4. if install mode is `keep-homes`: existing home subvolumes to preserve, selected from a multiple-choice list
5. ucode package (`intel-ucode`, `amd-ucode`, or `none`)
6. GPU driver (`nvidia`, `nvidia-open`, `nouveau`, or `none`)
7. zram swap size in GB
8. disk swapfile size in GB (if 0, do not create any swapfile)
9. work context names (in `keep-homes`, these are created in addition to the contexts whose homes are preserved)
10. shared secret (used for root LUKS unlock and as the password of every work context)
11. timezone
12. hostname
13. public dotfiles package (`yes/no`)
14. if the public dotfiles package is enabled: where it comes from, as [Installer Input Sources](003-input-sources.md) defines a package source
15. if the dotfiles map declares secrets the plan reaches: where the encrypted secret store comes from, as [Installer Input Sources](003-input-sources.md) defines a file source
16. if a secret store is given: the passphrase that opens it, asked once and asked again when it does not
17. pre-boot return message inclusion (`yes/no`)
18. if return message is enabled: where the template package comes from, the project's own among the origins, as [Installer Input Sources](003-input-sources.md) defines a package source
19. if return message is enabled: where the theme comes from, the project's own among the origins, as the same document defines it and [Return Message Themes](../oparch-return-message-render/004-themes.md) decides it
20. if return message is enabled: a value for each field the template package declares. The project's own package declares owner name, phone, email and return address
21. if return message is enabled: return-message languages, selecting as many as the theme accepts
22. if return message is enabled: logo inclusion (`yes/no`)
23. if logo is enabled: where the logo file comes from, as [Installer Input Sources](003-input-sources.md) defines a file source (retry or explicit continue-without-logo when it cannot be obtained)

Whether a package needs secrets at all is not asked: the installer asks the tool, which answers by building the plan the installation will carry out.

### Install Modes

`wipe-all` repartitions the target disk and destroys everything that was on it.

`keep-homes` keeps the `home/@<work-context>` subvolumes selected from the ones already there, and rebuilds the rest of the layout around them. Each preserved home returns to the work context of the same name, and the contexts named in prompt 9 are created beside them. The layout both modes arrive at is the one [Disk Layout](../../decisions/001-disk-layout.md) fixes; nothing of the mode survives in the installed system.

### Temporary Paths for Installer Staging

- Live installer temporary path for transient installation files: `/tmp/oparch`.
- Nothing is staged inside the target. The target filesystem is mounted while the installation runs, so the installer writes into it directly; only the commands that need the target's own context are run there.

### Public Dotfiles Package

When a public dotfiles package is enabled, the installer puts its content into `/dotfiles` and then runs `oparch-dotfiles-sync`. Where that content comes from — a directory, an archive or a repository — is defined in [Installer Input Sources](003-input-sources.md).

It is the last thing the installation does, and it is judged long before it: the package is brought to the staging path while the form is still being answered, and `oparch-dotfiles-sync` is asked what it makes of it, for the hostname and the work contexts this installation is creating. A package it will not apply is refused there, with the disk untouched.

What `/dotfiles` is left as — its modes, the default ACL that keeps them true, and the `safe.directory` entry that lets git work in a tree it does not own — is decided in [Dotfiles](../../decisions/014-dotfiles.md).

A map that declares secrets is given them as one encrypted store, defined in [Secret Store Archive](../oparch-dotfiles-sync/002-secret-store-archive.md). It is opened into the live staging path, which is memory, and copied into the target with the owner and modes the map format requires, before the tool runs.

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
- `ipxe`
- `zram-generator` (if the zram swap size is greater than zero)
- `intel-ucode` (if selected as the ucode package)
- `amd-ucode` (if selected as the ucode package)
- `nvidia` (if GPU driver is `nvidia`)
- `nvidia-open` (if GPU driver is `nvidia-open`)
- `plymouth` (if pre-boot return message is enabled)

### Netboot Recovery Binary

The `Arch Netboot` entry required by [Bootloader](../../decisions/008-bootloader.md) chainloads `/EFI/OpinionatedArch/netbootx64.efi` on the EFI system partition.

That file is copied from the `ipxe` package, which `pacstrap` installs into the target as `/usr/share/ipxe/x86_64/ipxe-arch.efi`. It is not downloaded, and it is not staged in the live environment.

### Minimum Services Enabled in Chroot

- `NetworkManager.service`
- `systemd-resolved.service`

These services must be enabled in the target system before first boot, not only installed.

## Why

- Avoiding defensive pre-existence handling is required because the installer always starts from the same clean-live baseline; if impossible-state guards are added anyway, script size and branching grow without adding real reliability, which increases maintenance cost and failure surface.
- Installing the baseline package set with `pacstrap` is required so installation scripts have one package source of truth and avoid running two package installation operations.
- The preserved-home selection allows multiple choices because `keep-homes` can preserve any subset of the home subvolumes already there.
- Ucode package selection is required because CPU microcode must be installed before reboot when the target hardware needs it; if deferred until after first boot, the first run can start without the CPU fixes expected for correct hardware operation.
- GPU driver selection is required because the target graphics driver must be installed before reboot when the hardware needs it; if deferred until after first boot, the first run can start with missing or incorrect graphics support.
- A public dotfiles package is requested during installation so public dotfiles can be placed in `/dotfiles` and synchronized before first boot.
- Return-message language selection is requested during installation so the pre-boot return message is available on first boot instead of requiring post-install setup.
- The minimum service baseline is enabled before first boot so baseline system functionality is available immediately.
- The netboot recovery binary comes from the `ipxe` package rather than from a download because the package ships the same Arch-scripted `ipxe-arch.efi` the project would otherwise fetch, and taking it from there keeps every artifact on one source and one verification. A downloaded file is vouched for only by the transport that carried it, adds a network failure path of its own to a run that must complete in full, and pins the machine to whichever build the static file happens to be — an older one than the package carries.

## Considerations

- Conditional prompts must remain explicit (for example logo URL only when logo is enabled).
- Any new mandatory prompt, bootstrap package, or baseline service must be added here first.
- Optional package groups are intentionally outside this baseline and are handled in later decision documents.

