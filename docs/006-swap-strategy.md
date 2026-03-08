# 006: Swap Strategy

## Context and Decision

The machines using this installer can have different memory and storage capacities, and the same machine role can still require different swap behavior depending on current workload. Because of that variability, swap sizing is not tied to machine role.

The installer must ask two values in GB during setup:

- zram swap size in GB
- disk swap partition size in GB

Both values are chosen interactively at install time.

## Why

- Swap sizing is independent from machine role because role labels are too coarse to predict RAM pressure and VM workload on a specific machine; if tied to role, identical roles with different hardware/load will receive wrong swap sizing.
- Asking `zram swap size in GB` is required because compressed RAM swap must be tuned to available memory and responsiveness goals; if fixed globally, zram can be too small to help or too large for the target memory budget.
- Asking `disk swap partition size in GB` is required because persistent swap needs vary by disk capacity and workload safety margin; if fixed globally, disk space can be wasted or swap headroom can be insufficient.
- Choosing both values interactively at install time is required because that is when real hardware constraints are known; if hardcoded beforehand, later correction requires avoidable repartitioning/reconfiguration.

## Implementation Plan

1. Add interactive prompts for `zram_swap_gb` and `disk_swap_gb`.
2. Validate both values as non-negative integers.
3. Apply zram configuration from `zram_swap_gb`.
4. Create and enable a swap partition sized from `disk_swap_gb`.
5. Persist the chosen values in installer state for reproducibility.

## Considerations

- Swap values must be independent from machine role selection.
- Very large disk swap values are valid but should trigger a warning about disk usage and potential thrashing.
- If `disk_swap_gb` is `0`, disk swap is disabled.
- If `zram_swap_gb` is `0`, zram swap is disabled.
