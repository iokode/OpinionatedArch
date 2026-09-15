# Oparch Tools

## Context

OpinionatedArch decides how a machine is laid out and how it is operated, and a machine changes. Those decisions hold only if something carries them out afterwards. The tools do that.

## Decision

An operation that a decision of this project governs is done with a tool of this project. Adding a work context, taking a snapshot or restoring one, rotating the password: each is a command that leaves the machine as the decisions describe it, so that keeping it that way is not a procedure the operator has to remember.

This document defines the common policy for those tools; it does not enumerate the tool inventory.

Tool-specific documents live in `docs/tools/`. Each tool has its own directory there, named after the command, holding a command document and one further document per format, syntax or protocol the tool defines.

Tool names use the `oparch-{entity}-{action}` format. The `entity` identifies the domain managed by the tool. A domain is the system object or area of operation that the decisions of this project govern and that tools act on: work contexts, snapshots, the password. The `action` identifies the operation performed on that entity.

`oparch-installer` is an exception to the naming format. It is not an operational tool of the installed system: it runs from the live environment and installs that system in the first place. Its interactive version is `oparch-installer-interactive`.

Interactive tools are an exception to the naming format too. An interactive tool is named after what it covers, followed by `-interactive`: the entity alone when it covers several operations of that entity, as `oparch-snapshot-interactive` does, and the entity and the action when it covers one, as `oparch-password-rotate-interactive` does.

Every operation is a command-line tool. A command-line tool takes what it acts on from its arguments and asks for nothing, so that any operation can be run from a script. The exception is an interactive tool over a system tool, whose domain logic belongs to that system tool rather than to this project: it has no command-line tool and no library, because the system tool is both, as NetworkManager is for the network.

The domain logic of an entity is the code that acts on its domain as the decisions of this project describe, whichever interface asked for it. It lives in a library of that entity, and it is the library that carries out each operation. The command-line tools of an entity, and its interactive tool when it has one, are interfaces built on that library; not every entity has an interactive tool. Interactive tools are interfaces only: they browse choices, filter lists, ask for confirmation, collect input, and then call the library with explicit parameters. An interactive tool may act on the system to be usable, and never to carry out domain logic. An interactive tool can cover several operations of its entity.

What runs a tool on an event — a systemd unit started with the machine, a pacman hook, a program that waits for a login — is a trigger of that tool. A trigger is shipped in a package of its own, and never in the package of the tool it runs, which ships the tool alone.

Tools are versioned semantically, in three segments always, and the version a tool carries is the version its package declares. `pkgver` admits no hyphen, so a pre-release is written glued to the version with no separator at all: `0.1.0dev1`, and never `0.1.0_dev1` or `0.1.0.dev1`. `dev` marks a tool under active development. The tools start at `0.1.0dev1`.

The assets these tools read on a system are kept at `/usr/share/opinionatedarch/assets`. Whatever installs an asset puts it there, and whatever reads one is pointed there.

The language these tools are written in is decided in [BAML as Implementation Language](../development/000-baml-as-implementation-language.md).

## Why

- The operations a decision governs are given tools because a decision that is only written down is kept by hand, and by hand it is kept until the day it is not: a home subvolume forgotten for a new context, a snapshot never taken, an account left in the wrong group. What the tool does is what the decision says, and running it is the whole of the procedure.
- The `oparch-{entity}-{action}` naming format is required so commands remain discoverable and script-friendly; if naming varies by tool, operators must memorize exceptions.
- Every operation is a command-line tool that takes what it acts on from its arguments so that every operation remains scriptable and testable; an operation reachable only through an interactive tool is one no script can perform.
- An interactive tool over a system tool has no command-line tool of this project because the system tool already is one: a second would wrap it and decide nothing, and a script calls the system tool directly.
- The domain logic of an entity lives in one library so that an operation is carried out by the same code whichever interface started it; if interactive tools held domain logic themselves, it would be duplicated and harder to verify. An interactive tool calls the library rather than the command-line tool because what it shows — how far an operation has gone and why it failed — reaches it from the library as values, where from a command-line tool it would arrive as text to be read back.
- A trigger is a package of its own because when a tool runs is not part of what the tool does: the tool is the same whether the operator, a boot or a login starts it. Shipped inside the tool's package, a trigger comes with every installation of the tool, and a machine that reaches the same moment another way can neither leave it out nor be given a different one without that package being changed. Apart, each trigger is installed, replaced or removed on its own, and the tool's package changes only when the tool does.
- Interactive tools are named with `-interactive` so that the name says whether a command is an interface, with one suffix for all of them; an interactive tool that covers several operations has no single action to put in the format.
- Versions are semantic because some of the formats these tools read declare a version of their own, and a tool decides what to do with a file by comparing what it declares against the tool's own version. A version that carries no meaning on one side of that comparison makes the comparison meaningless, and the file format is not free to be read some other way.
- A pre-release is glued to the version because that is the only form pacman orders as one. `0.1.0dev1` precedes `0.1.0`, while `0.1.0_dev1` and `0.1.0.dev1` both follow it: the same intent written with a separator inverts the order, and what the operator is then offered as an upgrade is the earlier build.
- The assets have one named location because more than one tool reads them and more than one thing installs them there. A path asserted only by whichever tool happened to be written first is a path everything else copies from one another, and when two of those copies disagree there is nothing that says which of them is wrong.
- The implementation language is not decided here because it applies to every built-in tool, not only to the operational ones.

## Considerations

- Do not duplicate the concrete tool inventory in this document.
- Do not put domain logic in the code of an interactive tool: the filesystem changes, account changes, snapshot changes and other system mutations that make up an operation belong to the library of its entity. What an interactive tool does to the system so that it can be used, such as applying a keymap or connecting to a network, is part of the interface and stays in it.
- Keep exceptions explicit in the affected tool document.
- A version that has to move backwards can only be corrected with a pacman `epoch`, and a package that is given one keeps it for good.
- A tool whose own default asset directory is somewhere else has to be given this one. `oparch-installer-interactive` is such a tool: its default is a directory beside the binary, and what runs it names this path instead.

