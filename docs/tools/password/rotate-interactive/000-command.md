# oparch-password-rotate-interactive

## Description

`oparch-password-rotate-interactive` is the interactive interface for rotating the shared secret used by disk encryption and every work context. It collects the existing shared secret and the replacement shared secret, then rotates it through the password library, which `oparch-password-rotate` is built on too.

It runs as root. Run by any other user, it refuses with an error before it takes the terminal over.

What a rotation that stops half way leaves behind, and how it is finished, is described in [oparch-password-rotate](../rotate/000-command.md). Here, finishing it is running this tool again and giving the new secret as both the existing secret and the new one.

## Why is needed

Password rotation needs an interactive interface for operators who do not want to pass secrets directly in command arguments. The interactive tool keeps input collection separate from password-rotation behavior, so the operation remains owned by the password library.

## Requirements

Everything [oparch-password-rotate](../rotate/000-command.md) requires, because it rotates through the same library.

On top of that, **the BAML runtime library.** This tool has a host, so its binary loads a shared library of about 25 MB rather than carrying it. Where it comes from is [Host Bridge](../../../development/001-host-bridge.md). It comes in a package of its own, `oparch-baml-runtime`, which this tool's package depends on. What goes on `PATH` is a wrapper that names the library with `BAML_LIBRARY_PATH`, along with `BAML_LIBRARY_DISABLE_DOWNLOAD`, which turns a missing library into a failure instead of a silent download.

## Interactive usage

- Mandatory input: existing shared secret.
- Mandatory input: replacement shared secret.
- Mandatory input: replacement shared secret confirmation.
- Rotate the shared secret through the password library with the collected values.

The tool takes over the terminal and asks three screens in order, each a field that shows a bullet for every character typed and never the character: the existing shared secret, the replacement, and the replacement again. The left pane lists them, with the rotation after them, and marks which screen is showing.

An answer that is not taken is reported on the screen it was given on, and that screen is asked again. That covers a replacement the password library refuses and a confirmation that is not the replacement. The only replacement the library refuses that can be typed here is an empty one: `Enter` accepts a field, so a line break cannot be typed into it.

Once the confirmation is taken, the rotation runs, and the last screen says how it ended: either that the shared secret was rotated, or what failed and what the failing command wrote. The screen stays until the operator leaves it, and the same is printed on the terminal once it has been handed back.

| Key | Action |
| --- | --- |
| Typing | Enter a secret |
| `Enter` | Accept the field; on the last screen, leave |
| `Esc`, `F1` | Go back one screen; the first screen has nothing behind it and stays |
| `F6` | Leave without rotating, after a confirmation; on the last screen, leave |
| `F8` | Read the runtime log |

The exit status is `0` when the shared secret was rotated, and `1` when the run was refused, when the operator left without rotating, or when the rotation failed.
