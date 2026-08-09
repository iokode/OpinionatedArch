# Swap Strategy

## Context

The machines using this installer can have different memory and storage capacities, and they can require different swap behavior depending on current workload.

## Decision

Because of that variability, swap sizing is chosen directly at install time.

The installer must ask two values in GB during setup:

- zram swap size in GB
- disk swapfile size in GB, for one install-time swapfile inside `/swap`

Both values are chosen interactively at install time, are validated as non-negative integers, and are persisted in installer state.

## Why

- Using swapfiles inside `/swap` is required because the disk layout has no swap partition
- Limiting the installer to one disk swapfile is required because install-time swap setup should stay simple; if more swapfiles are needed later, they can be created manually inside `/swap`.
- Choosing swap values interactively at install time is required because that is when real hardware constraints are known; if hardcoded beforehand, later correction requires avoidable reconfiguration.

## Considerations

- Swap values must be selected from memory, storage, and workload expectations.
- If `disk_swapfile_gb` is `0`, disk swap is disabled at install time.
- Additional swapfiles may be created manually later inside `/swap`.
- If `zram_swap_gb` is `0`, zram swap is disabled.
