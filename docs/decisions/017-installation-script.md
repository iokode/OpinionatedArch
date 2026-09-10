# Installation Script

## Context

An installation is made from a live environment that has this project's tools in it. Arriving at such an environment by writing an image to a stick is one way. Someone already sitting in front of an Arch live environment is one step away from another.

## Decision

OpinionatedArch publishes an installation script: a shell script, run on an Arch live environment, that leaves it able to install and then starts the installation.

It is served from the project's source repository, at a fixed address, and never from the package repository.

The script carries the fingerprint of the signing key's primary. It fetches the public key, refuses to go on if what it fetched is not that key, trusts it, configures the repository [Package Repository](016-package-repository.md) defines, installs `oparch-installer` from it, and runs it.

An installation made this way needs a network throughout, and gives the target what the repositories hold at that moment. It has nothing of its own to fall back on.

## Why

- The script exists because an image is a download and a stick to write, and neither is worth the trouble when an Arch live environment is already running. What [Installation ISO](018-installation-iso.md) carries, this fetches; that is the whole of the difference, and it is a fair trade when the machine already has a network.
- It is served from the source repository and not from the package repository because that is what makes carrying a fingerprint mean anything. One origin serving both the key and the packages it validates proves nothing, for the reason [Package Repository](016-package-repository.md) gives, and a script that took its key from the repository it is about to trust would be that arrangement written down.
- The fingerprint is in the script and the key is fetched, rather than the key itself being in the script, because rotating a subkey changes the published key and leaves the primary's fingerprint as it was. A script carrying the key would have to be rewritten at every rotation, and a file that is rewritten often is a file nobody reads before running.
- A mismatch stops the run rather than asking, because there is nothing to ask: a key that is not the expected one is either a mistake or an attack, and continuing on either is how a machine ends up trusting something nobody chose.
- Nothing is arranged to make this work without a network, because there would be nothing to work with: everything this way of installing uses arrives over one. Offline installation is what the image is for.

## Considerations

- This way of installing and the image do not root their trust in the same thing. The image is an artifact obtained once and deliberately; the script is what an address answered with at the moment it was asked. They differ, and neither document claims otherwise.
- The script leaves the live environment changed — a repository in its `pacman.conf`, a key in its keyring, packages installed. That is what a live environment is for, and nothing undoes it because nothing survives the reboot.
