# oparch-work-context-list

## Description

`oparch-work-context-list` lists the work contexts of the machine, one name per line: the accounts that are members of `work-contexts`.

It runs as any user.

## Why is needed

The machine has accounts that are not work contexts, so which contexts there are is not what listing its accounts answers. A script, or an interface, that needs to know which contexts exist gets them from one tool rather than from a reading of the group repeated wherever it is needed.

## Requirements

What has to be installed where this runs, which is the machine whose work contexts are listed.

- **`glibc`**, for `getent`: the work contexts are read from the `work-contexts` group, which every account may read, so the tool needs no privileges.

It is on any Arch system, so there is nothing to add before a run.

There is no BAML runtime library in this list: this tool has no host, so `baml pack` makes it a standalone binary — the distinction is [Host Bridge](../../../development/001-host-bridge.md).
