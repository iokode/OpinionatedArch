# What is OpinionatedArch

OpinionatedArch is an Arch-based system for one physical person who wants multiple work contexts without maintaining a separate system configuration for each.

## The Problems It Solves

Arch decides almost nothing for you, and it offers no method for what comes after. That is the point of it, and it is also the work: the network stack, the audio daemon, the kernel, swap and the locale are choices you make and wire yourself, and the machine is then yours to keep in that shape by hand. You can automate the first part — with `archinstall`, or a script of your own — and the automation becomes one more thing you own and maintain. Most of what follows is that same absence, seen from a different side.

It multiplies where one person keeps several accounts. Separating personal use from client work is what accounts are for, and each one gives its own session, browser profile, cookies and running processes, which is exactly what is wanted. What is not wanted is configuring every one of them and repeating every change across all of them — and sharing that configuration by hand, with symlinks or a script, is one more arrangement to keep working.

Nothing holds the shape over time. Adding an account, rotating the disk passphrase, taking a snapshot before something risky: each is a multi-step procedure done by hand, and it is easy for two of them to come out different. A machine drifts into parts that no longer agree with each other, and nothing written down says what it was supposed to be.

Rollback and recovery are things you have to remember to arrange. Btrfs snapshots and a recovery medium are within reach of any Arch install, and they are opt-in: you choose the scope, size the retention, wire them to the layout, and find out whether you got it right on the day it matters.

One problem here is not of that kind. A lost machine cannot say whose it is on its own, however methodically it was built. Engraving the chassis or sticking a label on it works and needs no computer at all, which is why most people do it; it also comes off, and not everyone wants it on the lid of a laptop.

## What It Decides

OpinionatedArch decides the system and not the interface. Everything from the disk up to a booted, recoverable machine with its configuration in place has one answer, taken once and written down as a decision.

Everything above that — the desktop, the window manager, the shell, the editor — is the operator's. The shared configuration is what carries their answer to every context.

## Where To Continue

- [Operating Model](001-operating-model.md) describes how the system works.
- [Decisions](../decisions/) are the answers this document says are taken once, one per document with its reasoning.
- [Tools](../tools/) are the commands that keep a machine in the shape those decisions describe.
- [Installation Overview](002-installation-overview.md) describes how a machine is installed.

