# Encryption

## Context

Machines running this system hold sensitive data at rest. Two things have to work without that data being reachable: the UEFI boot flow, which reads its artifacts before anything is decrypted, and whatever repairs the keys of the container when they are damaged or when the passphrase that opens them is gone — which cannot live inside what it repairs.

## Decision

Encryption is mandatory and is not configurable. There is no OpinionatedArch machine without it.

The container that holds the Btrfs filesystem is always encrypted with `LUKS2`.

The passphrase of that container is the password every work context has, as [Work Contexts and Accounts](000-work-contexts-and-accounts.md) decides.

Two partitions stay outside the encryption, as [Disk Layout](001-disk-layout.md) lays them out: the EFI system partition, and the recovery partition. Everything else the machine holds is inside the container.

Two files may be exported while the machine is being installed, each onto a medium the operator mounts for it, and neither is kept on the machine afterwards:

- An unlock file, which is a second key of the container. The recovery system starts without the passphrase, so from there this file opens the volume and a new passphrase can be set when the old one is gone.
- A copy of the container's master keys, so that the area holding them can be restored when it is damaged and the data behind it is not lost with it.

## Why

- Mandatory encryption with no way to turn it off is required because this project assumes sensitive data at rest on every machine; left as a choice, a machine ends up without it by a moment's decision taken once, and there is no second chance to make that choice differently.
- `LUKS2` is used because it is the current standard and what `cryptsetup` makes by default.
- The EFI system partition stays unencrypted because the firmware reads it and knows nothing about `LUKS`: whatever asks for the passphrase has to be readable before any passphrase has been given. And the prompt is not all that screen shows — the return message [Pre-Boot Ownership Message](009-preboot-ownership-message.md) puts there is meant for whoever finds the machine and will never have the secret, so it has to live outside the thing the secret opens.
- The two exports go onto a medium the operator brings and never onto the disk they open, because either of them kept beside the container undoes it: the recovery partition is unencrypted, and the container's own filesystem is one of the things they exist to outlive.
- They are offered rather than required because each is a second way into the disk for as long as it exists, and only the operator can judge how well it will be kept; what the machine owes is the chance to make them at the one moment the container is created, which is the only moment it can be done without asking for the passphrase again.
- The recovery partition stays unencrypted because it is where the container's keys are repaired from: restoring the area that holds the master keys when it is damaged, or opening the volume with the unlock file and setting a new passphrase when the old one is gone. Encrypted with the same secret it would fail in exactly the cases it exists for, and encrypted with a second one it would add a secret to keep for a system that holds nothing worth hiding.
- Swap needs no encryption of its own because it holds what memory held and it already lives inside the container: it is protected by where it is. A second layer over it would encrypt what is encrypted and add a mapping of its own that can fail, which is one more thing between the machine and starting.

## Considerations

- What is written to the recovery partition is readable by anyone holding the disk, so it carries no secret of the installed system.
- Swap confidentiality at rest depends on the existing `LUKS2` container, not on a separate swap encryption mapping.
- Do not create a `crypttab` entry for swap encryption.
- How each exported file is used from the recovery system is not decided here: it is a recovery path, and [Recovery](011-recovery.md) owns it.
- The two exports are not equally dangerous to keep. The unlock file is one key among the container's own, and removing that key ends what it opens. The master-key copy is not revoked by changing the passphrase, or by anything short of encrypting the volume again: whoever holds it opens this disk for as long as the disk exists.
