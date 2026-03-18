# 017: System Identity Policy

## Context and Decision

The installer asks for the machine hostname.

The installer writes the selected value to `/etc/hostname`.

The installer does not modify `/etc/hosts` in this phase and keeps the default file content provided by the base system.

## Why

- Asking for hostname is required because machine identity is installation-specific input; if hostname is not requested, identity must be fixed or inferred and can be wrong for the target machine.
- Writing `/etc/hostname` is required because this is the canonical hostname source for the installed system; if skipped, hostname persistence is undefined.
- Not modifying `/etc/hosts` is required because current baseline behavior works without custom host mappings and no concrete issue requires overrides; if `/etc/hosts` is customized without need, policy adds arbitrary maintenance surface.

## Implementation Plan

1. Prompt for `hostname` during installation.
2. Validate hostname format before writing.
3. Write hostname to `/etc/hostname`.
4. Leave `/etc/hosts` unchanged from base system defaults.

## Considerations

- If a future service requires explicit local hostname mapping, update this decision with a concrete requirement.
- Hostname policy here is independent from network-stack selection and DNS policy.
