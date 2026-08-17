# oparch-work-context-create

## Description

`oparch-work-context-create` creates a new work context: the account that carries it, its groups, its home subvolume, and the initial ownership of that home.

## Why is needed

Creating the account by hand is error-prone and can break assumptions used by snapshot and permission policies. A work context is not one `useradd`: it is an account, a membership in two groups, a dedicated subvolume and a mount that has to survive a reboot. One tool owns the whole of it, so a context added later matches the ones the installation made.

## Input parameters

- `<name>`: Mandatory. Name of the work context to create. It is also the name of the account that carries it, so it has to be a valid username.
