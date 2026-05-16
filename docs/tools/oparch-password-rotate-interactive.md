# oparch-password-rotate-interactive

## Description

`oparch-password-rotate-interactive` is the interactive interface for rotating the shared secret used by disk encryption and login users. It collects the existing shared secret and replacement shared secret, then calls `oparch-password-rotate --old-password <password> --new-password <password>`.

## Why is needed

Password rotation needs an interactive interface for operators who do not want to pass secrets directly in command arguments. The interactive tool keeps input collection separate from password-rotation behavior, so the operation remains owned by `oparch-password-rotate`.

## Interactive usage

- Mandatory input: existing shared secret.
- Mandatory input: replacement shared secret.
- Mandatory input: replacement shared secret confirmation.
- Call `oparch-password-rotate --old-password <password> --new-password <password>` with the collected values.
