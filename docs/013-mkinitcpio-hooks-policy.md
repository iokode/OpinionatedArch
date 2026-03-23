# 013: mkinitcpio Hooks Policy

## Context and Decision

Initramfs uses the busybox-based flow for this project phase.

The configured hooks are:

```bash
HOOKS=(base udev autodetect microcode kms keyboard keymap block plymouth encrypt filesystems)
```

The following hooks are intentionally not used in this phase: `systemd`, `sd-encrypt`, `usr`, `modconf`, `btrfs`, and `fsck`.

Plymouth must be installed in the target system before generating initramfs.

Keyboard layout for unlock is provided by installer input and applied through `keymap`.

## Why

- Busybox initramfs flow is used because current boot requirements are limited to Plymouth + LUKS + Btrfs root; if systemd initramfs is introduced now, complexity increases without a required benefit.
- `base`, `udev`, `block`, and `filesystems` are required because they provide the minimum boot path from initramfs to mounted root; if any is missing, early boot cannot complete reliably.
- `encrypt` is required because root is encrypted with LUKS; if it is missing, root cannot be unlocked during boot.
- `plymouth` is required because unlock must show the custom ownership screen; if missing, unlock falls back to plain text prompt and the designed UX is lost.
- `keyboard` and `keymap` are required because passphrase input must work with the expected layout; if omitted, unlock can fail from wrong key interpretation.
- `kms` is required because Plymouth should render correctly in early graphics mode; if omitted, rendering quality and behavior can degrade.
- `microcode` is included because CPU microcode updates should be applied early; if omitted, the system still boots but loses early mitigation/CPU-fix coverage.
- `autodetect` is included because initramfs should contain only required hardware modules for current target; if omitted, image size and boot overhead increase.
- `systemd`/`sd-encrypt` are excluded because this policy explicitly uses busybox flow in this phase; if mixed, hook logic becomes inconsistent.
- `usr` is excluded because `/usr` is not a separate early-boot mount target in this layout; if included unnecessarily, it adds no value.
- `modconf` is excluded because no early-boot module option override is currently required; if added without need, policy becomes noisier.
- `btrfs` hook is excluded because root mount in this layout is handled through `filesystems` without extra btrfs runtime requirements; if added now, it is extra surface without current need.
- `fsck` is excluded because Btrfs does not use the same boot-time fsck flow as ext filesystems; if included, it adds no useful recovery path for this design.

## Implementation Plan

1. Install required packages in target system before initramfs generation (`mkinitcpio`, `plymouth`, kernel package).
2. Write installer-selected keyboard layout to `/etc/vconsole.conf`.
3. Set the `HOOKS` line in `/etc/mkinitcpio.conf` to the decided list.
4. Generate images with `mkinitcpio -P`.
5. Validate that unlock prompt is rendered by Plymouth and that root unlock succeeds.

## Considerations

- Hook order is part of policy and must not be arbitrarily reordered.
- `plymouth` must appear before `encrypt`.
- Reference to `plymouth-encrypt` is treated as obsolete for current Arch hook set in this project.
- If initramfs policy changes to systemd later, migrate explicitly to `sd-encrypt` in a dedicated decision update.

## References
https://wiki.archlinux.org/title/Mkinitcpio
https://wiki.archlinux.org/title/Plymouth
