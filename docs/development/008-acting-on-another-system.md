# Acting on Another System

A tool sometimes has to change a system that is not the one it is running on: an installation being built, a volume being repaired. There are two ways to arrange that, and this is which one the project uses.

**A tool is entered, not aimed at.** Whoever needs it run against another root enters that root and runs the tool inside it, so the tool sees `/` and needs to know nothing. The installer is the exception, and the reason it is one is what makes the rule worth stating.

## What the two arrangements are

**Aiming at it.** The tool takes a target — a root, and whether commands are entered into it — and composes that root with every path it touches. `006-where-a-command-runs.md` describes the shape.

**Entering it.** The caller runs `arch-chroot <root> <tool>`. Inside, the tool's root is the root, and every absolute path it carries means what it says.

## Why entering, for a tool

Because a tool's paths are absolute and there are more of them than there look to be. A synchroniser carries where the dotfiles are, where its state goes, where the secret store is — and then every target the map declares, and every home directory it expands, all absolute. Aiming it at another root means composing all of that, not just the commands it runs.

Half of that composition is worse than none. A tool that prefixes the roots it was written with, but not the paths it reads out of a file, looks like it supports another root and does not — and what it writes to the wrong place is the state that says what it owns.

Entering costs nothing to write. The tool has no target, no prefixing, and no case to get wrong; the caller already has the root mounted and already enters it for other things.

## Why the installer is the exception

It is not a tool being run against a system. It is the thing that makes one.

Two properties follow from that, and neither holds for anything else. It writes into the target before there is anything to enter — the root it is building has no shell, no packages and no tools until it has put them there. And when it does enter, it enters for single commands that need the target's own context, while continuing to write files into it directly from outside. So it needs a root and the entering decided separately, which is exactly what a target is.

## What it costs

A tool that is entered has to be installed in the root being entered. That is the price of the arrangement, and it is worth naming: the caller cannot run a tool that is not there.

The tools this affects ship as what `baml pack` produces, so being installed is what they are anyway.
