# 012: GRUB Boot Policy

## Context and Decision

GRUB behavior is controlled by `startup_policy`.

`/boot` is located on the EFI system partition and remains unencrypted.

Because of that boot layout, Btrfs snapshots of `@` do not include kernel/initramfs artifacts stored in `/boot`. This trade-off is accepted.

`Netboot Arch` is implemented as an EFI chainload entry in GRUB. The installer copies a netboot EFI binary to a fixed ESP path (`/EFI/OpinionatedArch/netbootx64.efi`) and GRUB forwards control to that file.

The copied netboot EFI binary is not auto-updated by system updates.

GRUB update policy:

- GRUB package updates are handled through normal package updates.
- After GRUB package updates or menu-template changes, regenerate `grub.cfg`.
- Re-run `grub-install` when GRUB EFI payload on ESP must be refreshed.

### `startup_policy=automatic`

- `GRUB_TIMEOUT_STYLE=hidden`
- `GRUB_TIMEOUT=1`
- Default boot entry: `OpinionatedArch`
- Normal startup does not display the menu.
- Holding the GRUB interrupt key during the hidden timeout shows the menu.

Entry order:
1. `OpinionatedArch`
2. `Netboot Arch`
3. `EFI firmware`
4. `Shutdown`

### `startup_policy=manual`

- `GRUB_TIMEOUT_STYLE=menu`
- `GRUB_TIMEOUT=-1` (unlimited)
- Default boot entry: `OpinionatedArch`
- The menu is shown and waits for explicit operator selection.
- Base entries are the same as `automatic`.

## Why

- Startup-policy-specific GRUB behavior is required because installation targets have different boot interaction needs; if one policy is forced on all targets, daily startup or deliberate boot selection is degraded on at least one machine.
- Keeping `/boot` on EFI and unencrypted is required because this design prioritizes a simple boot chain and early initramfs/Plymouth unlock flow; if `/boot` is moved inside encrypted root, boot complexity and pre-unlock prompt behavior increase.
- Accepting that `@` snapshots do not include kernel/initramfs is required because it is the direct consequence of the selected `/boot` layout; if this is not stated explicitly, rollback expectations become incorrect.
- `automatic` hidden timeout is required because systems that normally boot the default OS should reach unlock quickly without showing the boot menu; if the menu is shown or the timeout is long, normal startup becomes slower without benefit.
- `automatic` uses `GRUB_TIMEOUT=1` instead of `0` because GRUB needs a small interruption window to reveal the menu when operator access is needed; if the timeout is zero, interruption may be unreliable.
- `manual` unlimited timeout is required because deliberate boot selection should not be missed; if timeout auto-boots quickly, intended operator selection is lost.
- Stable entry order is required because boot menu usage must be predictable under normal and recovery conditions; if order changes, operator error risk increases.
- `Netboot Arch` entry is required because it provides a built-in recovery/install path from GRUB; if missing, fallback requires separate manual boot handling.
- A fixed ESP path for netboot EFI (`/EFI/OpinionatedArch/netbootx64.efi`) is required because GRUB chainload entries should not depend on dynamic discovery; if path is variable, entry generation and maintenance become brittle.
- Not auto-updating the copied netboot EFI binary is required because this workflow treats it as a stable recovery launcher; if it is changed implicitly during normal updates, recovery behavior can change without explicit operator intent.
- `EFI firmware` and `Shutdown` entries are required because low-level firmware access and safe power-off should be available without booting Linux; if missing, those operations become less direct.
- `startup_policy` controls menu visibility and wait behavior only; it does not define machine type or external OS presence.
- Snapshot recovery is intentionally restore-based (not snapshot boot entries) because booting snapshots adds boot-menu complexity and interacts poorly with `/boot` being outside `@`; if snapshot boot entries are enabled, recovery expectations and boot behavior become harder to reason about.
- Regenerating `grub.cfg` after GRUB package/template changes is required because menu state must match installed scripts and entries; if skipped, menu can drift from intended policy.
- Re-running `grub-install` when ESP GRUB payload needs refresh is required because package updates alone do not guarantee deployed EFI loader state is refreshed; if omitted when needed, bootloader behavior can remain outdated.

## Implementation Plan

1. Configure GRUB defaults from selected `startup_policy` (`manual` or `automatic`).
2. Set `automatic` to hidden menu with `GRUB_TIMEOUT=1`, or `manual` to visible menu with `GRUB_TIMEOUT=-1`.
3. Generate fixed base menu entries in the specified order.
4. Add `Netboot Arch`, `EFI firmware`, and `Shutdown` entries.
5. Copy netboot EFI binary to `/EFI/OpinionatedArch/netbootx64.efi` on ESP and create GRUB chainload entry.
6. After GRUB package/template changes, regenerate `grub.cfg`.
7. Re-run `grub-install` when ESP GRUB payload refresh is required.
8. Validate final menu order, visibility, interruption, and timeout behavior.

## Considerations

- With `/boot` on EFI, rollback of `@` does not rollback kernel/initramfs.
- Kernel-update recovery is expected through live/netboot workflow and package downgrade when needed.
- Snapshot restore workflow is external to GRUB menu entries by policy.
- Netboot EFI binary lifecycle is explicit/manual by policy; updating it is a deliberate maintenance action.
- For UEFI GRUB, `Esc` is the expected interrupt key for revealing a hidden menu.
