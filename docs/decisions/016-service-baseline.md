# Service Baseline

**Work in progress. Nothing here is decided yet.**

This document will own which units an installation leaves enabled on a machine. It is the list rather than the individual choices: a decision that puts a component on the system says what that component needs running, and this is where what starts on a booted machine can be read at once.

`../state/001-remaining.md` carries it as a pending decision. What exists today is scattered by construction — `017-network-stack.md` selects `NetworkManager` and `systemd-resolved`, and `004-snapshots.md` requires a snapshot at boot, on every package transaction and at login, which is something enabled for each of the three — and no document states the resulting set.

The snapshot half is also moving: `../state/001-remaining.md` carries removing `snapper` and `snap-pac` in favour of the project's own snapshot tools, so what is enabled for snapshots today is not what this document will decide.
