# oparch-snapshot-restore

## Description

`oparch-snapshot-restore` restores a concrete snapshot for either system scope or user-home scope using the single `@snapshots` layout.

Every restore runs from the recovery system, as [Snapshots](../../decisions/004-snapshots.md) decides: neither `@` nor the home of a work context is restored while the installed system is running.

Restoring a system snapshot also puts back the set of boot artifacts recorded with it.

## Why is needed

Recovery must be deterministic during incidents. One tool for both scopes, running where nothing holds what it is replacing, reduces operator mistakes and avoids rolling a root back underneath the processes using it.

## Input parameters

- `<scope>`: Mandatory. Restore scope. Accepted values: `system`, `home`.
- `<name>`: Mandatory for `home` scope. Work context whose home scope is restored.
- `<snapshot>`: Mandatory. Concrete snapshot path or identifier to restore.
