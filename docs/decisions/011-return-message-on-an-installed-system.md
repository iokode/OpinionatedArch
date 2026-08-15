# Return Message on an Installed System

**Work in progress. Nothing here is decided yet.**

This document will own what an installed machine carries so that its pre-boot return message can be rendered again after the installation, and what it keeps of the package and the theme that produced the one it has.

[Pre-Boot Ownership Message](010-preboot-ownership-message.md) says that changing the message on an installed system means rendering it again, which is why rendering is a tool of its own rather than installer-internal behaviour, and [oparch-return-message-render](../tools/oparch-return-message-render/000-command.md) gives that as the reason the tool exists apart from the installer. Neither decides what the target has to hold for it. The installer renders from the live medium, so an installation needs nothing there; the tool reads the body of the Plymouth script, and the default template package and theme, from its assets directory, and no installation puts an assets directory on the machine. Until one is decided, editing `/etc/opinionatedarch/return-message.yaml` and running the tool again does not work on an installed system.

Deciding to support it also decides what becomes of the package and the theme the operator actually used, and so whether the values file keeps naming where each came from or is rewritten to name local copies. [Remaining](../state/001-remaining.md) carries all of it as a pending decision.
