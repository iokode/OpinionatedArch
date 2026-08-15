# Security Baseline

**Work in progress. Nothing here is decided yet.**

This document will own what an installed machine does about the network reaching it and about privilege on it: whether a firewall is installed and what it lets through, whether SSH is on the machine at all, and the sudo policy for the accounts that are not work contexts.

Part of it is decided elsewhere and this document does not reopen it: `000-work-contexts-and-accounts.md` gives work contexts passwordless sudo, leaves `root` without a password and not intended for interactive login, and states both as deliberate. What is missing is everything around them.

`../state/001-remaining.md` carries the rest as a pending decision.
