# 014: Btrfs Mount Options Policy

## Context and Decision

For this project phase, Btrfs mount options are not customized.

The installer uses Btrfs default mount behavior and does not set explicit tuning options such as `compress`, `noatime`, `ssd`, or per-subvolume mount overrides.

This applies to all configured subvolumes in this phase.

## Why

- Using defaults is required because current Btrfs defaults are already adequate for this setup and no concrete issue requires overrides; if custom options are introduced without a real problem to solve, policy becomes arbitrary and adds maintenance/debug surface without proven benefit.
- Avoiding per-subvolume mount-option divergence is required because this phase does not yet have measured workload evidence for targeted tuning; if divergent policies are added early, maintenance burden increases without proven benefit.
- Btrfs tuning is postponed because no concrete issue exists yet; if tuning is added now, troubleshooting later becomes harder because there is no problem-driven reason for those values.

## Implementation Plan

1. Create and mount Btrfs subvolumes without custom mount options.
2. Generate fstab entries without explicit Btrfs tuning flags.
3. Keep installer logic free of per-subvolume mount-option branching.
4. Revisit this decision in a later phase after real usage data is available.

## Considerations

- This decision is intentional, not an omission.
- Future tuning remains possible without changing current subvolume layout decisions.
- If a concrete performance or reliability issue appears, open a dedicated decision update before adding mount options.
