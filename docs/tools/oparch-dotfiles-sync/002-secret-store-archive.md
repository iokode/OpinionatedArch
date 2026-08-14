# Secret Store Archive

## Context

A map declares the secrets its renders need and never carries their values, so that a dotfiles package can be published without publishing credentials. The values live in the local store defined in `001-map-format.md`, which `oparch-dotfiles-sync` only ever reads.

That leaves the question of how a store reaches a machine that has none. During an installation there is no store at all: the machine is being made, and the tool runs before its first boot. Typing each value at the console is the obvious answer and a bad one — an API token is long, unmemorable, and typed blind on a console whose layout was chosen minutes earlier.

## Specification

### The file

A secret store travels as one file with the extension `.dfsec`, beside `.dfmap`.

Its content is a `tar` archive of a store's own tree — the `global` and `user` directories of `001-map-format.md`, with the same names inside — encrypted whole with a passphrase.

Unlike a map, a `.dfsec` is identified by its name alone. A map is recognised by the header at its first byte, and there is nothing to recognise in an archive whose bytes are ciphertext.

### The encryption

The archive is an `age` file, encrypted with a passphrase: `scrypt` derives the key, and the payload is sealed with ChaCha20-Poly1305 under a 256-bit key. Any implementation of the `age` format produces and reads one; the `age(1)` command line does, and so does the `age` Rust crate the installer opens it with.

### The passphrase

The passphrase is what protects the archive wherever it travels, so it is generated rather than invented: sixteen words from the EFF short wordlist, which is about 165 bits.

It is not confirmed against a second copy of itself, anywhere it is asked for. An archive that does not open is what a wrong passphrase looks like, immediately, so retyping is the check and there is nothing for a second copy to catch.

### What opens it, and where

Whoever opens one decrypts it and unpacks the archive that comes out. The two are separate: unpacking is what every other archive in this project gets, including the refusal of an entry that would be written outside the directory it is unpacked into.

Nothing writes a `.dfsec`. Producing one is `oparch-secret-export`, which does not exist yet and is tracked in `../../state/001-remaining.md`.

## Why

- The store travels as one file because the alternative is typing each value into a console, which is what a store exists to make unnecessary; a machine being installed has many secrets and one operator.
- It is encrypted because a file that travels on a removable medium or from a URL is a file that can be lost or fetched by someone else, and the values inside it are credentials. Unencrypted, the medium would be as sensitive as the machine.
- The extension is the only identification because the content is opaque by construction; a magic rule over ciphertext would recognise the encryption format and say nothing about what this project uses it for.
- A generated passphrase of that length is used because the archive's own strength is all that protects it once it has left the machine, and because a passphrase chosen by a person is the part of this that is guessed. At that length the key derivation stops being what an attack turns on.
- The passphrase is not confirmed because the archive confirms it: an unopened archive is an immediate, unambiguous answer, which is what a confirmation field exists to obtain and does not.
- Decryption and unpacking are kept apart because the refusal of escaping entries is already written, tested and shared; folding it into whatever decrypts would be a second copy of a rule this project has one of.

## Considerations

- A store is decrypted into a temporary directory before it is installed. During an installation that directory is on the live medium's `/tmp`, which is memory, so the values in the clear never reach a disk that is not the encrypted one they are being installed onto.
- The archive carries no record of which map it was made for. A store holding more than a plan needs is not an error; a store missing something it needs is, and it is reported by name.
- Rotating a secret means producing a new archive. Nothing edits one in place.
