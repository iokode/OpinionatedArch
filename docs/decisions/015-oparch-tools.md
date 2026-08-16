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

The language these tools are written in is decided in [BAML as Implementation Language](../development/000-baml-as-implementation-language.md).

## Why

- The operations a decision governs are given tools because a decision that is only written down is kept by hand, and by hand it is kept until the day it is not: a home subvolume forgotten for a new context, a snapshot never taken, an account left in the wrong group. What the tool does is what the decision says, and running it is the whole of the procedure.
- The `oparch-{entity}-{action}` naming format is required so commands remain discoverable and script-friendly; if naming varies by tool, operators must memorize exceptions.
- Separating command-line behavior from interactive selection is required so every operation remains scriptable and testable; if interactive tools perform actions directly, behavior becomes duplicated and harder to verify.
- The implementation language is not decided here because it applies to every built-in tool, not only to the operational ones.

## Considerations

- Do not duplicate the concrete tool inventory in this document.
- Do not put filesystem changes, account changes, snapshot operations, or other system mutations in interactive tools.
- Keep exceptions explicit in the affected tool document.

