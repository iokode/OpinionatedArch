# oparch-work-context-interactive

## Description

`oparch-work-context-interactive` is the interactive interface for the work contexts of the machine. It lists them, creates one and removes one, carrying each operation out through the work context library, which `oparch-work-context-list`, `oparch-work-context-create` and `oparch-work-context-remove` are built on too.

It runs as root. Run by any other user, it refuses with an error before it takes the terminal over.

## Why is needed

Creating and removing a work context take answers that are easier to give looking at the contexts already there: which name is free, which context is being removed, and whose home receives its data. The interactive tool shows the contexts and collects those answers, and the operations remain owned by the work context library.

## Requirements

Everything [oparch-work-context-create](../create/000-command.md) and [oparch-work-context-remove](../remove/000-command.md) require, because it creates and removes through the same library; what [oparch-work-context-list](../list/000-command.md) requires is part of that.

On top of that, **the BAML runtime library.** This tool has a host, so its binary loads a shared library of about 25 MB rather than carrying it. Where it comes from is [Host Bridge](../../../development/001-host-bridge.md). It comes in a package of its own, `oparch-baml-runtime`, which this tool's package depends on. What goes on `PATH` is a wrapper that names the library with `BAML_LIBRARY_PATH`, along with `BAML_LIBRARY_DISABLE_DOWNLOAD`, which turns a missing library into a failure instead of a silent download.

## Interactive usage

- Shows the work contexts of the machine.
- Create a work context:
  - Mandatory input: name of the work context to create.
- Remove a work context:
  - Mandatory input: work context to remove, chosen from the list.
  - Optional input: work context whose home receives the removed context's home data.
  - Optional input: keep the removed context's snapshot data.
  - Mandatory input: confirmation.
- Carry out the chosen operation through the work context library with the collected values.

The tool takes over the terminal. The left pane lists the screens of what is being done, with the operation itself last, and marks which screen is showing; the right pane shows it.

The first screen, **Work contexts**, names the work contexts of the machine and asks what to do: create a work context or remove one.

Creating asks one screen, **Name**: the name of the new work context, which is also the name of its account. A name that is not a valid username, or that is `system`, is reported on that screen, which is asked again.

Removing asks four screens in order:

1. **Work context**: the work context to remove, chosen from the list. The last work context of the machine is reported on this screen, which is asked again.
2. **Home data**: not to keep the removed context's home, or to keep it in the home of one of the other work contexts, each offered by name.
3. **Snapshots**: to remove the snapshots of the removed context's home, or to keep them.
4. **Confirmation**: one entry, removing the context, under a sentence saying what will happen to its home and its snapshots.

Once the name, or the confirmation, is taken, the operation runs, and the last screen says how it ended: that the work context was created or removed, and where its home was copied to when it was kept; or what failed. The screen stays until the operator leaves it, and the same is printed on the terminal once it has been handed back. One run carries out one operation.

| Key | Action |
| --- | --- |
| `↑` `↓` | Move within a list |
| Typing | Filter a list, or enter a name |
| `Enter` | Select, or accept the name; on the last screen, leave |
| `Esc`, `F1` | Go back one screen; the first screen has nothing behind it and stays |
| `F6` | Leave without creating or removing anything, after a confirmation; on the last screen, leave |
| `F8` | Read the runtime log |

The exit status is `0` when the work context was created or removed, and `1` when the run was refused, when the operator left without an operation, or when the operation failed.
