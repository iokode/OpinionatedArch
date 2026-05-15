# 016: Oparch Tools

This document defines operational tools provided by OpinionatedArch. Each tool has a single purpose and is designed to keep recurring system tasks consistent.

## Tool: `oparch-user-create`

### What it does
Creates a new login user with the required baseline policy: account, groups, home subvolume, and initial home directory ownership.

### Why it is needed
Creating login users manually is error-prone and can break assumptions used by snapshot and permission policies. A single command ensures new users always match the expected model.

## Tool: `oparch-user-remove`

### What it does
Removes a login user, including account removal, home-subvolume removal, and mount/fstab cleanup. The command asks whether home data should be preserved. If preservation is selected, it asks for a destination login user and copies data to `/home/<target-user>/other-users-home-data/<removed-user>` before removal.

### Why it is needed
Manual user removal can leave inconsistent state (stale fstab entries, mounted paths, orphaned subvolumes). A dedicated command keeps removal deterministic while offering an explicit and repeatable data-preservation path.

## Tool: `oparch-password-rotate`

### What it does
Rotates the shared secret used by disk encryption and login users. It changes the LUKS passphrase on the encrypted root device and updates all members of `login-users` to the same new password. It accepts old and new passwords via parameter for scripting, and when password parameters are omitted it reads them with `read -s`.

### Why it is needed
The system model uses one shared secret for both disk unlock and login users. Rotating that secret manually in multiple places is error-prone and can desynchronize boot unlock and account login. A dedicated command keeps both sides synchronized in one operation.

## Tool: `oparch-dotfiles-link`

### What it does
Creates and refreshes links from the shared dotfiles source into target user/system paths.

### Why it is needed
Manual linking drifts over time and is hard to audit. A dedicated command keeps linking behavior repeatable and prevents per-user divergence.

## Tool: `oparch-snapshot-system-create`

### What it does
Creates a manual system-scope snapshot under `/snapshots/system/manual` and requires a human-readable justification in the snapshot name or label.

### Why it is needed
System-level manual checkpoints are required before risky non-package changes. Mandatory justification keeps long-lived manual snapshots understandable later.

## Tool: `oparch-snapshot-user-create`

### What it does
Creates a manual user-scope snapshot under `/snapshots/home/<login-user>/manual` for a selected login user.

### Why it is needed
User data operations can be destructive and are often user-specific. A per-user command makes rollback anchors precise and avoids cross-user ambiguity.

## Tool: `oparch-snapshot-restore`

### What it does
Restores snapshots for both scopes (`system` and `home/<login-user>`) using the single `@snapshots` path layout. User-scope restore can run on the installed system with controlled session state. System-scope restore must run offline from an external environment (for example live media + chroot).

### Why it is needed
Recovery must be deterministic during incidents, and restore safety differs by scope. A single restore interface with explicit online/offline rules avoids ad-hoc procedures, reduces operator mistakes, and prevents fragile system-root rollback while the system is running.
