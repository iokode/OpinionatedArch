# 006: Swap Strategy

## Context and Decision

The machines using this installer can have different memory and storage capacities, and they can require different swap behavior depending on current workload. Because of that variability, swap sizing is chosen directly at install time.

The installer must ask two values in GB during setup:

- zram swap size in GB
- disk swapfile size in GB, for one install-time swapfile inside `/swap`

Both values are chosen interactively at install time.

## Why

- Using swapfiles inside `/swap` is required because the disk layout has no swap partition
- Limiting the installer to one disk swapfile is required because install-time swap setup should stay simple; if more swapfiles are needed later, they can be created manually inside `/swap`.
- Choosing swap values interactively at install time is required because that is when real hardware constraints are known; if hardcoded beforehand, later correction requires avoidable reconfiguration.

## Implementation Plan

1. Add interactive prompts for `zram_swap_gb` and `disk_swapfile_gb`.
2. Validate both swap values as non-negative integers.
3. Apply zram configuration from `zram_swap_gb`.
4. Create and enable one swapfile inside `/swap` when `disk_swapfile_gb` is greater than `0`.
5. Persist the chosen values in installer state for reproducibility.

## Considerations

- Swap values must be selected from memory, storage, and workload expectations.
- If `disk_swapfile_gb` is `0`, disk swap is disabled at install time.
- Additional swapfiles may be created manually later inside `/swap`.
- If `zram_swap_gb` is `0`, zram swap is disabled.
