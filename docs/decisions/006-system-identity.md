# System Identity

## Context

Machine identity is installation-specific input.

## Decision

The hostname is configurable.

It lives in `/etc/hostname`, which is where the installed system reads it from.

`/etc/hosts` is left as the base system provides it, with no mapping of its own.

## Why

- The hostname is configurable because it names one machine among the operator's, and a name fixed by this project would be the same on all of them.
- `/etc/hostname` is where it goes because that is the canonical source for the installed system; anywhere else, the name would not survive a reboot.
- Not modifying `/etc/hosts` is required because current baseline behavior works without custom host mappings and no concrete issue requires overrides; if `/etc/hosts` is customized without need, policy adds arbitrary maintenance surface.

## Considerations

- If a future service requires explicit local hostname mapping, update this decision with a concrete requirement.
- Hostname policy here is independent from network-stack selection and DNS policy.
