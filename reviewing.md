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

## What is OpinionatedArch

**Oparch Tools does not carry the role this document gives the tools.** Here and in the README they are the way of working that keeps the decisions true as the machine changes, and Where To Continue presents them as the commands that keep a machine in the shape the decisions describe. The decision that owns them opens with "small commands for recurring system operations" and then legislates the naming format and the split between command-line and interactive. Nothing in it says they are what holds a machine to its decisions. Same shape as the Dotfiles entry above: a general document defers a claim to a decision that does not contain it.

## Disk Layout

**The installer still builds the old layout.** The recovery system moved out of the encrypted container and onto an ext4 partition of its own, so the disk now has three partitions and the Btrfs filesystem no longer has a `@recovery` subvolume. Nothing of that is in the code: the disk phase still makes two partitions and creates `@recovery` among the subvolumes, its expected commands say so, and the end-to-end harness checks what it produces. This pass moved the decision and nothing else, deliberately.

## Swap

**The installer sets no swap priority.** Swap decides that the compressed swap in RAM is used before the swapfile on disk, and nothing in the code makes that true. The mount table entry the swap phase appends is `/swap/swapfile none swap defaults 0 0`, with no `pri=`, and the zram configuration it writes carries a size and a compression algorithm and no priority either. Which of the two the kernel reaches for first is left to whatever the defaults turn out to be.


