# oparch-password-rotate-interactive

## Description

`oparch-password-rotate-interactive` is the interactive interface for rotating the shared secret used by disk encryption and every work context. It collects the existing shared secret and the replacement shared secret, then rotates it through the password library, which `oparch-password-rotate` is built on too.

## Why is needed

Password rotation needs an interactive interface for operators who do not want to pass secrets directly in command arguments. The interactive tool keeps input collection separate from password-rotation behavior, so the operation remains owned by the password library.

## Interactive usage

- Mandatory input: existing shared secret.
- Mandatory input: replacement shared secret.
- Mandatory input: replacement shared secret confirmation.
- Rotate the shared secret through the password library with the collected values.
