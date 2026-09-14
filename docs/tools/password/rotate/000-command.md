# oparch-password-rotate

## Description

`oparch-password-rotate` rotates the shared secret used by disk encryption and every work context. It changes the LUKS passphrase on the encrypted root device and updates every member of `work-contexts` to the same new password.

## Why is needed

The system model uses one shared secret for both disk unlock and every work context. Rotating it by hand in several places can desynchronize boot unlock from account login, so a dedicated tool keeps the secret synchronized in one operation.

## Input parameters

- `--old-password <password>`: Mandatory. Existing shared secret.
- `--new-password <password>`: Mandatory. Replacement shared secret.
