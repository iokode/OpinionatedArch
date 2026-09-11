# Installation ISO

## Context

An installation starts from a live environment, and everything the installer does, it does with what that environment carries. What an installation is made from is therefore part of what the installation is, and not merely how it was delivered.

## Decision

OpinionatedArch ships an installation ISO: an image for `x86_64`, built with `archiso` from its `releng` profile.

An image is built and published every month, against the packages current when it is built. Images are served over HTTPS from `https://iso.oparch.iokode.dev`, out of object storage of the project's own, in a bucket apart from the one the packages are in and reached with credentials of its own. Each has its checksum beside it. The two most recent are kept and the ones before them are deleted.

Two further addresses, `https://oparch.iokode.dev/latest.iso` and `https://oparch.iokode.dev/latest.sha256`, answer with whichever image is newest and with the checksum of that same one. They are published because the images are named for the minute they were built, so the address of any one of them stops being the address of the current one as soon as there is another, and both the image and what says it is the image have to be linkable.

The checksum is what the project says about an image, and checking it is how someone tells they have the one that was published.

### What the image carries

The `releng` profile already carries most of what an installation calls. On top of it the image installs the project's own packages, from the repository [Package Repository](016-package-repository.md) defines: every tool an installation runs from the live environment or hands to the target, and the keyring they are checked against.

Everything else those tools need arrives as their declared dependencies, and is on the image because they are. What each of them needs is the `Requirements` section of its own document.

The BAML runtime library travels inside `oparch-installer` and the installer is pointed at the copy on the image. It is never downloaded: a library that is not there is a failure of the run and not a fetch.

The image also carries a repository of its own, holding the bootstrap package set an installation puts into the target and the project's own packages, so that a machine can be installed with no network at all.

Which of the two an installation draws from is settled by whether it has a network, and it is settled deliberately. Given a network, the official repositories take precedence and the target is given what is current on them. Given none, the target is given what the image carries. An installation proceeds without a network because it was told to, and never because reaching for one failed: a synchronisation that fails after a network was configured is a failed run, not a quiet fall back to the image.

### What the image does

The image starts `oparch-installer` on its own, and leaves it reachable as a command, because the installer can be left and re-entering it is how that is undone.

## Why

- The project ships an image of its own because the tools need an environment the official one does not provide, and providing it at run time makes an installation depend on the network before it has configured any, and on the mirrors agreeing with the age of what is fetching from them. [End-to-End Testing](../development/006-end-to-end-testing.md) records three failures that are all of them that, and not one of them is a defect in the installation.
- The cadence is monthly because it is Arch's, and what ages on this image ages on Arch's clock rather than on this project's. Two things age: the keyring, which reaches a day when it cannot verify packages signed by packagers it never knew, and the kernel the image boots, which reaches a day when it does not bring up the machine it was booted on — and a new machine is the case an installer exists for. The image is `releng`, the project's own packages and the bootstrap set it carries, so following upstream keeps all three within a month of what Arch considers current — and carrying that set is what puts it on this clock at all, since an installation made from the image installs the image's age. The project's own tools are rebuilt by the same publication, so the image stays current in them without needing a cadence of its own.
- The runtime is carried rather than downloaded because that download would fall at the one moment the machine has no network of its own yet, and because two runs of one image that fetch their own runtime are two different installations. A missing library that fails the run says so while there is still someone there to be told.
- The image carries the bootstrap set because an installation happens at the one moment a machine has no network of its own, and an image that cannot build a system without one is missing exactly where it is most needed: a machine with no socket to plug into, or a wireless network the installation has not reached yet. Carrying it also makes an installation without a network reproducible, since the same image then builds the same system — which is the thing this project asks of a machine a year later.
- Offline is entered and not fallen into, because a machine installed at the age of its image while its owner believed it was installed at today's is a machine nobody can account for. The distinction costs an answer on a screen and buys the difference between a decision and an accident.
- The image starts the installer because installing this system is the only thing the image is for. What the operator would otherwise type is the same every time, and a prompt whose one correct use is a fixed command is a step that can be got wrong and never a step that can be got right in a new way. It stays reachable as a command for the opposite reason: the installer can be left, and there has to be a way back in that is not booting the machine again.
- Two are kept because that is what the storage they are published to holds. An image carries the packages it installs, which is what makes it the size it is and what the alternative to it was — an image that could not install without a network — and a few of them is the whole of the space there is. The number is not a judgement about which images are worth having; it is the limit, and the two that survive it are the last two. What that costs is said rather than argued away: a machine was installed from one of them, and which one is part of what that machine is, so an image that has been deleted is an installation that cannot be repeated from the medium it was made with. What survives of an older one is its name and its checksum in whatever recorded them, which says which image a machine came from without being able to produce it.
- The images are kept apart from the packages, in their own bucket, because things are deleted out of this one. A repository whose whole property is that nothing in it disappears is not a place to run a rule that removes files, and the two are read by different things at different rates anyway.
- Images are not published beside the packages, because the two are fetched differently: a repository is read by machines, from an address written into every `pacman.conf`, and has to stay where it was put, while an image is fetched once, by a person, and the whole history of them has to fit somewhere without a storage budget deciding what survives. And they are not attached to releases either, which would have served that: carrying the bootstrap set adds about a gigabyte of packages to an image that already weighs one and a half, and a release may hold no file larger than two. Between an image that can install without a network and a place that was convenient, the first is the one that was decided.
- The checksum is published because an image is the one thing here that nothing else vouches for. Every package it carries is signed, and the key that signs them is checked against a fingerprint that arrives from somewhere else — but the image itself is a file on a server, and if that server serves a different one nothing in it would say so. A checksum published apart from it is what closes that, and it closes it only if someone checks, which is the trade a medium fetched by a person makes.

## Considerations

- An installation with a network gives the target what the repositories hold at that moment; the copies on the image are what an installation without one uses. Either way, what a target runs after its first update is pacman's business and not the image's.
- How the image is built and published is not decided here: that machinery belongs to the project's own working environment rather than to the distribution.
