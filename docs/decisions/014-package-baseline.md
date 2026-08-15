# Package Baseline

**Work in progress. Nothing here is decided yet.**

This document will own what every OpinionatedArch machine has installed on it whatever it is for — development tools, firmware and core utilities — and what is left to be installed afterwards by whoever uses it.

Nothing decides it today, and `../state/001-remaining.md` carries it as a pending decision. What the rest of the documentation fixes is not a baseline but the packages one decision requires to hold: the kernel `007-kernel.md` names, the network stack `017-network-stack.md` selects, and Plymouth, which `012-mkinitcpio-hooks.md` requires in the target before the initramfs is built whenever the return message is enabled.

The project's own tools are the other half of the question. What each of them requires to find installed where it runs is the `Requirements` section of its command document, and `../state/001-remaining.md` carries putting those packages on the installed system and on the project's medium as work that has not been done. A baseline that leaves them out leaves a machine whose own tools do not run on it.
