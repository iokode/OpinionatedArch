# Package Repository

## Context

OpinionatedArch is built as a set of tools, and those tools have to reach the machines that run them: whatever installs a system, and the system it installs. A machine also outlives the version of a tool it was given, so how a tool arrives is also how it is replaced.

## Decision

OpinionatedArch publishes its tools as pacman packages, in a repository of its own.

The repository is named `oparch` and is served over HTTPS from `https://packages.oparch.iokode.dev`, for the `x86_64` architecture. It is a set of static files — the packages, their signatures and the repository database — and nothing runs on the serving side.

It holds one package per tool this project ships, and `oparch-keyring`, which carries the public half of the key the rest are signed with.

Every package and the repository database are signed, and the signature is required: pacman is configured for this repository with `SigLevel = Required TrustedOnly`, wherever an installation runs and on every installed system alike. The private half of the key is held by the project's continuous integration, which signs what it publishes, and nothing reaches the repository unsigned.

Trust in that key is anchored in an origin other than the one the repository is served from: whatever tells a machine which key to trust does not come from the same place as the packages that key validates. An installation gives the target that key rather than sending it to fetch one.

Each package declares its own dependencies, so installing a tool brings what that tool needs onto whichever system it is installed. What those are is the `Requirements` section of the tool's own document.

An installed system carries this repository configured above the official Arch repositories. A package name present in both resolves to this one.

An installed system gets every tool this project ships except `oparch-installer`, which is published here because that is how it reaches the live environment it runs in, and is installed on no target.

## Why

- The tools are published as packages because a machine has to be able to say which version of a tool it runs and to replace it without help, and pacman already answers both for everything else on it; a tool that arrives as a copy is a file whose provenance is whatever the person who copied it remembers.
- Signatures are required because the repository is fetched over the network by a machine that is being built, at the moment it has least to check anything against. A signature moves that check to a single deliberate act — trusting one key, once — instead of repeating it at every fetch, where it would be made by nobody.
- The private key is held by continuous integration because the packages are rebuilt on a schedule and the medium is published with them; a key that only one machine holds makes every publication wait for that machine to be switched on, and a publication that waits is one that stops happening. What that costs is accepted rather than hidden: whoever controls the project's continuous integration can sign packages this system will install without question.
- The key is anchored somewhere other than the repository because a keyring fetched from the repository it protects proves nothing. A certificate authenticates who answers, not what they answer, so an origin that has been taken over serves valid TLS with whatever it likes; and if it serves both the packages and the key that validates them, the signature attests only that the content came from whoever holds that origin, which is what the transport already said. The separation reaches exactly that far: it stops whoever serves the packages from also supplying the key that vouches for them, and constrains nothing about whoever can use the key itself.
- Dependencies are declared by the packages rather than listed by whatever installs them, because a list kept beside the medium and a list kept beside the tool are two lists that have to agree, and only one of the two travels to the installed system.
- The repository sits above the official repositories so that where a package comes from is fixed by this project rather than by what Arch adds later. Below them, the same name appearing upstream would silently move a tool's origin, and the machine would stop being the one this project describes without anything having been changed on it.
- `oparch-installer` is not installed on a target because it is not an operational tool: [Oparch Tools](015-oparch-tools.md) sets it apart as the one that runs from the live environment and installs the system in the first place. On an installed system every use of it would be a mistake.
- The rest are installed on a target because the machine keeps changing after the installation, and what a decision of this project governs is kept by a tool of this project rather than by hand.

## Considerations

- The repository is static files, so there is no index to generate and no listing to keep in step. What pacman reads is the database, and writing the database is what publishing means.
- Do not add a second path by which a tool reaches a machine. A copy standing beside a package is a version that nothing can account for.
- How the packages are built and published is not decided here: it belongs to the project's own working environment rather than to the distribution.
