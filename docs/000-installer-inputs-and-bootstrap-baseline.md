# 000: Installer Inputs and Bootstrap Baseline

## Context and Decision

This document is the centralized list of:

- installer prompts
- bootstrap package list by installation phase
- minimum services enabled in chroot

### Installer Prompts

The installer asks for:

1. target disk
2. destructive confirmation (`wipe-all`)
3. machine role (`Laptop` or `Main PC`)
4. CPU vendor (`Intel`, `AMD`, or `other`) for microcode package selection
5. zram swap size in GB
6. disk swap partition size in GB
7. login usernames list
8. shared secret (used for root LUKS unlock and login-user password)
9. console keymap
10. timezone
11. hostname
12. pre-boot ownership fields:
    - owner name
    - phone
    - email
    - return address
13. logo inclusion (`yes/no`)
14. if logo is enabled: `logo_url` (retry or explicit continue-without-logo on download failure)

### Temporary Paths for Installer Staging

- Live installer temporary path for transient installation files: `/tmp/oparch`.
- Target chroot temporary path for transient installation files: `/oparch/tmp`.
- Remove `/oparch/tmp` at the end of the installer script.

### Bootstrap Package List

Pre-chroot (`pacstrap`):

- `base`
- `linux`
- `linux-headers`
- `linux-firmware`
- `intel-ucode` (if CPU vendor is `Intel`)
- `amd-ucode` (if CPU vendor is `AMD`)
- no microcode package (if CPU vendor is `other`)

Post-chroot (`pacman -S`):

- `mkinitcpio`
- `btrfs-progs`
- `cryptsetup`
- `grub`
- `efibootmgr`
- `plymouth`
- `sudo`
- `networkmanager`
- `snapper`
- `snap-pac`

### Minimum Services Enabled in Chroot

- `NetworkManager.service`
- `systemd-resolved.service`
- `snapper-cleanup.timer`

## Why

- A centralized list is required because installer prompt, package, and service definitions are cross-cutting and easy to duplicate; if this list is not centralized, documentation and script behavior drift.
- Splitting package installation into pre-chroot and post-chroot phases is required because kernel/base bootstrap must exist before chroot, while policy/system packages are configured inside target context; if phases are mixed without structure, debugging and failure isolation are harder.
- CPU-vendor microcode selection is required because early microcode package is vendor-specific for Intel/AMD and intentionally absent for `other`; if this mapping is not explicit, package selection can be incorrect.
- Explicit service baseline is required because “installed” is not equivalent to “enabled”; if services are not listed explicitly, first-boot behavior is inconsistent.
- `/tmp/oparch` in live installer is required because transient installation files need deterministic staging before files are copied into the target system; if omitted, installer temp-file flow becomes scattered and harder to reason about.
- `/oparch/tmp` in target chroot is required because `/tmp` may be cleaned by package hooks before later setup steps run; if `/tmp` is used as the only target staging path, transient files can disappear mid-install.
- Removing `/oparch/tmp` at the end is required because those assets are transient installer inputs only; if retained, stale artifacts remain after installation.

## Implementation Plan

1. Keep this file as the authoritative bootstrap checklist.
2. Validate that installer prompts map one-to-one to script input questions.
3. Install pre-chroot package set with `pacstrap`.
4. Install post-chroot package set with `pacman -S` in target context.
5. Enable the minimum service baseline in chroot before first reboot.
6. Stage transient installer files in `/tmp/oparch` during live installation.
7. Copy required transient files from `/tmp/oparch` to `/oparch/tmp` in target before chroot setup steps that consume them.
8. Remove `/oparch/tmp` at the end of the installer script.

## Considerations

- Conditional prompts must remain explicit (for example logo URL only when logo is enabled).
- Any new mandatory prompt, bootstrap package, or baseline service must be added here first.
- Optional package groups are intentionally outside this baseline and are handled in later decision documents.
