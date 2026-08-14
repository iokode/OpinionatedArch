# Installation Checks

What an installation is checked for, beyond finishing. `006-end-to-end-testing.md` describes the harness and what it already does — it installs from a configuration file and boots the disk it made, which answers "did it work at all". The checks here answer "did it do the right things".

Each says what it is for. A check whose reason is only "it should say so" is not worth a harness step.

## In the installed system

Run against the machine that was just installed, once it boots.


| Check                                                                                                               | What it is for                                                                                                                                                                                          |
| ------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `/etc/localtime` is a symlink into `/usr/share/zoneinfo`                                                            | The link is made through the filesystem port rather than by the host, and a symlink is one of the two operations `baml.fs` cannot do, so it goes through a command. It is the thinnest ice in the port. |
| `/etc/sudoers.d/10-wheel` is `0440 root:root`                                                                       | The other of those two operations. `sudo` refuses a sudoers file with looser permissions, so a wrong mode here is a machine whose operator cannot become root.                                          |
| `/dotfiles` is `2775 root:dotfiles`                                                                                 | The only mode in the project with a special bit. Masked to `775` it looks correct and stops doing its job: the group would no longer be inherited by what is created there.                             |
| `/dotfiles` carries a default ACL granting its group write                                                          | The modes are what the copy left; the ACL is what keeps them true for everything created afterwards, and it is invisible to `ls`. Without it the group can write only what the installation put there, which is the half of `../decisions/013-dotfiles-policy.md` nobody would notice missing. |
| Every directory under `/dotfiles` is `2775` and every file `664`                                                    | A copy carries the modes it came from, so this is the half the ACL cannot do. Wrong, the operator can read the shared configuration and change none of it.                                              |
| `/etc/gitconfig` names `/dotfiles` as a safe directory                                                              | The tree is root's and the operator is not, so git refuses to work in it without this. It is written rather than set with `git config`, so nothing else would fail if it were missing — until someone runs git there. |
| `/etc/oparch/dotfiles-sync/secrets` is `0700 root:root`, and each file in it `0600`                                 | The values in it are credentials rendered into configuration afterwards. Loosened, every work context can read every secret the dotfiles carry, which the store exists to prevent.                        |
| `ipxe` is installed                                                                                                 | The netboot binary comes from the package rather than from a download, as `../tools/oparch-installer/002-inputs-and-bootstrap-baseline.md` decides.                                                     |
| `/boot/EFI/OpinionatedArch/netbootx64.efi` is there, and its checksum equals `/usr/share/ipxe/x86_64/ipxe-arch.efi` | That the file on the EFI partition is the one the package shipped, and not something fetched.                                                                                                           |


The last one is a checksum comparison rather than a presence check on purpose: a present file proves nothing about where it came from.

## That the recovery path works

Press a key while the machine starts, choose `Netboot archiso`, and reach a root shell in the live environment it loads.

This is the check the harness explicitly cannot make, for the reason `006-end-to-end-testing.md` records: the menu is drawn on a video console the guest does not have. It matters more than its awkwardness suggests, because it is the only thing that exercises the netboot binary as a binary. Everything else about it is a checksum.

## That a failure is legible

Cut the machine's network while `pacstrap` is running, and read the screen.


| What to look for                                                      | What it is for                                                                                                                    |
| --------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| One red line naming what failed, and `Installation aborted.` under it | A failing package manager writes thousands of lines. All of them in red, at the level an operator watches at, is worse than none. |
| The screen stays                                                      | The reason has to survive being read. Behind a modal it was gone as soon as the modal was closed.                                 |
| At verbose 2, what the command wrote, in red but not shouting         | It is what to read first when something went wrong, and it is not the line that says the run stopped.                             |
| At verbose 1, the commands and the file operations as they were       | `pacstrap -K /mnt …` and `Write '/mnt/etc/hostname'`, not a sentence about them. The sentence is the phase, one level up.         |


## That the pre-boot message is drawn

Install with the return message enabled and the project's own theme, and look at what the boot splash shows.

It draws through ImageMagick, with the theme's fonts reached by an environment variable. That variable used to replace the whole environment rather than add to it, so the drawing ran with no `PATH` and no `HOME`; this is what confirms it no longer does.

`../state/001-remaining.md` records that `imagemagick`, `pango` and `noto-fonts` are not yet placed on the ISO or on the installed system. A failure here is that gap until it is ruled out, and reading it as anything else costs an afternoon.

## Both ways in

The installation is run twice: once answering the screens, and once with `--config`. They are separate paths — the configuration file is the only one that brings the sources it names before anything is written — and only the first shows the interface at all, so a check about the screen belongs to it and a check about what was installed belongs to either.

