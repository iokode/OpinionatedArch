# Network Stack

## Context

The system must manage Ethernet, Wi-Fi, and VPN connections, and its DNS and routing needs vary by machine and network environment.

## Decision

The base network stack for this project is:

- `NetworkManager`
- `systemd-resolved`

`NetworkManager` uses `systemd-resolved` for name resolution, and `/etc/resolv.conf` points to the resolved-managed path.

Connection profiles stay in the DHCP/auto baseline by default.

Advanced per-machine DNS/routing policy is intentionally post-install.

## Why

- `NetworkManager` is required because this project needs one practical manager for Ethernet, Wi-Fi, and VPN without splitting each concern into separate management layers; if separate layers are used early, service sprawl and operational complexity increase.
- `systemd-resolved` is required because planned VPN use needs DNS behavior that can be scoped per link/domain and route intent; if resolved is not used, implementing route-scoped DNS policy is less direct and less consistent.
- Keeping installer networking at DHCP/auto baseline is required because machine-specific network policy varies by environment; if static policy is hardcoded in installer, portability and reuse across machines are reduced.
- Deferring advanced DNS/routing rules to post-install is required because those rules depend on real network context and VPN topology; if encoded prematurely, the installer can apply incorrect assumptions.

## Considerations

- Running both `NetworkManager` and `systemd-resolved` is intentional in this policy.
- Do not enable competing network managers in parallel for the same interfaces.
