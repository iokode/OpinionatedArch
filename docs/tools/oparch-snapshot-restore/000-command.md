# oparch-snapshot-restore

## Description

`oparch-snapshot-restore` restores a concrete snapshot for either system scope or user-home scope using the single `@snapshots` layout.

User-scope restore can run on the installed system with controlled session state. System-scope restore must run offline from an external environment, such as live media plus chroot.

## Why is needed

Recovery must be deterministic during incidents, and restore safety differs by scope. A single restore tool with explicit online and offline rules reduces operator mistakes and avoids fragile system-root rollback while the system is running.

## Input parameters

- `<scope>`: Mandatory. Restore scope. Accepted values: `system`, `home`.
- `<name>`: Mandatory for `home` scope. Work context whose home scope is restored.
- `<snapshot>`: Mandatory. Concrete snapshot path or identifier to restore.
