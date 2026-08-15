# Boot Image Format

**Work in progress. Nothing here is decided yet.**

This document will own the form the boot images take on the EFI system partition: which of them is a kernel and an initramfs the boot menu names separately and which is a unified image, and what keeps each of them current on a machine that has already been installed.

[Remaining](../state/001-remaining.md) carries the first half as a pending decision, as a unified kernel image for the recovery system and `vmlinuz` for OpinionatedArch. Nothing decides it today: [Disk Layout](001-disk-layout.md) lists `initramfs-linux.img`, `vmlinuz-linux` and the microcode image under `OpinionatedArch/` on the EFI system partition and says nothing about what the recovery system boots from, [Kernel](007-kernel.md) decides which kernel package is installed and not what is made of it, and [mkinitcpio Hooks](012-mkinitcpio-hooks.md) decides what goes into the initramfs and generates it with `mkinitcpio -P`.

The second half is the netboot binary, which [Remaining](../state/001-remaining.md) carries as a defect rather than as a decision. The copy at `/EFI/OpinionatedArch/netbootx64.efi` is written once by the installer and nothing refreshes it when pacman updates the package it was taken from, so the external recovery path [Bootloader](009-bootloader.md) requires ages in place, and it is first exercised on the day the machine is already broken. What refreshes it, and whether that copy belongs to the mechanism that refreshes it or to the installer that first wrote it, belongs here with the rest of what the partition carries.
