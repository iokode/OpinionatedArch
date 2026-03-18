# 012: GRUB Boot Policy

## Context and Decision

GRUB behavior is role-specific.

`/boot` is located on the EFI system partition and remains unencrypted.

Because of that boot layout, Btrfs snapshots of `@` do not include kernel/initramfs artifacts stored in `/boot`. This trade-off is accepted.

`Netboot Arch` is implemented as an EFI chainload entry in GRUB. The installer copies a netboot EFI binary to a fixed ESP path (`/EFI/OpinionatedArch/netbootx64.efi`) and GRUB forwards control to that file.

The copied netboot EFI binary is not auto-updated by system updates.

GRUB update policy:

- GRUB package updates are handled through normal package updates.
- After GRUB package updates or menu-template changes, regenerate `grub.cfg`.
- Re-run `grub-install` when GRUB EFI payload on ESP must be refreshed.

### Laptop Profile

- `GRUB_TIMEOUT=2`
- Default boot entry: `OpinionatedArch`
Entry order:
1. `OpinionatedArch`
2. `Netboot Arch`
3. `EFI firmware`
4. `Shutdown`

### Main PC Profile

- `GRUB_TIMEOUT=-1` (unlimited)
- Base entries are the same as Laptop.
- Additional external OS entries (for example Windows on another disk) are inserted between `Netboot Arch` and `EFI firmware`.

## Why

- Role-specific GRUB behavior is required because Laptop and Main PC have different boot interaction needs; if one policy is forced on both, daily workflow is degraded on at least one machine.
- Keeping `/boot` on EFI and unencrypted is required because this design prioritizes a simple boot chain and early initramfs/Plymouth unlock flow; if `/boot` is moved inside encrypted root, boot complexity and pre-unlock prompt behavior increase.
- Accepting that `@` snapshots do not include kernel/initramfs is required because it is the direct consequence of the selected `/boot` layout; if this is not stated explicitly, rollback expectations become incorrect.
- Laptop timeout `2s` is required because Laptop does not need extra OS selection and should reach unlock quickly; if timeout is long, normal startup becomes slower without benefit.
- Main PC timeout unlimited is required because external OS selection is a real and frequent use case; if timeout auto-boots quickly, intended OS selection is missed.
- Stable entry order is required because boot menu usage must be predictable under normal and recovery conditions; if order changes, operator error risk increases.
- `Netboot Arch` entry is required because it provides a built-in recovery/install path from GRUB; if missing, fallback requires separate manual boot handling.
- A fixed ESP path for netboot EFI (`/EFI/OpinionatedArch/netbootx64.efi`) is required because GRUB chainload entries should not depend on dynamic discovery; if path is variable, entry generation and maintenance become brittle.
- Not auto-updating the copied netboot EFI binary is required because this workflow treats it as a stable recovery launcher; if it is changed implicitly during normal updates, recovery behavior can change without explicit operator intent.
- `EFI firmware` and `Shutdown` entries are required because low-level firmware access and safe power-off should be available without booting Linux; if missing, those operations become less direct.
- External OS entries only on Main PC are required because that profile hosts multi-OS usage while Laptop does not; if added everywhere, Laptop menu becomes unnecessary clutter.
- Snapshot recovery is intentionally restore-based (not snapshot boot entries) because booting snapshots adds boot-menu complexity and interacts poorly with `/boot` being outside `@`; if snapshot boot entries are enabled, recovery expectations and boot behavior become harder to reason about.
- Regenerating `grub.cfg` after GRUB package/template changes is required because menu state must match installed scripts and entries; if skipped, menu can drift from intended policy.
- Re-running `grub-install` when ESP GRUB payload needs refresh is required because package updates alone do not guarantee deployed EFI loader state is refreshed; if omitted when needed, bootloader behavior can remain outdated.

## Implementation Plan

1. Configure GRUB defaults from selected machine role (`Laptop` or `Main PC`).
2. Set role timeout (`2` for Laptop, `-1` for Main PC) and default entry (`OpinionatedArch`).
3. Generate fixed base menu entries in the specified order.
4. Add `Netboot Arch`, `EFI firmware`, and `Shutdown` entries.
5. For Main PC only, insert external OS entries between `Netboot Arch` and `EFI firmware`.
6. Copy netboot EFI binary to `/EFI/OpinionatedArch/netbootx64.efi` on ESP and create GRUB chainload entry.
7. After GRUB package/template changes, regenerate `grub.cfg`.
8. Re-run `grub-install` when ESP GRUB payload refresh is required.
9. Validate final menu order and timeout behavior.

## Considerations

- With `/boot` on EFI, rollback of `@` does not rollback kernel/initramfs.
- Kernel-update recovery is expected through live/netboot workflow and package downgrade when needed.
- Snapshot restore workflow is external to GRUB menu entries by policy.
- Netboot EFI binary lifecycle is explicit/manual by policy; updating it is a deliberate maintenance action.
