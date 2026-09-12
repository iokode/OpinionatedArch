# Building and Publishing

How what this project ships gets built and how it reaches the place it is published from. What is published, and how a machine comes to trust it, is decided in [Package Repository](../decisions/016-package-repository.md) and [Signing Key](../decisions/019-signing-key.md); both say that the machinery is not theirs, and this is where it is.

It describes the project's own working environment. Nothing here is installed on a machine.

## What a publication is

A merge to `master` runs it. What gets published is not worked out from what the merge changed: each `PKGBUILD` declares a version, the published repository database says which versions it already holds, and what is missing from the second is built and added.

That is deliberate, and it is the difference between asking the tree and asking the repository. A run that adds nothing changes nothing. A run repeated changes nothing the second time. A publication that failed after uploading some of its packages is finished by the next run rather than unpicked by hand. And nothing has to reason about merges, rebases or a run that was skipped, because the question is never "what happened" but "what is missing".

Publishing a tool is therefore raising its version in its `PKGBUILD`. That is the act, it is one line, and it is visible in the diff of the change that earned it.

## Two jobs, and what each may touch

The build job holds no secret. It installs the toolchain, compiles the tools, and hands the packages over as an artifact.

The publish job holds the signing key and runs nothing but the signing and the upload that follows it. Nothing of this project's toolchain is installed there.

The split is the whole of the protection there is. The key is in plain text in that job while it is used, so anything running beside it can take it — and building runs `makepkg`, a compiler and a language toolchain, which is a great deal of code nobody here wrote and which changes without being looked at. Keeping that away from the key removes the cause rather than covering the effect; masking output and passphrases cover effects, and were tried and dropped for saying more than they did.

The key is given to that job through an environment of its own, because a secret of the repository is readable by any job in it, and one attached to an environment only by a job that names it.

## What is pinned, and where each version comes from

Three things are fixed, and each is fixed once:

- **The BAML wrapper**, by version and by checksum, and fetched as a release archive rather than through an installer script pulled from the network and run. Its version and its checksum are written in the composite action and nowhere else.
- **The BAML toolchain**, read from `Cargo.lock`. That file already carries the version the host was resolved and built against, so writing it a second time would be inviting the two to disagree. The runtime library the host loads is fetched the same way, from the manifest the toolchain leaves cached, which names its address and its checksum for the version already fixed.
- **The actions**, by commit rather than by major version. A major tag is moved by whoever owns the action, so the code running in these jobs could change without this repository changing. That matters most for the one that hands the packages to the job that signs them: what runs there decides what the key vouches for.

A pin goes stale on its own, and a stale pin is a fix nobody received, so Dependabot proposes the moves as pull requests. Cargo is left unwatched on purpose: `baml_bridge` is pinned to the nightly its toolchain is pinned to, and they move together or not at all.

## What makepkg is asked to do

It packages. It does not compile.

That is not a preference: the BAML toolchain is not an Arch package, so there are no `makedepends` that would bring it, and `makepkg` in a clean chroot would have nothing to build with. So the build job compiles, leaves the results beside each `PKGBUILD`, and the definition's `source` names those local files.

Two things follow. A `PKGBUILD` here does not build on its own from a fresh clone — what it packages has to be produced first, which is what the workflow does. And `makepkg` is not asked to sign, which it would otherwise do with a key it would have to be given; signing happens in the other job, which is the only one that has one.

## The repository has memory

A package repository only grows, and its database is state that accumulates. `repo-add` adds to the database it is given, so the published one is fetched before anything is added to it; adding to an empty database instead would publish a repository holding only what was built that day.

Object storage has no symbolic links. What `repo-add` leaves as a link — the short name pacman actually asks for — is uploaded as a file of its own under both names, or nothing would answer the request. Packages go up before the database that names them, so a database is never published pointing at a file that is not there.

One run publishes at a time. The database is the one thing two of them would damage between themselves, and neither is cancelled half way.

## How the image is built

The profile is not kept here. `releng` is archiso's, it moves with archiso, and holding a copy would be maintaining a fork of a bootloader configuration nobody in this project wrote — while the reason the image is rebuilt at all is precisely that upstream moves. So the profile is assembled at build time: a copy of `releng` as it is on the day, with this project's differences applied over it. What is kept in `archiso/` is only the difference — what the medium adds, what it drops, what its own repository carries, and the one file that starts the installer.

The medium's repository is filled by downloading rather than installing: what is wanted is package files, so that an installation with nothing to fetch from has something to install. Every package an answer might ask for is fetched, and not the ones a particular answer would, because an installation without a network cannot go and get the microcode of the processor it turns out to be running on.

Two repositories end up in the live system's `pacman.conf`. Their order separates them: the published one above the official ones, because packages of this project's are this project's wherever else a name appears; and the medium's own below everything, because it is what answers when nothing else can and never what wins while something else can. Above means in front of the first repository already in the file, not appended to the end of it, which is where every official one would then be ahead of it. What is asked of them separates them too — the published one has to be signed and the medium's own is not checked at all, for the reason [Installation ISO](../decisions/018-installation-iso.md) gives.

Both configurations also name where packages are looked for before any of them is fetched: the target's own cache, and the medium's repository. That is the same directory that serves the repository, so the files are on the image once and named twice, and an installation with a network does not download a package the medium already holds at the version being installed. That file is generated from the profile's own rather than written out a second time, so the repositories an image was built from and the ones it installs from cannot come to disagree.

A second configuration is written beside the medium's repository, holding that repository and no other. It is what an installation told it has no network is run with, and the installer names it by its path: with it there is nothing to synchronise and nothing to reach for, where the live system's own would try the official repositories first and fail on all of them. It carries the same options the medium was built under, taken from the profile's file rather than written again, and the stanza naming the repository is written once for both.

It is built in a container that is allowed more than containers usually are, because `mkarchiso` makes filesystems and mounts them.

What is built is then tested, and only published if it passes. The cases in [End-to-End Testing](006-end-to-end-testing.md) boot the image that was just made, install machines from it and boot what they installed, and a case that fails leaves the image where it was built. That is what running it here rather than afterwards is for: an image that does not install a machine that boots never becomes the one anybody downloads.

The build is read for one thing afterwards, and fails on it: one of this project's own packages whose install scriptlet failed. Those scriptlets are where a package arranges what installing it means — the project's key reaches the medium through one of them — and pacman does not fail a transaction when one fails. It reports it and carries on, `mkarchiso` finishes, and the image is published missing whatever that scriptlet was there to do, with every step green. Its report is the only signal there is, so it is what the build looks for.

It is read for this project's packages only. Upstream scriptlets fail here as a matter of course: `mkinitcpio` ends every build of this image reporting errors, because it goes looking for firmware nobody ships for modules nothing here uses, and a build stopped by that is a build that never finishes. What this project ships is its own to get right, and is what this holds to working.

Images are named for the minute they were built. That is not decoration: what sorts last is what was built last, which is how the one that is kept is told from the one it replaces, and how the addresses that always answer with the newest find it. Two things depend on that, the prune and the Worker, and both would have to change together if that name ever did. They also have to agree on what sorting is: the Worker orders by code unit, having no locale to take, so the prune is pinned to bytes rather than left to the locale of whatever ran it — a locale-aware sort weighs punctuation differently, and the two would then disagree about which image is the current one. The minute is there rather than the day because more than one image is built on some days, and two images with one name is the second replacing the first in a bucket where nothing says it happened; it holds where a counter would not, since a name reaching further in time reaches further in order at a width that never changes.

The prune runs after the new image is up and not before, so that an upload which fails leaves the two that were there rather than one. It costs a few minutes with three of them in the bucket, which is what that is worth.

## What runs at the edge

Two addresses answer with whatever image is newest and with its checksum, and what answers both is one Worker that reads the bucket rather than being told — the checksum is stored beside the image under the image's own name, so finding the current image finds both. It is deployed by a workflow of its own, when what is in `.cloudflare/` changes and not otherwise, so that what is deployed is what was committed rather than what somebody remembered to push by hand.

It is not deployed alongside the image it points at. That is published every day and this changes almost never, and joining them would mean a failure to deploy taking down the publication of an image that was fine.

The token it is given can rewrite what the project's own addresses answer with, which is neither the signing key nor write access to a bucket, so it lives in an environment of its own and is reachable from nothing else.

## The signing key

Made once, by `packages/generate-signing-key.sh`, and not again: there is one key, the job that publishes signs with it, and nobody signs by hand. Contributing needs no key at all. What runs that script a second time is a fork setting up a repository of its own.

It asks two things and does the rest: the address the key answers to, and the passphrase of the primary. It leaves the public half to be committed, the copy for continuous integration with its passphrase removed, and an archive of everything that has to go somewhere this project cannot reach. What each of those is for, and why the halves are held apart, is [Signing Key](../decisions/019-signing-key.md).

## Considerations

- What a `PKGBUILD` is handed to package is put beside it when a package is built and is no part of this repository, as [Repository Layout](002-repository-layout.md) records.
- A package whose contents change without its version changing is not republished, because the database says it is already there. That is the mechanism working, and it is why a change to what a package carries is a change to its version.
