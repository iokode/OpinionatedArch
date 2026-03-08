# 007: Kernel Strategy

## Context and Decision

Several kernel options are available in official Arch repositories (`linux`, `linux-lts`, `linux-zen`, `linux-hardened`). A multi-kernel setup can provide fallback options, but it also increases maintenance overhead, especially when external modules or DKMS workflows are involved.

The selected strategy is single-kernel: install and maintain only `linux`.

## Why

- Single-kernel strategy is chosen because multi-kernel setups multiply package/header/module maintenance work (especially with external modules or DKMS); if multiple kernels are maintained, update and module-failure surface grows significantly.
- `linux` is selected as the only installed kernel because it is the standard Arch kernel path for this project baseline and minimizes operational branches; if extra variants are installed by default, ongoing maintenance overhead increases without a currently accepted benefit.
- Recovery is delegated to external live-environment workflow because failures in the local boot chain can invalidate all local kernel entries together; if recovery relies mainly on local kernel fan-out, it creates false confidence in scenarios where local boot is already broken.

## Implementation Plan

1. Install only `linux` and `linux-headers`.
2. Do not install `linux-lts`, `linux-zen`, or `linux-hardened` by default.
3. Keep GRUB entries focused on the installed kernel.
4. Document and maintain a live-environment recovery path using chroot.

## Considerations

- All referenced kernel variants are official Arch packages, but they serve different trade-offs.
- A local GRUB entry that chains to a live `.efi` binary is not considered a complete recovery guarantee unless the full live runtime payload is also available and compatible.
- If the boot chain itself is broken, internal fallback entries are irrelevant; external live media remains the robust recovery path.
- This decision can be revisited later if role-specific requirements justify multi-kernel maintenance.
