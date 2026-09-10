# Signing Key

## Context

Every package this project publishes is signed, and every machine that installs one checks that signature against a key it was given. That key is the root of what an installed machine trusts. It is also used with nobody present, because publishing is not something a person is asked to attend.

What [Package Repository](016-package-repository.md) decides is that the signature is required and where trust in the key is established. This document decides the key itself: what it is, who holds which part of it, and how it is replaced.

## Decision

The key is Ed25519, and it has two halves that live apart.

**The primary key** certifies and revokes, and signs nothing else. It carries a passphrase, it never leaves its owner's keeping, and it does not expire. Its revocation certificate is made when the key is made and is kept beside it, away from any network.

**The signing subkey** is what signs the packages and the repository database. It carries no passphrase, and it is held as a secret of the project's continuous integration. What is exported there is the subkey alone: the primary is never copied into it.

The subkey is used in a context that runs nothing but the signing and the publication that follows it. What builds the packages runs elsewhere, and without the key.

### Rotation

A signing subkey is good for three years, and its three years have three parts.

1. **In its first year** it signs alone.
2. **When its second year begins**, its successor is created and bound by the primary, and `oparch-keyring` is published carrying that binding, signed by the subkey that is still in use. The outgoing subkey goes on signing for the whole of this year.
3. **When its third year begins**, signing moves to the successor. The outgoing subkey signs nothing more, and stays valid.
4. **At the end of the third year** it expires, having signed nothing for a year.

So a machine is given the next key two years before anything is signed with it, and everything the previous one signed stays verifiable for a year after it stopped signing.

## Why

- The key is Ed25519 because every link that touches it is current Arch — the container that signs, the image that verifies, the system that is installed — so there is no older implementation to accommodate and no compatibility question to answer.
- The key is split because its two halves face different threats. The primary sits on removable media, where the threat is that someone takes the media, and a passphrase is the answer to exactly that. The subkey sits in a secret store, where the threat is that someone reaches the store — and a passphrase kept in the same store is not an answer to that, because whoever reads one reads the other.
- The subkey carries no passphrase because the one case it covered was the key being exposed by accident from a job that also ran code nobody here wrote, and that job no longer holds the key. A measure whose failure case has been removed does not become harmless; it is read as protection by whoever finds it later.
- The subkey expires and the primary does not, because expiry contains a stolen subkey and cannot contain a stolen primary. Renewing a subkey means the primary signing its binding again, and the primary is not where the subkey is, so whoever takes the subkey cannot extend it: it stops working on a date they do not control. A primary renews itself, so its expiry stops nobody who has it — and if it lapses there is no way back, because the keyring that would carry its replacement is checked against the key that lapsed.
- The outgoing subkey keeps signing for a year after its successor exists, rather than the successor taking over the day it is created, because the keyring that introduces it has to be verifiable by a machine that has not seen it yet. A machine reached by packages signed with a key it does not know cannot check the very package that would teach it that key, and announcing the key early would buy nothing.
- Three years bounds how long an undetected theft of a subkey stays useful, and the three years are cut in three so that neither end of a rotation is a cliff. A machine has two years in which to learn the next key before anything is signed with it, rather than one. And the key that stops signing does not stop being valid on the same day: it has a year in which what it signed is still checkable, so a machine coming back after a long silence can install what is in the repository while it catches up. Moving the signing on the day of the expiry would leave a repository full of packages signed by a key that had just died.
- The signing context runs nothing else because the key is in plain text in that context's memory, and anything running beside it can take it. Building runs `makepkg`, a compiler and a language toolchain — a great deal of code nobody here wrote, which changes without being looked at. Keeping that away from the key is the only measure here that removes a cause rather than covering an effect.
- The revocation certificate is made at the same time as the key because it cannot be made afterwards by someone who has lost the key, and losing the key is the case it exists for.

## Considerations

- The primary is kept where it can be reached quickly. Revoking a subkey and issuing another needs it, and the day that is needed is not a day to go looking for it.
- A subkey that is replaced early, because it was compromised rather than because it aged, follows the same order as a rotation and cannot follow a shorter one: a machine still has to be given the new key by something it can already verify.
