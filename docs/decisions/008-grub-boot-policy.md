# GRUB Boot Policy

## Context

`/boot` is located on the EFI system partition and remains unencrypted.

Because of that boot layout, Btrfs snapshots of `@` do not include kernel/initramfs artifacts stored in `/boot`.

## Decision

That trade-off is accepted.

The boot menu is hidden and the default entry is started without waiting.

`grub-mkconfig` is not used.

The installer uses one static `grub.cfg` stored under `assets/`, installed as `/boot/grub/grub.cfg`.

If the shared dotfiles contain a `grub/` directory, the dotfiles synchronization tool copies that directory to `/boot`.

If `custom.cfg` exists after that synchronization, GRUB includes it.

- `GRUB_TIMEOUT_STYLE=hidden`
- `GRUB_TIMEOUT=1`
- Default boot entry: `OpinionatedArch`
- Normal startup does not display the menu.
- Holding `Shift` while powering on the device shows the menu instead of booting directly.

Entry order:
1. `OpinionatedArch`
2. `Recovery mode`
3. `Netboot archiso`
4. `EFI firmware settings`
5. `Reboot`
6. `Shutdown`

## Why

- A single startup behaviour is used because an unattended boot is what the design needs everywhere: the pre-boot return message exists so that whoever finds a lost machine sees ownership details, and a menu that waits indefinitely shows a boot menu instead. Anyone who wants the menu can enable it by editing the GRUB configuration, and can keep that change in their dotfiles.
- Keeping `/boot` on EFI and unencrypted is required because this design prioritizes a simple boot chain and early initramfs/Plymouth unlock flow; if `/boot` is moved inside encrypted root, boot complexity and pre-unlock prompt behavior increase.
- Accepting that `@` snapshots do not include kernel/initramfs is required because it is the direct consequence of the selected `/boot` layout; if this is not stated explicitly, rollback expectations become incorrect.
- Avoiding `grub-mkconfig` is required because this policy uses reviewed static GRUB configuration assets; if GRUB configuration is generated dynamically, menu content can drift from the project-owned source of truth.
- One static `grub.cfg` is required because the menu is a designed artifact rather than generated output; if it were generated, menu content could drift from the project-owned source of truth.
- A hidden timeout is required because a system that normally boots the default entry should reach unlock quickly without showing the boot menu; if the menu is shown or the timeout is long, normal startup becomes slower without benefit.
- `Shift` interrupt behavior is required so startup still has an explicit operator path to the GRUB menu; if there is no interrupt path, recovery entries become harder to reach.
- Stable entry order is required because boot menu usage must be predictable under normal and recovery conditions; if order changes, operator error risk increases.
- `Recovery mode` and `Netboot archiso` entries are required because local recovery and external live-boot recovery are different incident paths; if either is missing, some recovery workflows require separate manual boot handling.
- `EFI firmware settings`, `Reboot`, and `Shutdown` entries are required because firmware access, restart, and safe power-off should be available without booting Linux; if missing, those operations become less direct.
- Dotfiles-provided `grub/` synchronization is required so machine/project custom GRUB additions have one managed source; if copied manually, `/boot` can drift from the dotfiles state.
- Optional `custom.cfg` inclusion is required because local GRUB extensions must remain possible without editing the static base assets; if omitted, every local addition requires modifying the base `grub.cfg` source.
- Snapshot recovery is intentionally restore-based (not snapshot boot entries) because booting snapshots adds boot-menu complexity and interacts poorly with `/boot` being outside `@`; if snapshot boot entries are enabled, recovery expectations and boot behavior become harder to reason about.

## Considerations

- With `/boot` on EFI, rollback of `@` does not rollback kernel/initramfs.
- Kernel-update recovery is expected through the recovery workflow and package downgrade when needed.
- Snapshot restore workflow is external to GRUB menu entries by policy.
- Startup must boot `OpinionatedArch` directly unless `Shift` is held during power-on.
- Any `custom.cfg` content is outside the base static `grub.cfg` source of truth.
