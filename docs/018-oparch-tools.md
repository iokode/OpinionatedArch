# 018: Oparch Tools

This document defines operational tools provided by OpinionatedArch. Each tool has a single purpose and is designed to keep recurring system tasks consistent.

## Tool: `oparch-user-create`

### What it does
Creates a new login user with the required baseline policy: account, groups, home subvolume, and initial home directory ownership.

### Why it is needed
Creating login users manually is error-prone and can break assumptions used by snapshot and permission policies. A single command ensures new users always match the expected model.

## Tool: `oparch-dotfiles-link`

### What it does
Creates and refreshes links from the shared dotfiles source into target user/system paths.

### Why it is needed
Manual linking drifts over time and is hard to audit. A dedicated command keeps linking behavior repeatable and prevents per-user divergence.

## Tool: `oparch-snapshot-system-create`

### What it does
Creates a manual system-scope snapshot under `/snapshots/system` and requires a human-readable justification in the snapshot name or label.

### Why it is needed
System-level manual checkpoints are required before risky non-package changes. Mandatory justification keeps long-lived manual snapshots understandable later.

## Tool: `oparch-snapshot-user-create`

### What it does
Creates a manual user-scope snapshot under `/snapshots/<login-user>` for a selected login user.

### Why it is needed
User data operations can be destructive and are often user-specific. A per-user command makes rollback anchors precise and avoids cross-user ambiguity.

## Tool: `oparch-snapshot-restore`

### What it does
Restores snapshots for both scopes (`system` and `<login-user>`) using the single `@snapshots` path layout. User-scope restore can run on the installed system with controlled session state. System-scope restore must run offline from an external environment (for example live media + chroot).

### Why it is needed
Recovery must be deterministic during incidents, and restore safety differs by scope. A single restore interface with explicit online/offline rules avoids ad-hoc procedures, reduces operator mistakes, and prevents fragile system-root rollback while the system is running.