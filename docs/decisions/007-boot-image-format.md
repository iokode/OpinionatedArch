# Boot Image Format

## Context

The images a machine starts from are read by the firmware before anything is decrypted. Two systems start from them: the installed one, and the one that has to start when the installed one will not.

## Decision

The installed system boots from a kernel image and an initramfs kept apart, `vmlinuz-linux` and `initramfs-linux.img`, with the microcode image beside them, under `OpinionatedArch/` on the EFI system partition as [Disk Layout](001-disk-layout.md) lays it out.

The recovery system boots from a unified kernel image: one EFI executable at `EFI/OpinionatedArch/recovery.efi`, carrying its own kernel, initramfs and command line.

The installation registers three EFI boot entries, in order: GRUB, the recovery image, and the netboot binary.

### What keeps each of them current

The kernel image and the initramfs are rewritten under `OpinionatedArch/` on every kernel update.

The recovery image is built when that system is installed.

The microcode image is installed by its own package at a path that belongs to the package, so a pacman hook moves it into `OpinionatedArch/` in the same transaction that installs and updates it. It is moved, not copied.

The netboot binary is a copy of what the `ipxe` package carries, remade by a pacman hook whenever that package changes. The installation writes it the first time.

GRUB's own executable, `EFI/OpinionatedArch/grubx64.efi`, and the modules it loads from `OpinionatedArch/grub/`, are made by `grub-install`: the `grub` package puts neither on the partition. A pacman hook runs it again whenever that package changes. The menu is not touched by it: that file is an asset of this project, as [Bootloader](008-bootloader.md) decides.

## Why

- The installed system boots what its own updates leave behind: the kernel image and the initramfs are rewritten on every kernel update, so what the machine starts from is current with nothing of this project in between. It is also how an Arch system is normally arranged, and this machine is one. Its command line lives in the menu, where it can be changed at the one moment that matters — in front of a machine that will not start.
- The recovery system is one image so that starting it depends on nothing else on the machine that could be broken.
- The recovery image and the netboot binary get entries of their own because both are paths taken when GRUB is not there to take them.
- The artifacts live under a directory of the project's own rather than at the root of the partition because a system snapshot takes the whole directory, as [Snapshots](004-snapshots.md) requires, and whatever else the partition holds is not this project's to copy.
- The microcode is moved rather than copied because two identical images on the partition are two answers to which one boots.
- The netboot binary is refreshed by a hook because an update of its package would otherwise change what the copy was made from and not the copy. It is copied rather than moved because what it comes from belongs to the package and lives outside the partition.
- GRUB is installed again on each update of its package so that what starts the machine is the version installed on it: a fix that reaches the package — a corrected bug as much as a closed vulnerability — otherwise does not reach the artifact every start goes through. What argues against it is an update leaving a machine that will not start, and that risk is already answered: `recovery.efi` is a boot entry of its own, and reinstalling GRUB from there is the repair.

## Considerations

- pacman keeps naming the microcode image at the path its package installs it to. Every update puts it back there and the hook moves it again, which is what makes this work; `pacman -Qkk` reports the file as missing, and removing the package leaves the moved one behind.

