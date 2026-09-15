# oparch-password-rotate

## Description

`oparch-password-rotate` rotates the shared secret used by disk encryption and every work context. It changes the LUKS passphrase on the encrypted root device and updates every member of `work-contexts` to the same new password.

The encrypted root device is the partition the installation names `OpinionatedArch`, the label [Disk Layout](../../../decisions/001-disk-layout.md) gives the container, and it is found at `/dev/disk/by-partlabel/OpinionatedArch`. Its passphrase is changed with `cryptsetup luksChangeKey`, which checks the existing shared secret against the container. The members of `work-contexts` are read from the group, and each is given the new password with `chpasswd`. The rotation stops at the first of those commands that fails, and says which one failed and what it wrote.

It runs as root. Run by any other user, it refuses with an error before doing anything else.

## Why is needed

The system model uses one shared secret for both disk unlock and every work context. Rotating it by hand in several places can desynchronize boot unlock from account login, so a dedicated tool keeps the secret synchronized in one operation.

## Requirements

What has to be installed where this runs, which is the installed system whose secret is rotated.

- **`cryptsetup`**, for `luksChangeKey`.
- **`shadow`**, for `chpasswd`.
- **`glibc`**, for `getent`: the accounts given the new password are the members of `work-contexts`.
- **`coreutils`**, for `id`, which says whether the tool runs as root.
- **`systemd`**, whose udev rules name the partitions under `/dev/disk/by-partlabel/`, where the container is found.

Every one of these is on an installed system: the installation puts `cryptsetup` there, and `base` brings the rest.

There is no BAML runtime library in this list: this tool has no host, so `baml pack` makes it a standalone binary — the distinction is [Host Bridge](../../../development/001-host-bridge.md).

## Input parameters

- `--old-password <password>`: Mandatory. Existing shared secret.
- `--new-password <password>`: Mandatory. Replacement shared secret.

Neither secret is handed to another program on its command line. `cryptsetup` reads both on its standard input, the existing one on the first line and the replacement on the second: given no key file and an input that is not a terminal, it reads each passphrase of a LUKS container up to the end of a line, as `cryptsetup(8)` describes. `chpasswd` reads the replacement the same way, one line per account. A secret is therefore read up to its first line break, and one that holds a line break does not arrive whole.

The exit status is `0` when the secret was rotated, `2` when the command line is not the one described here, and `1` when the run was refused or a step of the rotation failed.
