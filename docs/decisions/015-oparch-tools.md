# Oparch Tools

## Context

OpinionatedArch decides how a machine is laid out and how it is operated, and a machine changes. Those decisions hold only if something carries them out afterwards. The tools do that.

## Decision

An operation that a decision of this project governs is done with a tool of this project. Adding a work context, taking a snapshot or restoring one, rotating the password: each is a command that leaves the machine as the decisions describe it, so that keeping it that way is not a procedure the operator has to remember.

This document defines the common policy for those tools; it does not enumerate the tool inventory.

Tool-specific documents live in `docs/tools/`. Each tool has its own directory there, named after the command, holding a command document and one further document per format, syntax or protocol the tool defines.

Tool names use the `oparch-{entity}-{action}` format. The `entity` identifies the system object or operational domain managed by the tool. The `action` identifies the operation performed on that entity.

`oparch-installer` is an exception to the naming format. It is not an operational tool of the installed system: it runs from the live environment and installs that system in the first place.

Command-line tools own behavior and perform the actual operation. Interactive tools are interfaces only: they browse choices, filter lists, ask for confirmation, collect input, and then call the matching command-line tool with explicit parameters.

Tools are versioned semantically, in three segments always, and the version a tool carries is the version its package declares. `pkgver` admits no hyphen, so a pre-release is written glued to the version with no separator at all: `0.1.0dev1`, and never `0.1.0_dev1` or `0.1.0.dev1`. `dev` marks a tool under active development. The tools start at `0.1.0dev1`.

The assets these tools read on a system are kept at `/usr/share/opinionatedarch/assets`. Whatever installs an asset puts it there, and whatever reads one is pointed there.

The language these tools are written in is decided in [BAML as Implementation Language](../development/000-baml-as-implementation-language.md).

## Why

- The operations a decision governs are given tools because a decision that is only written down is kept by hand, and by hand it is kept until the day it is not: a home subvolume forgotten for a new context, a snapshot never taken, an account left in the wrong group. What the tool does is what the decision says, and running it is the whole of the procedure.
- The `oparch-{entity}-{action}` naming format is required so commands remain discoverable and script-friendly; if naming varies by tool, operators must memorize exceptions.
- Separating command-line behavior from interactive selection is required so every operation remains scriptable and testable; if interactive tools perform actions directly, behavior becomes duplicated and harder to verify.
- Versions are semantic because some of the formats these tools read declare a version of their own, and a tool decides what to do with a file by comparing what it declares against the tool's own version. A version that carries no meaning on one side of that comparison makes the comparison meaningless, and the file format is not free to be read some other way.
- A pre-release is glued to the version because that is the only form pacman orders as one. `0.1.0dev1` precedes `0.1.0`, while `0.1.0_dev1` and `0.1.0.dev1` both follow it: the same intent written with a separator inverts the order, and what the operator is then offered as an upgrade is the earlier build.
- The assets have one named location because more than one tool reads them and more than one thing installs them there. A path asserted only by whichever tool happened to be written first is a path everything else copies from one another, and when two of those copies disagree there is nothing that says which of them is wrong.
- The implementation language is not decided here because it applies to every built-in tool, not only to the operational ones.

## Considerations

- Do not duplicate the concrete tool inventory in this document.
- Do not put filesystem changes, account changes, snapshot operations, or other system mutations in interactive tools.
- Keep exceptions explicit in the affected tool document.
- A version that has to move backwards can only be corrected with a pacman `epoch`, and a package that is given one keeps it for good.
- A tool whose own default asset directory is somewhere else has to be given this one. `oparch-installer` is such a tool: its default is a directory beside the binary, and what runs it names this path instead.

