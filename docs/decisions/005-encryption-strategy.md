# Encryption Strategy

## Context

Machines running this system hold sensitive data at rest, and the UEFI boot flow must read boot artifacts before the root filesystem can be decrypted.

## Decision

Encryption is mandatory for this installer. There is no installer option to disable it.

The BTRFS system partition is always encrypted with `LUKS2`.

Authentication is unified for the main system unlock path: the installer asks one secret and uses it both as the LUKS passphrase for the root container and as the password value for all login users.

The EFI partition remains unencrypted.

Hibernation and resume are not configured.

## Why

- Mandatory encryption with no disable toggle is required because this project assumes sensitive data at rest on every machine; if encryption can be skipped interactively, an insecure install can be produced by operator error.
- `LUKS2` is used because it is the current standard Linux full-disk encryption format with strong tooling support; if a weaker/legacy format is used without need, long-term maintainability and security posture degrade.
- One shared secret for root LUKS unlock and login users is used because the operator explicitly prioritizes one strong memorized secret over multiple secrets likely to be externalized; if split into many secrets in this model, practical secret-handling risk increases.
- EFI stays unencrypted because the UEFI boot flow must read boot artifacts before root decryption; if EFI encryption is forced in this design, boot reliability and implementation complexity increase sharply.
- Swapfiles are protected by the existing Btrfs-on-LUKS2 encryption boundary because persistent swap is stored inside the encrypted filesystem; if a second swap-specific encryption layer is added, the design gains redundant encryption and extra failure surface without improving the selected at-rest boundary.

## Considerations

- Swap confidentiality at rest depends on the existing `LUKS2` container, not on a separate swap encryption mapping.
- Do not create a `crypttab` entry for swap encryption.
- LUKS header backup and recovery workflow should be documented later as an operational safeguard.
