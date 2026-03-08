# 010: Encryption Strategy

## Context and Decision

Encryption is mandatory for this installer. There is no installer option to disable it.

The root/system partition is always encrypted with `LUKS2`.

Authentication is unified for the main system unlock path: the installer asks one secret and uses it both as the LUKS passphrase for the root container and as the password value for all login users.

The EFI partition remains unencrypted.

Swap is always encrypted. Swap encryption uses an ephemeral random key generated at boot, and hibernation is not supported.

## Why

- Mandatory encryption with no disable toggle is required because this project assumes sensitive data at rest on every machine; if encryption can be skipped interactively, an insecure install can be produced by operator error.
- `LUKS2` is used because it is the current standard Linux full-disk encryption format with strong tooling support; if a weaker/legacy format is used without need, long-term maintainability and security posture degrade.
- One shared secret for root LUKS unlock and login users is used because the operator explicitly prioritizes one strong memorized secret over multiple secrets likely to be externalized; if split into many secrets in this model, practical secret-handling risk increases.
- EFI stays unencrypted because the UEFI boot flow must read boot artifacts before root decryption; if EFI encryption is forced in this design, boot reliability and implementation complexity increase sharply.
- Swap is encrypted with an ephemeral boot-time key because swap can contain sensitive memory remnants and must not be recoverable after shutdown; if swap is plaintext or uses a persistent key, offline extraction risk increases.
- Hibernation is disabled because hibernation requires persistent swap-resume state and conflicts with ephemeral swap-key strategy; if hibernation is enabled under this model, resume behavior is broken or requires a different security design.

## Implementation Plan

1. Prompt once for the shared secret during installation.
2. Create a `LUKS2` container on the root partition and open it as `cryptroot`.
3. Create Btrfs inside `cryptroot` and continue normal subvolume setup.
4. Set login-user passwords to the same shared secret value.
5. Configure encrypted swap with a random boot-time key via `crypttab`, then initialize swap on the mapped device.
6. Configure initramfs and bootloader so root unlock always occurs at boot.
7. Ensure hibernation/resume is not configured.

## Considerations

- Encrypted swap with ephemeral key protects confidentiality at rest but is incompatible with hibernation by design.
- Copying raw swap blocks is still possible, but copied data remains unreadable without the ephemeral key.
- LUKS header backup and recovery workflow should be documented later as an operational safeguard.
