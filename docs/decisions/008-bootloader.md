# Bootloader

## Context

Arch's repositories carry several bootloaders — `grub`, `refind`, `limine`, `syslinux`, `systemd-boot`, and others — and leave the choice to whoever installs the system.

## Decision

The bootloader is GRUB.

The boot menu is hidden and the default entry, `OpinionatedArch`, is started without waiting (`GRUB_TIMEOUT_STYLE=hidden` with `GRUB_TIMEOUT=1`).

Pressing any key during that second shows the menu.

`grub-mkconfig` is not used.

The menu is one static `grub.cfg`, kept among the project's assets and installed as `/boot/OpinionatedArch/grub/grub.cfg`, where GRUB reads its files from as [Boot Image Format](007-boot-image-format.md) decides.

The menu carries nothing particular to the machine it starts: the installation writes those values beside it, in `oparch.cfg`, which the menu's first line reads.

The menu includes `custom.cfg` only if it exists where GRUB reads its files.

### Entry order

1. `OpinionatedArch`
2. `Recovery mode`
3. `Arch Netboot`
4. `EFI firmware settings`
5. `Reboot`
6. `Shutdown`

## Why

- GRUB is the chosen bootloader because it does everything this design asks of it, and it is the most mature bootloader on Linux.
- `grub-mkconfig` is not used because what it generates is a dirty, unmaintainable configuration.
- The menu is one file among the project's assets because it is then read, reviewed and changed like anything else this project owns.
- The machine's own values live in a second file so that the menu stays identical wherever it is installed.
- Startup goes to the default entry without showing the menu because what follows it is the unlock prompt carrying the return message, which [Pre-Boot Ownership Message](009-preboot-ownership-message.md) puts there for whoever finds a lost machine: a menu waiting there shows them a menu instead. The operator can turn the menu on in the GRUB configuration and keep that change in their dotfiles.
- An interrupt exists so the recovery entries stay reachable, and it is any key during the hidden second rather than a modifier held while powering on, because a modifier cannot be read here: `keystatus` needs the firmware to report which modifiers are held, and the UEFI console input this project boots from does not. A menu behind `Shift` is a menu behind nothing, and nothing about it looks broken from the outside. This project targets UEFI and does not support BIOS, so the reading that would work there is not one to keep the promise for.
- The order of the entries is fixed because an entry that moves is an entry chosen wrong.
- `Recovery mode` and `Arch Netboot` are both there because they start different things: one the recovery system on the machine's own disk, the other a live environment that needs nothing from the disk.
- `EFI firmware settings`, `Reboot` and `Shutdown` are there because the menu is already on screen, and reaching any of them otherwise means starting Linux first.
- `custom.cfg` is included so that local additions have somewhere to go that is not the project's own file.

