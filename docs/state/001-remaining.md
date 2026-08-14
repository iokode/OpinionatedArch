# Remaining

What this project does not have: decisions not taken, work not done, tools with no specification, and the defects that are known and unfixed. It is the counterpart of `000-what-is-built.md`, which is what it does have.

It is a backlog, not a specification. Nothing listed here is decided.

## Pending Decisions

- **Package baseline** — what is always installed (`base` dev tools, firmware, core tools) and what remains optional.
- **AUR policy** — whether to use `paru`, how to install it, and which build user to use.
- **Default systemd services** — which units are always enabled at install time.
- **Base security policy** — firewall, SSH (if applicable), sudo policy.
- **Real session/login strategy** — initial display manager and fallback until custom implementation exists.
- **Rebuilding the return message on an installed system** — nothing is installed for it today. The installer renders from the live medium, so an installation needs nothing on the target; but the tool reads the body of the Plymouth script, and the default template package and theme, from its assets directory, and no assets directory is put on the installed system. Until one is, editing `/etc/opinionatedarch/return-message.yaml` and running the tool again does not work there, although `../tools/oparch-return-message-render/000-command.md` describes that as the reason the tool exists apart from the installer. Deciding to support it also decides whether the package and theme the operator actually used are kept, and so whether the values file keeps naming where each came from or is rewritten to name local copies.
- **Kernel image in boot** — UKI for Recovery, vmlinuz for OpinionatedArch.

## Pending Work

- **Recovery system** — a read-only BTRFS subvolume with an Arch installation with tools to chroot the system.
- Generate archiso with the installer and the recovery scripts.
- Pack tools in pacman packages and create the oparch repository.
- Create the oparchiso image with installer.
- Remove `snapper` and `snap-pac`; replace by snapshot manager tools.
- Add a `-r|--reboot` option to the installer, to reboot when the installation finishes.
- Implement the `keep-homes` install mode. The screen offers it and the configuration file documents it, and `prepare_layout` answers it with `keep-homes install mode is not supported yet.` before touching the disk. The prompt that goes with it is missing too: which of the existing home subvolumes to preserve. `../tools/oparch-installer/002-inputs-and-bootstrap-baseline.md` lists it, and the configuration file already carries it as `preserved_work_contexts`, so a file can express what no screen asks.
- Handle long addresses in 4-languages layout and fix presentation in 2-languages and 3-languages layouts. Test 1-language layout.
- Put on the project's ISO, and on the installed system, what the tools require and the official Arch medium does not carry: `imagemagick`, `pango`, `noto-fonts`, `fontconfig` and `git`. Which tool needs which, and what each has to be able to do, is the `Requirements` section of `../tools/oparch-installer/000-command.md` and `../tools/oparch-return-message-render/000-command.md`; the work here is putting them there. Until then the end-to-end harness installs them in the guest by hand, which `../development/006-end-to-end-testing.md` records as a step that disappears when the ISO arrives. One of them has never been observed failing: whether the drawing actually breaks without `pango` is unknown, because the run that went looking failed earlier, on a live environment too old for the ImageMagick its mirrors offered.
- Write the operational tools. `oparch-installer`, `oparch-return-message-render` and `oparch-dotfiles-sync` exist; the seven specified in `../tools/` that are not those have no implementation at all. `oparch-work-context-create`, `oparch-work-context-remove` and `oparch-password-rotate` had one in `sh`, written before the language was decided and under the names the tools carried then, along with two snapshot scripts; all of them were deleted rather than carried, because a tool half-written in a language the project no longer uses is worse than one not written yet — it is found and run. Every built-in tool is written in the language `../development/000-baml-as-implementation-language.md` decides, and whether each needs a host is answered the same way as for any other, in `../development/001-host-bridge.md`. The installed system therefore has no account, password or snapshot tooling on it today, which is what makes this the first work rather than merely pending.
- Run the end-to-end harness against the dotfiles step, and write the four cases it is missing. `../development/006-end-to-end-testing.md` describes five; only the first is written, and it has never been executed. The run `000-what-is-built.md` records is the harness as it was before the dotfiles step was given to it, so nothing has yet run the harness in the shape it is in now. The other four are a repository that stays one, a map whose secrets arrive, a package that does not hold what it declares, and a passphrase that does not open the store. Three of them are runs that are meant not to happen, and the harness performs one installation per invocation, so covering them is a change to its shape rather than four more assertions.
- Check an installed machine against `../decisions/013-dotfiles-policy.md`. The dotfiles step has been exercised by hand as far as its targets landing, but what it leaves `/dotfiles` as has not been looked at on a booted system: the modes under it, the default ACL, whether a work context can write there, and whether git works in it without complaining about who owns it. The same for the secret store's own `0700` and `0600`. `../development/007-installation-checks.md` lists all of them; none has been observed.
- Take a dotfiles package from a `git` origin and from a `tar` origin at least once. Only `local` has been exercised. The `git` one matters most: it is the only origin cloned with its history, because `/dotfiles` stays the repository `../decisions/001-disk-layout.md` restores from, and that the history and the remote survive the copy into the target has unit coverage and nothing else.

## Tools Pending Specification

- `**oparch-network-manager**` — wifi and wired network manager.
- `**oparch-pacman**` — browser across pacman repositories and package installer.
- `**oparch-aur**` (with PKGBUILD analytics) — browser across AUR repository, PKGBUILD inspector (LLM-based) and package installer, using `paru`.
- `**oparch-secret-export**` — writes the local dotfiles secret store out as one encrypted archive. The installer takes such an archive as an input when the dotfiles map declares secrets, so it is how a machine gets its credentials before first boot without every token being typed at the console. The archive is meant to travel on a removable medium or from a URL, which is what its encryption has to hold up. What it is encrypted with, and whether restoring a store is this tool or a second command, are part of its specification.

## Recovery Tools Pending Specification

- `**oparch-chroot**` — select disk where oparch is installed, mount it and chroot it.
- `**oparch-snapshot**` — snapshot browser and restorer.

## Issues

- The netboot binary on the EFI system partition is copied once, during installation, and nothing refreshes it afterwards. `../tools/oparch-installer/002-inputs-and-bootstrap-baseline.md` puts `/EFI/OpinionatedArch/netbootx64.efi` there from `/usr/share/ipxe/x86_64/ipxe-arch.efi`, but when pacman later updates `ipxe` the copy stays at whichever build the installation took. So the external recovery path that `../decisions/007-grub-boot-policy.md` requires ages in place, and it ages unnoticed: it is the path used when the machine is already broken, which is the moment it is first exercised. The drift is older than the package it now comes from — the download it replaced never tracked its source either, and left nothing on the machine to refresh from. What is new is that the source is now installed on the target, so the copy can be refreshed at all; a pacman hook on `ipxe` is the obvious candidate, and choosing it also decides whether the ESP copy is owned by the hook or by the installer that first wrote it.
- A successful installation shows red lines that mean nothing went wrong. The log paints `Said::Complaint` red, and a complaint is defined as whatever a command wrote to standard error — but writing to standard error is not how a program says it failed, it is where plenty of them put everything that is not their output. `mkinitcpio` reports possibly missing firmware there, and `grub-install` announces `Installing for x86_64-efi platform.` and `Installation finished. No error reported.` there too, so the end of a run that worked is a column of red. The rule to fix is `stderr means failure`, not any one command. Painting complaints yellow and leaving red to `Said::Failed` is a line and is most of the truth; colouring them by the exit code of the command that produced them would be the whole of it, and costs more, because the lines are pushed as they stream and the code is not known until after the last one.
- There are two ways to run a command. A caller either calls the shell port directly, or calls `run_in` with a target, and nothing says which is meant where: the installer uses `run_in` because it works on a system it is not running on, and the tools that only ever work on their own machine call the port. One way would be for `run_in` to be the only door and the port's `capture` to be the primitive that only it calls, so that every command says where it runs and a tool that later gains a second root changes what target it passes rather than needing every call found. It is not urgent — no tool is at risk of running a command against the wrong root today — and the cost is one argument at every call site.

