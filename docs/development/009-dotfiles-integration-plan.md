# Dotfiles Integration Plan

`oparch-dotfiles-sync` exists and the installer collects a dotfiles package, but nothing joins the two: `tools/oparch-installer/003-input-sources.md` still says that nothing consumes the package, and `remaining.md` records that an installation answered by hand does not even fetch it. This plan is how that gap closes — where the step goes, how the package gets to `/dotfiles`, how it is judged before the disk is touched, and what a map that needs credentials does about them.

This is a plan, so it is finite: when the work described here is done, this document is deleted rather than maintained.

## The step, and why it is last

One phase is added, after the bootloader, present only when a dotfiles package was chosen — the same way the return message adds its own phase only when one was asked for, and for the same reason: a list that shows a phase that will not run lies about how much is left.

Last is not a preference. Three things ahead of it are inputs to it:

- **Users and groups.** The tool expands user targets over the members of the `dotfiles` group and their home directories. Before that phase there is no group and there are no homes.
- **Packages.** A map installs the packages it declares, with pacman, into the target.
- **Bootloader.** `decisions/007-grub-boot-policy.md` has the tool copy a `grub/` directory from the dotfiles to `/boot`, and has GRUB include `custom.cfg` if it exists *after* that synchronization. `grub-install` and the static menu are written by the bootloader phase; what the dotfiles add goes on top of them.

Nothing ahead of it depends on it in return. The initramfs is the one candidate, and it is not: the `HOOKS` line belongs to `decisions/008-mkinitcpio-hooks-policy.md` and the Plymouth theme to the return-message phase, neither of which reads the dotfiles.

Being last means its failure comes after a bootloader is already installed. That changes nothing about what a failure means: by the all-or-nothing rule in `AGENTS.md`, the run stops and the machine is not one to boot.

## Getting the package here

The package is brought into the live staging directory while the form is still being answered, and copied into `/mnt/dotfiles` by the phase. It is not fetched straight into the target, for two reasons that have nothing to do with convenience: when the question is asked there is no target yet, and a `local` origin may name a medium that will be unmounted or a disk that is about to be erased. That is the same reasoning already written into `bring_here`, and the template package and the theme already work this way.

A `git` origin is cloned. `/dotfiles` is itself a repository — `decisions/001-disk-layout.md` makes restoring it a Git operation — so what is copied into the target has to be a repository with its history, not a shallow checkout. `bring_here` clones `--depth 1` today, which is right for a template package and a theme, where a history is not the content. It has to stop being uniform: the dotfiles package keeps its history and the other two do not.

The copy carries `.git` with everything else, so the history and the remote survive it. What decides whether they are there is the clone, not the copy.

An origin that is not a repository leaves no repository behind. A package taken as a directory or an archive lands in `/dotfiles` as files, and the restore path `decisions/001-disk-layout.md` describes does not exist on that machine until someone makes it one. That is a consequence of the origin the operator chose, not something the installer can supply.

The copy into `/mnt/dotfiles` happens after the users phase has created `/dotfiles` as `2775 root:dotfiles`, so the setgid bit gives the copied tree its group. `development/007-installation-checks.md` already checks that mode.

The group is not the whole of it. Setgid carries the group downwards and not the permission to write, and `cp -r` gives what it copies the modes the source had — `755` directories and `644` files, for a clone. A tree copied that way is one a login user can read and not change, under a mount point whose `2775` says otherwise.

`decisions/013-dotfiles-policy.md` decides what that has to end up as, and it takes three things from the installation: the default ACL on `/dotfiles`, the modes of what the copy brings, and `/dotfiles` in git's `safe.directory` on the installed system. Btrfs carries ACLs with no mount option, so nothing about the disk phase changes.

## Judging it while there is still someone to ask

A package is rejected at the form, not at the end of the installation. What makes that possible is that the validator is the tool itself: the installer runs the packed `oparch-dotfiles-sync` with `--dry-run` against the staged package, and a non-zero exit is a package the operator is asked to replace.

The tool already reports everything the rejection needs. A map that does not parse, a version it does not implement, an `include` that is not there, a source that is missing, a symlink or special file where a regular one was declared, a path escaping the package, a render source that is a directory, a reference to an undeclared value, a secret whose store file is absent — all of them are diagnostics from `build_plan`, and all of them are produced before anything is applied. No second implementation of the format is needed anywhere, and the installer does not link the tool's namespace.

What is judged is **this machine's plan**: rules whose selectors do not match this hostname or these users are not expanded, so their sources are not checked. That is what `tools/oparch-dotfiles-sync/001-map-format.md` already specifies, and it is what makes a package shareable — a public package describes machines that are not this one, and demanding that every file and every secret in it be present here would make it unusable everywhere.

## Telling the tool which machine to plan for

At form time the plan has to be built for a machine that does not exist yet. The tool gains two optional inputs for that:

- `--hostname <name>`
- `--user <name>`, repeatable

Given none, it reads the machine it is running on, as it does today: `/etc/hostname` and the members of the `dotfiles` group. Given any `--user`, the group is not consulted at all — a machine described half from arguments and half from the system is worse than either.

One name is enough per user because `decisions/000-user-model-and-account-types.md` now fixes the home directory and the primary group as derivable from it.

These arguments describe a machine; they do not aim the tool at one. What it writes, it still writes into its own root, which is what `development/008-acting-on-another-system.md` requires. They also earn their keep outside the installer: a map can be checked for a machine that is not the one at hand, or for the hostname a machine is about to be given.

## Secrets

A map may declare secrets, and the store they are read from is not populated on a machine being installed. Skipping the rules that need them is not available: `tools/oparch-dotfiles-sync/001-map-format.md` rules it out in as many words, and the all-or-nothing rule rules it out again.

So the store arrives as an input, like every other piece of content the operator points at: **one encrypted archive**, decrypted with a passphrase given at the form. Typing one passphrase is the cost; typing every token is what it replaces. `remaining.md` carries the tool that produces such an archive.

It is one file, so it is asked for as one: the two origins a file has, and the picker that walks to a file rather than the one that walks to a directory or an archive. Its extension is `.dfsec`, beside `.dfmap`. Unlike the map, it is identified by its name alone — a map is recognised by the header at its first byte, and an encrypted archive has no content to be recognised by.

**Which secrets a package needs is asked of the tool.** It gains a mode that builds this machine's plan, does not care whether any store file exists, and prints what the plan requires: one store-relative path per line, `global/<name>` or `user/<username>/<name>`. An empty answer means the package needs no archive and the operator is not asked for one. A non-empty answer is also the list of what the archive has to contain, which is what the operator is told when it turns out not to contain it. An exit code would carry the same yes-or-no for the same flag and none of that.

The passphrase needs no confirmation field. Unlike the shared secret, a wrong one is caught immediately — the archive does not open — so it is asked once and asked again if it fails.

Decryption happens **in the host**, through the `age` crate, behind a port of its own: `Secrets`, with one method, `unseal` — the archive, the passphrase, where to put what comes out, and the failure or nothing. It is named for what it opens rather than for what opens it, so replacing `age` later is a change to the host and to nothing else.

It has to be the host because BAML's standard library carries no cryptography at all — no cipher, no hash, no digest — and because the `age` binary cannot be driven from a program: it takes the passphrase from a terminal and from nowhere else, and given one it prints its prompt over whatever is on screen and waits. The crate reads the same archives, needs no terminal, no subprocess and no package on the ISO, and returns a typed error for a wrong passphrase. The port is what keeps this from being a decision about the host: nothing above it can tell what is underneath, which is the property `development/004-host-bridge.md` selects hosts for.

The decrypted store is staged in the live system's `/tmp`, which is memory, so a plaintext store never reaches a disk. It is validated by the same `--dry-run`, with `--secrets-root` pointing at it, and copied into the target as `0700` on the store root and `0600` on each file, `root:root`, as the map format requires. `development/007-installation-checks.md` gains a row for that.

## Running it

The tool is entered, not aimed: the phase runs `arch-chroot /mnt oparch-dotfiles-sync` with no arguments, so inside the chroot the hostname, the group, the homes and `/dotfiles` all mean what they say. This is `development/008-acting-on-another-system.md`, and it is why the machine parameters above exist for validation and not for application.

Being entered means being installed in what is entered. Until the tools ship as packages from their own repository — `remaining.md` carries that — the installer copies the packed binary into the target before entering it, from the live medium, where it arrives beside the installer exactly as `oparch-return-message-render` already does.

## What changes

**In the installer.**

- A new phase file, added to `install_phases`, `install_phase_names` and `run_phases`, conditional on a dotfiles package. It copies the package in, leaves `/dotfiles` as `decisions/013-dotfiles-policy.md` requires — the default ACL, the modes, the `safe.directory` entry — and then enters the target and runs the tool.
- The form's dotfiles screen gains the fetch it never had, the validation run, and the secrets archive with its passphrase.
- `bring_every_source` stops being reachable only from the configuration-file path, which is the defect `remaining.md` records.
- `bring_here` stops cloning every origin shallow.
- The `Secrets` port, with its recording double beside the others.

**In the tool.** `--hostname`, `--user`, `--secrets-root`, and the mode that lists the secrets a plan requires. No change to what is validated or in which order.

**In the host.** The `age` crate, and the implementation of the new port.

**In the documentation.** The tool's command document gains its new parameters, and a document of its own for the `.dfsec` archive beside the one for the map. The installer's input documents gain the secrets archive, record that a dotfiles clone keeps its history where a package clone does not, and lose the sentence saying nothing consumes the dotfiles package. The configuration file format gains the archive and its passphrase — in clear text, beside `shared_secret`, which that document already warns makes the file as sensitive as what it contains. `development/004-host-bridge.md` records that the bridge now carries one thing that is neither a terminal nor a command, and why. `development/007-installation-checks.md` gains the secret store's modes and what `decisions/013-dotfiles-policy.md` requires of `/dotfiles`. `remaining.md` loses the issue about the package never being fetched.
