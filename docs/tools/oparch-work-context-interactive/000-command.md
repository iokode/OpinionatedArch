# oparch-work-context-interactive

## Description

`oparch-work-context-interactive` is the interactive interface for the work contexts of the machine. It lists them, creates one and removes one, carrying each operation out through the work context library, which `oparch-work-context-list`, `oparch-work-context-create` and `oparch-work-context-remove` are built on too.

## Why is needed

Creating and removing a work context take answers that are easier to give looking at the contexts already there: which name is free, which context is being removed, and whose home receives its data. The interactive tool shows the contexts and collects those answers, and the operations remain owned by the work context library.

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
