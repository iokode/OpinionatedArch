# Reviewing

Tracking for the branch of work that puts the repository in order. One heading per document read through, holding what its review turned up that is still to do. What is already applied leaves this file. What was done to the repository before any document was reviewed is at the top, under no document, because it belongs to none.

This file is temporary. When the branch is done it goes.

## Index

Every document, ticked when its review is called done. Only the operator ticks a box. A document with a heading below it has notes, which says nothing about whether it is finished.

**General**

- [x] What is OpinionatedArch
- [x] Operating Model
- [ ] Installation Overview

**Decisions**

- [x] Work Contexts and Accounts
- [x] Disk Layout
- [x] Encryption
- [x] Swap
- [x] Snapshots
- [x] Localization and Time
- [x] Kernel
- [x] Boot Image Format
- [x] Bootloader
- [x] Pre-Boot Ownership Message
- [x] mkinitcpio Hooks
- [x] Recovery — work in progress, nothing decided yet
- [x] Network Stack
- [x] Audio Stack — work in progress, nothing decided yet
- [x] Dotfiles
- [x] Oparch Tools

**Tools**

- [ ] oparch-installer, and its configuration file, inputs and input sources
- [ ] oparch-return-message-render, and its package, values and theme formats
- [ ] oparch-dotfiles-sync, and its map format and secret store archive
- [ ] oparch-work-context-create
- [ ] oparch-work-context-remove
- [ ] oparch-snapshot-system-create
- [ ] oparch-snapshot-work-context-create
- [ ] oparch-snapshot-restore
- [ ] oparch-password-rotate
- [ ] oparch-password-rotate-interactive

**Development**

- [ ] BAML as Implementation Language
- [ ] Host Bridge
- [ ] Repository Layout
- [ ] Where a Command Runs
- [ ] Acting on Another System
- [ ] BAML Working Notes
- [ ] End-to-End Testing
- [ ] Installation Checks

**Plans**

- [ ] Dotfiles Integration

**State**

- [ ] What Is Built
- [ ] Remaining

**Outside `docs/`**

- [x] README
- [ ] AGENTS

## Operating Model

**Document Types could say what an introduction is not.** The rule now asks for an introduction rather than a summary, which is the right word, but nothing stops the next writer from writing a summary and calling it one.

## What is OpinionatedArch

**Oparch Tools does not carry the role this document gives the tools.** Here and in the README they are the way of working that keeps the decisions true as the machine changes, and Where To Continue presents them as the commands that keep a machine in the shape the decisions describe. The decision that owns them opens with "small commands for recurring system operations" and then legislates the naming format and the split between command-line and interactive. Nothing in it says they are what holds a machine to its decisions. Same shape as the Dotfiles entry above: a general document defers a claim to a decision that does not contain it.

## Glossary

**Three terms had no other home, and the definitions died with the file.** They are written out here so they can be put where they belong.

**Port** — no document defines it; Host Bridge uses it in five places as if it were understood, and that is where the word does its work. *The boundary between a tool and something outside it: running a command, touching a file, opening an encrypted store, drawing a terminal. It is declared as an interface so that a test can put a stand-in where the machine would be. Every interface in the project is a port today; the word is kept because an interface does not have to be one.*

**Harness** — End-to-End Testing describes the apparatus, but the argument for the word lived only in the glossary. *It is not the thing under test and it is not the assertions; it is what makes running them possible at all. The word is the one used for a wiring harness — the thing that connects and drives — and not for anything to do with the tools this project is written with.*

## Work Contexts and Accounts

**"Baseline policy" is still in a tool document.** [oparch-work-context-create](docs/tools/oparch-work-context-create/000-command.md) opens with "creates a new work context with the required baseline policy: the account that carries it, its groups, its home subvolume, and the initial ownership of that home". No document defines the term, and in the two places it was used it named opposite populations — there, what a work context is given; here, the accounts that are not work contexts. It can go with nothing in its place, because what follows the colon is already the whole list.

## Disk Layout

**The installer still builds the old layout.** The recovery system moved out of the encrypted container and onto an ext4 partition of its own, so the disk now has three partitions and the Btrfs filesystem no longer has a `@recovery` subvolume. Nothing of that is in the code: the disk phase still makes two partitions and creates `@recovery` among the subvolumes, its expected commands say so, and the end-to-end harness checks what it produces. This pass moved the decision and nothing else, deliberately.

**Nothing says what happens when a preserved home and a named context collide.** In `keep-homes` the operator ticks which homes to keep and, on the Work contexts screen, names the contexts to create; the second is described as creating them "in addition to" the ones whose homes are preserved. If the same name arrives by both paths, no document says whether that is a validation error or simply that context coming back with the home it had. The mode is not implemented, so deciding it now costs nothing.

## Swap

**The installer sets no swap priority.** Swap decides that the compressed swap in RAM is used before the swapfile on disk, and nothing in the code makes that true. The mount table entry the swap phase appends is `/swap/swapfile none swap defaults 0 0`, with no `pri=`, and the zram configuration it writes carries a size and a compression algorithm and no priority either. Which of the two the kernel reaches for first is left to whatever the defaults turn out to be.

## Snapshots

**Two snapshot tools describe a job that has grown.** [oparch-snapshot-system-create](docs/tools/oparch-snapshot-system-create/000-command.md) describes creating the snapshot and nothing else, where creating one now also means hashing the boot artifacts, storing the set when it is new, and recording the pair. [oparch-snapshot-restore](docs/tools/oparch-snapshot-restore/000-command.md) says a system restore must run offline from live media plus chroot, which predates the recovery partition, and that a home restore can run on the installed system "with controlled session state", where Snapshots now requires that context to be logged out; neither the table nor putting the artifacts back is mentioned at all.

## Pre-Boot Ownership Message

**The margin moved from the boot to the composition, and the theme format still puts it at boot.** The decision now says the rendered image reaches the edges of the screen and its content does not, with the renderer leaving that margin when it composes the image. [Return Message Theme Format](docs/tools/oparch-return-message-render/003-theme-format.md) still carries `screen.fit`, "fraction of the limiting screen dimension the composition is scaled to", which is that same margin made by the splash instead. It goes, the separation it produced belongs in `canvas` beside the other spacings, and its validation, the `Why` explaining why `fit` is below one, and what the renderer writes into the splash script all follow.

**[Return Message Themes](docs/tools/oparch-return-message-render/004-themes.md) cites a decision by its old number.** Three times it says `` `007` `` — for the fixed limit of four it replaced, for what is refused of template packages, and for the validation rule it inherits. That document is [Pre-Boot Ownership Message](docs/decisions/009-preboot-ownership-message.md), and [Document Types](docs/README.md) asks for a link with its title.

