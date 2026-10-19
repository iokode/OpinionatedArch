# Trying a Working Tree

How a change to the tools is tried by hand before it is merged: an image that carries the installer built from the working tree, and two scripts that boot it in a window, one to try the installer and one to try the tools on a machine it installed. They belong to the project's working environment. Nothing here is published, and none of it is a test: the tests are [End-to-End Testing](006-end-to-end-testing.md).

## The debug image

`archiso/debug/build.sh <directory>` builds it and leaves it in that directory. It builds the tools it carries first, so what the image carries is the working tree as it is when the script runs.

The image is assembled the way the published one is, as [Building and Publishing](008-building-and-publishing.md) describes: a profile of archiso's, copied as it is on the day, with the differences kept in `archiso/debug/` applied over it. The profile is `baseline`, which boots and carries little else. On top of it the image gets:

- the packages the tools it carries call and the dependencies their packages declare, but not the packages themselves;
- the installer, the interactive installer with its wrapper, and the two tools the installer calls, the renderer and the dotfiles tool, built from the working tree and put where their packages put them, with the BAML runtime library of the toolchain `Cargo.lock` names, fetched the way the `setup-baml` action fetches it;
- the assets, where their package puts them;
- from `releng`: root's shell, the autologin on the first console that starts the interactive installer with the same `.zprofile` the published image carries, the keyring made at boot, and the mirrorlist with its servers uncommented;
- a repository of every package defined under `packages/`, `oparch-debug`, each built from the working tree the way the publish workflow builds it, as [Building and Publishing](008-building-and-publishing.md) describes: what the package packages is built from the working tree and put beside a copy of its `PKGBUILD`, and `makepkg` packages it. The tool a package carries is the one its name gives, `tools/<entity>/<action>/` for `oparch-<entity>-<action>`, packed with `baml pack`, or built with its host when it has one;
- the project's signing key, trusted, and a live `pacman.conf` with `oparch-debug` first, the project's repository after it and the official ones after that. `oparch-debug` is not signed, and is listed with `SigLevel = Never`, as the published image lists its own.

Its repository holds only the packages of the working tree, so an installation made from it needs a network. It boots UEFI only, and its root filesystem is compressed to be built quickly rather than to be small.

It builds as any user: `mkarchiso` runs its steps in a user namespace when it is not root. Its work directory is under `~/.cache` rather than `/tmp`, and is removed when the build ends.

## `scripts/vm-installer.sh`

Builds the debug image and boots it in a window, on a new disk, so the installer that opens on the first console is the one in the working tree.

Rebooting the live system closes the window and opens one that boots the disk it installed. Powering it off, or closing the window, ends the script. `scripts/vm-installer.sh --disk` boots the disk the last installation left, without building anything.

What it keeps is in `~/.cache/oparch-vm-installer`: the image, the disk and its firmware variables, and what the live system wrote on its serial line.

## `scripts/vm.sh`

Installs a machine from the debug image and boots it in a window. The machine gets what the installer installs, and the project's packages among it come from `oparch-debug`, so they are the working tree's. Every run installs the machine again, on a new disk:

1. The debug image is built.
2. It boots in a window, and the script drives it over its serial line with `scripts/lib/guest.sh`. The first console, which is what the window shows, runs the unattended installer from the image and nothing else.
3. The installer installs the machine with the answers in `scripts/vm-config.yaml`.
4. The image's `oparch-debug` is copied into the machine, to the path it has on the image, and listed in the machine's `pacman.conf` ahead of every other repository.
5. The live system powers off, and a window opens on the installed disk.

A package of the project the installation does not install is installed on the running machine with `pacman -S`, and comes from `oparch-debug` like the rest: the working tree's, with the units and hooks it ships and what it depends on.

`scripts/vm-config.yaml` is a configuration file in the format [Installer Configuration File Format](../tools/installer/unattended/001-config-file-format.md) defines, and the machine is whatever it answers: its work contexts, its shared secret, its keymap, timezone and hostname. The disk asks for the shared secret, and every work context logs in with it. Before the window opens on the installed disk, `vm.sh` says which secret and which work contexts those are.

What it keeps is in `~/.cache/oparch-vm`: the image, the disk and its firmware variables, and what the live system wrote on its serial line, where a failed installation leaves the installer's output.

## What they need

Beyond what the tools need to be built:

- `qemu-system-x86_64` with a window to draw in, which on Arch is `qemu-ui-gtk`, and `edk2-ovmf` for the firmware;
- `/dev/kvm`, without which the guest is emulated and slow;
- `archiso`, `grub` and `jq` for the image, `libarchive` for `bsdtar` and `util-linux` for `blkid`;
- `makepkg` and `repo-add`, which `pacman` carries, and `fakeroot`, for the packages the debug image carries.

## Why

- The image is built rather than the published one downloaded because building it takes under half a minute once the packages are in the machine's cache, where the published image is nearly three gigabytes and a new one is published every day. And an image that carries the tools starts the installer from the working tree the way the published one starts its own, where tools put into a running live system replace an installer that has already started.
- `oparch-debug` comes first in the live system's `pacman.conf`, and in the `pacman.conf` of a machine `vm.sh` installs, because `pacstrap` and `pacman` take a package from the first repository that carries its name. Every package of the project installed there that the working tree defines is then the working tree's: one the published repository does not hold yet installs at all, and one it does hold is the working tree's and not the published one.
- The debug image is built from `baseline` and the published one from `releng` because this one runs in a virtual machine: the firmware and hardware tools `releng` brings are for real machines, and nothing uses them here. The published image stays on `releng`, as [Installation ISO](../decisions/018-installation-iso.md) decides.
- A machine is installed inside a guest rather than written onto a disk image from the development machine because the installer presumes the live environment, for the reasons [End-to-End Testing](006-end-to-end-testing.md) gives, and because some of what it does acts on the machine it runs on: `efibootmgr` writes the firmware's boot entries and `hwclock` sets the hardware clock. Inside a guest those are the guest's.
- `vm.sh` installs again every run so that the machine it boots is always what the installer in the working tree makes, and never a machine an earlier run left.
- The machine keeps its own copy of `oparch-debug` because the live medium is gone once it boots, and the packages an installation does not install are installed on the machine afterwards. They are installed as packages because a package brings more than its files: a unit it enables, a hook, what it depends on. What is tried is then what the published package would put on a machine.
- The live system is given its kernel and initramfs from outside the firmware's boot because that is what makes its serial line a console, which `vm.sh` drives the installation through and `vm-installer.sh` reads a reboot from. A guest booted that way starts the same kernel again on every reset, which is the live system and never the disk, so `vm-installer.sh` runs it with QEMU told not to reset, and tells a reboot from a power off by what the kernel wrote on the serial line before it stopped.
- `vm.sh` masks the first console's login on the kernel command line because that login starts the interactive installer, which would fill the window until the serial line answers. The mask is removed before the installation, because systemd keeps it under `/run` and `pacstrap` gives the target the live system's `/run`: left there, it stops the `systemd` package enabling the login on the installed system's first console. The live console is not affected by its removal, because systemd read the mask when the system started.

## Considerations

- The debug image cannot try an installation without a network: its repository holds only the packages of the working tree, and the image carries no configuration for installing from that repository alone, which is what the interactive installer looks for before it offers going on without one.
- What these scripts try is the tools and the installer, not the published image: the package definitions, the `releng` profile and the signatures are what [End-to-End Testing](006-end-to-end-testing.md) runs against.
- The copy of `oparch-debug` on a machine `vm.sh` installed is the working tree as it was when the image was built, and nothing updates it.
- A build that is killed before it removes its work directory leaves it under `~/.cache` as `oparch-debug-image.*`, owned by the IDs of the namespace it ran in. `unshare --map-auto --map-root-user rm -rf` removes it.
