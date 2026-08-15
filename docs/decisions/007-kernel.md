# Kernel

## Context

Several kernel options are available in official Arch repositories (`linux`, `linux-lts`, `linux-zen`, `linux-hardened`). A multi-kernel setup can provide fallback options, but it also increases maintenance overhead, especially when external modules or DKMS workflows are involved.

## Decision

The selected strategy is single-kernel: install and maintain only `linux`.

## Why

- Single-kernel strategy is chosen because multi-kernel setups multiply package/header/module maintenance work (especially with external modules or DKMS); if multiple kernels are maintained, update and module-failure surface grows significantly.
- `linux` is selected as the only installed kernel because it is the standard Arch kernel path for this project baseline and minimizes operational branches; if extra variants are installed by default, ongoing maintenance overhead increases without a currently accepted benefit.
- Keeping one kernel only is accepted even for failure scenarios because this project prioritizes low maintenance over local multi-kernel fallback paths; if multiple kernels are added as default fallback, update and compatibility burden grows. Recovery is delegated to external live-environment.

## Considerations

- All referenced kernel variants are official Arch packages, but they serve different trade-offs.
- This decision can be revisited later if explicit requirements justify multi-kernel maintenance.
