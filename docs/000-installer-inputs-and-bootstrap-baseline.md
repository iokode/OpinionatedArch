# 000: Installer Inputs and Bootstrap Baseline

## Context and Decision

This document is the centralized list of:

- installer prompts
- bootstrap package list
- minimum services enabled in chroot

### Installer Prompts

The installer asks for:

1. target disk
2. destructive confirmation (`wipe-all`)
3. startup policy (`manual` or `automatic`)
4. ucode package (`intel-ucode`, `amd-ucode`, or `none`)
5. GPU driver (`nvidia`, `nvidia-open`, `nouveau`, or `none`)
6. zram swap size in GB
7. disk swap partition size in GB
8. login usernames list
9. shared secret (used for root LUKS unlock and login-user password)
10. console keymap
11. timezone
12. hostname
13. pre-boot return message inclusion (`yes/no`)
14. if return message is enabled: pre-boot ownership fields:
    - owner name
    - phone
    - email
    - return address
15. if return message is enabled: return-message languages, selecting 1 to 4 templates
16. if return message is enabled: logo inclusion (`yes/no`)
17. if logo is enabled: `logo_url` (retry or explicit continue-without-logo on download failure)

### Temporary Paths for Installer Staging

- Live installer temporary path for transient installation files: `/tmp/oparch`.
- Target chroot temporary path for transient installation files: `/usr/opinionatedarch/tmp`.
- Remove `/usr/opinionatedarch/tmp` at the end of the installer script.

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
- `gum`
- `fzf`
- `sudo`
- `networkmanager`
- `snapper`
- `snap-pac`
- `intel-ucode` (if selected as the ucode package)
- `amd-ucode` (if selected as the ucode package)
- `nvidia` (if GPU driver is `nvidia`)
- `nvidia-open` (if GPU driver is `nvidia-open`)
- `plymouth` (if pre-boot return message is enabled)
- `ttf-dejavu` (if pre-boot return message is enabled)

### Minimum Services Enabled in Chroot

- `NetworkManager.service`
- `systemd-resolved.service`
- `snapper-cleanup.timer`

## Why

- A centralized list is required because installer prompt, package, and service definitions are cross-cutting and easy to duplicate; if this list is not centralized, documentation and script behavior drift.
- Installing the baseline package set with `pacstrap` is required because package provisioning and target configuration are separate responsibilities; if chroot configuration also installs baseline packages, the package baseline has two sources of truth, and installation performs two package download operations instead of one.
- Ucode package selection is required because CPU microcode must be installed before reboot when the target hardware needs it; if deferred until after first boot, the first run can start without the CPU fixes expected for correct hardware operation.
- GPU driver selection is required because the target graphics driver must be installed before reboot when the hardware needs it; if deferred until after first boot, the first run can start with missing or incorrect graphics support.
- Return-message language selection is required because the target audience for a lost-device message depends on where the machine is expected to travel; if language choice is hardcoded, installations either show irrelevant text or require script edits.
- Installing a proportional font with the return-message theme is required because localized text needs Latin glyph coverage and should not depend on a monospace fallback; if omitted, accented characters or the preferred font style can fail during early boot.
- Explicit service baseline is required because “installed” is not equivalent to “enabled”; if services are not listed explicitly, first-boot behavior is inconsistent.
- `/tmp/oparch` in live installer is required because transient installation files need deterministic staging before files are copied into the target system; if omitted, installer temp-file flow becomes scattered and harder to reason about.
- `/usr/opinionatedarch/tmp` in target chroot is required because `/tmp` may be cleaned by package hooks before later setup steps run; if `/tmp` is used as the only target staging path, transient files can disappear mid-install.
- Removing `/usr/opinionatedarch/tmp` at the end is required because those assets are transient installer inputs only; if retained, stale artifacts remain after installation.

## Implementation Plan

1. Keep this file as the authoritative bootstrap checklist.
2. Validate that installer prompts map one-to-one to script input questions.
3. Install the full baseline package set with `pacstrap`.
4. Configure installed packages and services in target context.
5. Enable the minimum service baseline in chroot before first reboot.
6. Stage transient installer files in `/tmp/oparch` during live installation.
7. Copy required transient files from `/tmp/oparch` to `/usr/opinionatedarch/tmp` in target before chroot setup steps that consume them.
8. Remove `/usr/opinionatedarch/tmp` at the end of the installer script.

## Considerations

- Conditional prompts must remain explicit (for example logo URL only when logo is enabled).
- Any new mandatory prompt, bootstrap package, or baseline service must be added here first.
- Optional package groups are intentionally outside this baseline and are handled in later decision documents.
