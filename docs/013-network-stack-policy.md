# 013: Network Stack Policy

## Context and Decision

The base network stack for this project is:

- `NetworkManager`
- `systemd-resolved`

Advanced per-machine DNS/routing policy is intentionally post-install.

## Why

- `NetworkManager` is required because this project needs one practical manager for Ethernet, Wi-Fi, and VPN without splitting each concern into separate management layers; if separate layers are used early, service sprawl and operational complexity increase.
- `systemd-resolved` is required because planned VPN use needs DNS behavior that can be scoped per link/domain and route intent; if resolved is not used, implementing route-scoped DNS policy is less direct and less consistent.
- Keeping installer networking at DHCP/auto baseline is required because machine-specific network policy varies by environment; if static policy is hardcoded in installer, portability and reuse across machines are reduced.
- Deferring advanced DNS/routing rules to post-install is required because those rules depend on real network context and VPN topology; if encoded prematurely, the installer can apply incorrect assumptions.

## Implementation Plan

1. Install `networkmanager` in the target system.
2. Enable `NetworkManager.service`.
3. Enable `systemd-resolved.service`.
4. Ensure resolver integration is active (NetworkManager uses `systemd-resolved`; `/etc/resolv.conf` points to resolved-managed path).
5. Leave connection profiles in DHCP/auto baseline by default.
6. Apply machine-specific static routes and VPN DNS/routing rules after installation.

## Considerations

- Running both `NetworkManager` and `systemd-resolved` is intentional in this policy.
- Do not enable competing network managers in parallel for the same interfaces.
