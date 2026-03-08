# 004: Btrfs Subvolume Layout

## Context and Decision

The installation filesystem is `btrfs`. The chosen layout uses these subvolumes:

- `@`
- `@home-<login-user>` (one subvolume per login user)
- `@log`
- `@pkg`
- `@snapshots`

The dotfiles repository is not a dedicated subvolume; it stays in `/dotfiles` inside `@`.
Login-user homes are handled as dedicated per-user subvolumes under `/home`, not as plain directories.

## Why

Each subvolume exists for a specific recovery and isolation reason:

- `@`: keeps operating-system state together, including `/dotfiles`, so restoring system state also restores the matching system-managed configuration state; if separated, package/system rollback can land on a config revision that no longer matches.
- `@home-<login-user>`: isolates each login user data and allows per-user rollback without touching other users; if omitted, one rollback operation can revert unrelated user data.
- `@log`: keeps logs out of root-state rollback scope because logs are high-churn operational data; if logs stay in `@`, snapshot diffs and retention are dominated by log noise instead of meaningful system-state changes.
- `@pkg`: keeps package cache out of root-state rollback scope because cache lifecycle (download/cleanup) is not configuration state; if cache is inside `@`, snapshots capture irrelevant cache churn and waste snapshot space/history.
- `@snapshots`: provides a dedicated snapshot location so retention and cleanup can target snapshots without mixing with live runtime trees; if omitted, snapshot management is harder to reason about and easier to misoperate.
- Dotfiles stay inside `@` (no dedicated `@dotfiles`) because this project prefers rollback alignment between system state and managed configuration; if dotfiles are isolated in a separate rollback domain, restoring system state can desynchronize it from the configuration revision in use.

## Implementation Plan

1. Partition target disk and format the Linux partition as `btrfs`.
2. Create the selected subvolumes.
3. Mount subvolumes to their target mount points.
4. Persist mount configuration in fstab.
5. Provision each login user with a dedicated home subvolume at user-creation time.

## Considerations

- Do not add extra subvolumes unless there is a clear operational need.
- Snapshot policy must remain compatible with the selected mount layout.
- User provisioning must include home-subvolume creation for both install-time and post-install users.
