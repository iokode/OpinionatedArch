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

## The signing key

Made once, by `packages/generate-signing-key.sh`, and not again: there is one key, the job that publishes signs with it, and nobody signs by hand. Contributing needs no key at all. What runs that script a second time is a fork setting up a repository of its own.

It asks two things and does the rest: the address the key answers to, and the passphrase of the primary. It leaves the public half to be committed, the copy for continuous integration with its passphrase removed, and an archive of everything that has to go somewhere this project cannot reach. What each of those is for, and why the halves are held apart, is [Signing Key](../decisions/019-signing-key.md).

## Considerations

- What a `PKGBUILD` is handed to package is put beside it when a package is built and is no part of this repository, as [Repository Layout](002-repository-layout.md) records.
- A package whose contents change without its version changing is not republished, because the database says it is already there. That is the mechanism working, and it is why a change to what a package carries is a change to its version.
