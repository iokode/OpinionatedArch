# End-to-End Testing

End-to-end tests boot this project's installation image under QEMU and let the installer inside it build a machine on a disposable disk. Everything below the installer — `pacstrap`, `arch-chroot`, `cryptsetup`, `sgdisk` — is the genuine article, and the result is verified by booting the disk that was just installed.

This document describes the harness and the cases it runs. It does not describe the installer, which is documented in [oparch-installer](../tools/oparch-installer/000-command.md).

The **harness** is neither the thing under test nor the assertions: it is what makes running them possible at all. The word is the one used for a wiring harness, the thing that connects and drives, and not for anything to do with the tools this project is written with.

## The question this answers

Does an image this project publishes install a machine that boots?

Nothing else answers it. The unit suites verify which commands the installer decides to run, against recording doubles and with no privileges, and they are thorough about it — but a decision is not an effect, and every failure that has reached a person so far was a property of the world the installer decides in rather than of the decision. A keyring that does not exist on the medium, a boot-time wait that never ends without a network, a repository whose packages carry no signatures: none of them is visible to a test that does not boot anything.

That is why this exists, and it is also the measure of it. A case that does not bear on whether a published image installs a machine that boots is worth what it costs and no more.

## Why the installer is not tested on the development machine

The installer presumes it runs inside the live installation environment. It calls `arch-chroot`, `pacstrap` and `sgdisk` without checking whether they exist, and it is meant to stay that way: environment checks scattered through the installation phases would buy test convenience with permanent complexity in the code that matters most.

Attaching a disk image to a loop device on the development machine would exercise the partitioning phase, but only there, and only by installing the live environment's tooling onto a machine that is not it. Giving the installer the environment it expects is both more faithful and less work.

QEMU is used rather than the desktop hypervisor already available because the harness has to be a command, not a session: it boots a raw image directly, exposes the guest's console as text on standard output, resets to a clean disk with a copy-on-write overlay, and runs headless. The desktop hypervisor remains the better tool for driving the interface by hand.

## The medium it boots

The image this project builds, given by path. It is an input to a test rather than part of the project — over a gigabyte of it — and which image is being tested is the whole point of the test.

Booting the image that ships is what makes a run mean something. It also makes the run hermetic and quick: the medium carries the packages an installation installs, so a case installs with no network at all, against versions that cannot move under it.

Nothing about the medium has to be arranged for. The image starts the installer on `tty1` and leaves every other console a shell, which is what the harness drives: it logs in over the serial line and types there, and the interactive installer on the first console is no more in its way than it would be for a person who switched terminals.

What runs is the installer the image carries, as it was published: its own binary, its own copy of the runtime library, its own assets. What the guest is given is the case's own files.

## The harness, the runner, and a case

Three things, kept apart because they change for different reasons.

**The harness**, `tests/e2e/harness.sh`, is the wiring. It starts a guest on the image, drives its serial console, exposes the case's files to it, asserts what is true of any completed installation, boots the disk that was made, and cleans up after itself. It contains no case and asserts nothing that is particular to one.

**The runner**, `tests/e2e/run.sh`, is the command. It takes the image, works out which cases to run, and runs each in its own guest, reporting which passed.

**A case** is a directory under `tests/e2e/cases/`, holding a `case.sh` and whatever the installation it describes has to be given. It is one installation: the harness performs one per guest, and three of the cases below are runs that are meant not to happen, so a case is a guest rather than an assertion.

### What a case declares

- **A title**, the sentence naming it in this document.
- **An outcome**, which is `installs` or `refuses`. It is what the harness holds the run to, and what decides whether the checks that follow are made at all.
- **How the installation is driven**, which is the case's own: it hands the installer a configuration file, and what is in that file is what makes one case differ from another.
- **Its own assertions**, made in the guest after the installation, about what this case is for.
- **What the guest is given**: a directory of its own, and what the installation it describes has to read is in it.

Those are four files and a directory, and every case has all of them. `case.sh` declares the title and the outcome, `drive.sh` performs the installation, `assert.sh` makes the assertions, and `share/` is what the guest can see — which is why the rest is not in it: a case's own files have no business being readable by the machine they are testing.

The configuration file is what makes a run automatable. With `--config` the installer takes over no terminal, asks nothing, and reports as plain timestamped lines a test can read.

An `installs` case is followed by the checks that belong to every completed installation — the layout on the disk, and then the disk booted on its own, asked for its passphrase, and reaching a login. They live in the harness rather than in each case because they are true of all of them, and a copy of them in every case would be a copy to drift.

A `refuses` case is the opposite claim: the installer stopped, said why, and the disk is as it was. Those runs never reach `pacstrap`, so they cost seconds where an `installs` case costs minutes.

## Shape of a run

1. Create a disposable disk with `qemu-img create`, so each case starts from the same state and leaves nothing behind.
2. Boot the image with that disk attached, the kernel and initramfs extracted from it so `console=ttyS0` can be passed on the kernel command line, and `-nographic -serial mon:stdio` so the guest's console is the harness's standard output.
3. Expose what the case gives the guest through a 9p mount, read-only.
4. Let the case drive the installer the image carries, and read the console while it does.
5. Hold the run to the outcome the case declared, make the case's assertions, and — where a machine was installed — boot the disk again without the medium, answer the passphrase, and wait for a login.

Steps 4 and 5 are what distinguish this from the unit tests.

## What driving that console is like

The guest is reached through a serial line and nothing else, and that is harder than it sounds. What is written down here is what has cost time before; none of it is a matter of taste.

- **A shell prompt does not end in a newline**, so a reader that works in lines waits for ever at exactly the moment it has arrived. What arrives has to be matched as it comes.
- **What a person reads is not what is on the wire.** The prompt comes interleaved with escape sequences and colour, so the word `archiso` a person sees is not a run of bytes to match against. The guest is asked to announce when it is done instead, and the announcement has to be a string the shell echoing the command back cannot produce by itself.
- **The terminal echoes what it is told.** Turning the echo off once does not hold: line editing puts the terminal back the way it wants it at every prompt. Only what the guest produces should come back, never what it was told to do.
- **A serial line ends a command with a carriage return**, not a newline. A newline leaves the terminal joining what should have been two commands into one.
- **Nothing waits a fixed time for `login` to hand over.** Anything typed while it still has the line is swallowed, and how long that takes is not ours to know, so the guest is asked until it answers.
- **An exit status does not survive the wire** reliably. What survived was a different word for each outcome.
- **The share is not mounted under `/mnt`**: that is where the installer mounts the system it is building, and it would be mounting over its own inputs.
- **The installed machine writes where a screen would be.** To watch it boot, its kernel has to be told to use the serial line too, and the file to say that in is the one the installer generates per machine — not the menu the project ships, which is what is being tested.

## Where it runs, and what it needs

On a machine that is running Arch. The firmware the guest boots is named by `edk2-ovmf`'s own path, which is a distribution's to move and nobody else's, so the working environment is the one this project is developed on.

What has to be installed: `qemu-system-x86_64`, `edk2-ovmf`, `libarchive` for `bsdtar`, `util-linux` for `blkid` and `procps-ng`.

The guest needs no network, which is what makes a run reproducible.

Hardware acceleration is used when `/dev/kvm` can be read and written, and the harness falls back to emulation when it cannot. The difference is not a detail: an installation that takes a minute accelerated takes long enough emulated to change what this is for.

## What this cannot see

The guest runs with `-nographic`, so there is no display for a splash. Plymouth falls back to the text prompt [Pre-Boot Ownership Message](../decisions/009-preboot-ownership-message.md) requires, which is worth knowing works, but the harness therefore never draws the composed message and never runs the script the renderer writes.

That is a limit of this harness. The splash itself was seen on 2026-08-11, on VMware and by hand: the machine booted to the return message screen, and Escape moved between it and the text prompt. A run with a display attached is what would bring that under the harness.

The boot menu is not checked either. It is reached by pressing a key while the machine starts, and GRUB draws it on the video console, which this guest does not have — so a check would be pressing keys it cannot see the effect of, and the attempt at one was still sending them when the passphrase prompt was up. That path was verified by hand instead.

## The cases

Each is one installation. The first is the one that answers the question at the top of this document; the rest are about the dotfiles step, and are written here because there is nowhere else yet — each of them is a document of its own once there is a place for test specifications, and this section goes when they move.

**A machine is installed and boots.** `installs`, from a configuration file. The smallest configuration there is: no dotfiles package, no return message, no network. It asserts nothing of its own, which is the point — what it is for is the checks every `installs` case gets, and it is the case that says whether an image is fit to publish.

**A machine is installed with a network.** `installs`. The same machine, reached the other way: the official repositories decide the versions, this project's repository sits above them, and the copies the medium carries are a cache rather than a source. Afterwards the machine carries the tools this project ships and the repository that publishes them, above the official ones and with the key they are checked against. It is the one case that is not hermetic, because what it installs is whatever Arch was serving at the moment it ran, and that is the condition it exists to test.

**A machine is installed with a return message.** `installs`. The phase with the most outside it: it writes the values, installs the Plymouth theme and runs the renderer, which draws through Pango and needs fonts to do it. The message cannot be seen from here, so what is held to is that it was made — the values on the machine, the theme installed, images drawn into it, and that theme being the one the machine boots with.

**A machine is installed with a swap file.** `installs`. A swap file on btrfs is not a file with `mkswap` run over it: the filesystem makes it itself, without copy-on-write and without compression, or the kernel refuses to swap to it. What is held to is the file where the layout puts it, being a swap area according to the kernel's own reader, and named in the mount table.

**A machine is installed with microcode.** `installs`. Microcode is loaded by the bootloader before the kernel, from a file on the EFI system partition named by the menu entry generated for that machine. What is held to is the image being where the boot reads it, nothing left where the package put it, the machine's own menu file naming it, and the hook that will move it there again at the next update.

**A configuration naming a disk that is not there is refused.** `refuses`. The earliest gate there is: a file is checked against the machine it will run on before a single value has been acted on. It costs seconds, and what it holds is that the disk the guest does have is as it was.

The rest are about the dotfiles step, and need two fixtures between them: a dotfiles package whose map declares a link, a copy and a render, and an encrypted store holding what that render references.

**A package is applied.** `installs`. The configuration names a dotfiles package. Afterwards `/dotfiles` holds what the package held; its directories are `2775` and its files `664`; the default ACL [Dotfiles](../decisions/014-dotfiles.md) requires is on it; `/dotfiles` is in git's system `safe.directory`; and each of the three operations the map declared has produced its target, owned by the user the map named.

**A repository stays a repository.** `installs`. The same run with the package taken from a `git` origin. Afterwards `/dotfiles` is a repository with its history and its remote, not a checkout of one revision.

**A map that needs secrets gets them.** `installs`. The configuration also names the encrypted store and its passphrase. Afterwards the rendered target holds the secret's value, and the store on the installed system is `0700` at its root and `0600` at each file, owned `root:root`.

**A package that does not hold what it declares is refused.** `refuses`. A map naming a file that is not in the package. The run stops before the disk is touched, and says which file and where the map says it should be.

**A passphrase that does not open the store is refused.** `refuses`. The same, stopping for that reason and saying so, with the disk equally untouched.

The last two are what makes the others worth having: they are the cases where the installation is meant not to happen, and the assertion is on the disk being as it was.

Which of them are written, and what has been run, is [What Is Built](../state/000-what-is-built.md) and [Remaining](../state/001-remaining.md).
