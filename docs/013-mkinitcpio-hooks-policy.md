# 013: mkinitcpio Hooks Policy

## Context and Decision

Initramfs uses the busybox-based flow for this project phase.

When the pre-boot return message is enabled, the configured hooks are:

```bash
HOOKS=(base udev autodetect microcode kms keyboard keymap block opinionatedarch-plymouth-locale plymouth encrypt filesystems)
```

When the pre-boot return message is disabled, the configured hooks are:

```bash
HOOKS=(base udev autodetect microcode kms keyboard keymap block encrypt filesystems)
```

The following hooks are intentionally not used in this phase: `systemd`, `sd-encrypt`, `usr`, `modconf`, `btrfs`, and `fsck`.

Plymouth must be installed in the target system before generating initramfs only when the pre-boot return message is enabled.

The `opinionatedarch-plymouth-locale` hook exports `LANG=C.UTF-8` and `LC_CTYPE=C.UTF-8` before Plymouth starts.

Keyboard layout for unlock is provided by installer input and applied through `keymap`.

## Why

- Busybox initramfs flow is used because current boot requirements are limited to LUKS + Btrfs root, plus optional Plymouth return-message rendering; if systemd initramfs is introduced now, complexity increases without a required benefit.
- `base`, `udev`, `block`, and `filesystems` are required because they provide the minimum boot path from initramfs to mounted root; if any is missing, early boot cannot complete reliably.
- `encrypt` is required because root is encrypted with LUKS; if it is missing, root cannot be unlocked during boot.
- `plymouth` is required only when the return message is enabled because that screen needs custom visual rendering; if the return message is disabled, the plain unlock prompt is sufficient.
- `opinionatedarch-plymouth-locale` is required before `plymouth` because Plymouth's FreeType label renderer decodes template text through the process locale; if Plymouth starts in the default `C` locale, UTF-8 language names and message text can render as missing glyphs even when the font contains those characters.
- `keyboard` and `keymap` are required because passphrase input must work with the expected layout; if omitted, unlock can fail from wrong key interpretation.
- `kms` is required because early graphics setup should be consistent across boot paths and supports Plymouth rendering when the return message is enabled; if omitted, rendering quality and handoff behavior can degrade.
- `microcode` is included because CPU microcode updates should be applied early; if omitted, the system still boots but loses early mitigation/CPU-fix coverage.
- `autodetect` is included because initramfs should contain only required hardware modules for current target; if omitted, image size and boot overhead increase.
- `systemd`/`sd-encrypt` are excluded because this policy explicitly uses busybox flow in this phase; if mixed, hook logic becomes inconsistent.
- `usr` is excluded because `/usr` is not a separate early-boot mount target in this layout; if included unnecessarily, it adds no value.
- `modconf` is excluded because no early-boot module option override is currently required; if added without need, policy becomes noisier.
- `btrfs` hook is excluded because root mount in this layout is handled through `filesystems` without extra btrfs runtime requirements; if added now, it is extra surface without current need.
- `fsck` is excluded because Btrfs does not use the same boot-time fsck flow as ext filesystems; if included, it adds no useful recovery path for this design.

## Implementation Plan

1. Install required packages in target system before initramfs generation (`mkinitcpio`, kernel package, and `plymouth` only when the return message is enabled).
2. Write installer-selected keyboard layout to `/etc/vconsole.conf`.
3. When the return message is enabled, write the `opinionatedarch-plymouth-locale` runtime and install hooks.
4. Set the `HOOKS` line in `/etc/mkinitcpio.conf` to the decided list.
5. Generate images with `mkinitcpio -P`.
6. Validate that root unlock succeeds, and when the return message is enabled, validate that the unlock prompt is rendered by Plymouth.

## Considerations

- Hook order is part of policy and must not be arbitrarily reordered.
- If enabled, `opinionatedarch-plymouth-locale` must appear before `plymouth`.
- If enabled, `plymouth` must appear before `encrypt`.
- Reference to `plymouth-encrypt` is treated as obsolete for current Arch hook set in this project.
- If initramfs policy changes to systemd later, migrate explicitly to `sd-encrypt` in a dedicated decision update.

## References
https://wiki.archlinux.org/title/Mkinitcpio
https://wiki.archlinux.org/title/Plymouth
