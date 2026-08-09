# GRUB Boot Policy

## Context

`/boot` is located on the EFI system partition and remains unencrypted.

Because of that boot layout, Btrfs snapshots of `@` do not include kernel/initramfs artifacts stored in `/boot`.

## Decision

That trade-off is accepted.

GRUB behavior is controlled by `startup_policy`.

`grub-mkconfig` is not used.

The installer uses two static `grub.cfg` versions stored under `assets/`: one for `startup_policy=automatic` and one for `startup_policy=manual`. Both versions define the same entries. The only difference is menu visibility and startup behavior. The selected version is installed as `/boot/grub/grub.cfg`.

If the shared dotfiles contain a `grub/` directory, the dotfiles synchronization tool copies that directory to `/boot`.

If `custom.cfg` exists after that synchronization, GRUB includes it.

### `startup_policy=automatic`

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
- Avoiding `grub-mkconfig` is required because this policy uses reviewed static GRUB configuration assets; if GRUB configuration is generated dynamically, menu content can drift from the project-owned source of truth.
- Two static `grub.cfg` variants are required because startup policy changes menu visibility behavior while keeping the boot entries identical; if entry definitions diverge between policies, automatic and manual installs can expose different recovery capabilities.
- `automatic` hidden timeout is required because systems that normally boot the default OS should reach unlock quickly without showing the boot menu; if the menu is shown or the timeout is long, normal startup becomes slower without benefit.
- `Shift` interrupt behavior is required so automatic startup still has an explicit operator path to the GRUB menu; if there is no interrupt path, recovery entries become harder to reach.
- `manual` unlimited timeout is required because deliberate boot selection should not be missed; if timeout auto-boots quickly, intended operator selection is lost.
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
- `startup_policy=automatic` must boot `OpinionatedArch` directly unless `Shift` is held during power-on.
- `startup_policy=manual` must show the same entries and wait for explicit operator selection.
- Any `custom.cfg` content is outside the base static `grub.cfg` source of truth.
