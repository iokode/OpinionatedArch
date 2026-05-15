# 009: Encryption Strategy

## Context and Decision

Encryption is mandatory for this installer. There is no installer option to disable it.

The BTRFS system partition is always encrypted with `LUKS2`.

Authentication is unified for the main system unlock path: the installer asks one secret and uses it both as the LUKS passphrase for the root container and as the password value for all login users.

The EFI partition remains unencrypted.

## Why

- Mandatory encryption with no disable toggle is required because this project assumes sensitive data at rest on every machine; if encryption can be skipped interactively, an insecure install can be produced by operator error.
- `LUKS2` is used because it is the current standard Linux full-disk encryption format with strong tooling support; if a weaker/legacy format is used without need, long-term maintainability and security posture degrade.
- One shared secret for root LUKS unlock and login users is used because the operator explicitly prioritizes one strong memorized secret over multiple secrets likely to be externalized; if split into many secrets in this model, practical secret-handling risk increases.
- EFI stays unencrypted because the UEFI boot flow must read boot artifacts before root decryption; if EFI encryption is forced in this design, boot reliability and implementation complexity increase sharply.
- Swapfiles are protected by the existing Btrfs-on-LUKS2 encryption boundary because persistent swap is stored inside the encrypted filesystem; if a second swap-specific encryption layer is added, the design gains redundant encryption and extra failure surface without improving the selected at-rest boundary.
- Hibernation is disabled because no resume flow is defined for this swapfile model in this phase; if hibernation is enabled without a defined resume design, resume behavior is undefined.

## Implementation Plan

1. Prompt once for the shared secret during installation.
2. Create a `LUKS2` container on the root partition and open it as `cryptroot`.
3. Create Btrfs inside `cryptroot` and continue normal subvolume setup.
4. Set login-user passwords to the same shared secret value.
5. Create swapfiles inside the encrypted Btrfs filesystem according to `006-swap-strategy.md`.
6. Configure initramfs and bootloader so root unlock always occurs at boot.
7. Ensure hibernation/resume is not configured.

## Considerations

- Swap confidentiality at rest depends on the existing `LUKS2` container, not on a separate swap encryption mapping.
- Do not create a `crypttab` entry for swap encryption.
- LUKS header backup and recovery workflow should be documented later as an operational safeguard.
