# 006: Swap Strategy

## Context and Decision

The machines using this installer can have different memory and storage capacities, and they can require different swap behavior depending on current workload. Because of that variability, swap sizing is chosen directly at install time.

The installer must ask two values in GB during setup:

- zram swap size in GB
- disk swap partition size in GB

Both values are chosen interactively at install time.

## Why

- Swap sizing is selected directly because no unrelated installer input predicts RAM pressure or VM workload on a specific machine; if tied to another input, machines with different hardware/load can receive wrong swap sizing.
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

- Swap values must be selected from memory, storage, and workload expectations.
- Very large disk swap values are valid but should trigger a warning about disk usage and potential thrashing.
- If `disk_swap_gb` is `0`, disk swap is disabled.
- If `zram_swap_gb` is `0`, zram swap is disabled.
