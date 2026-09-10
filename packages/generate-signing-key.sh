#!/usr/bin/env bash
#
# Creates the one signing key a package repository is published under, as
# decided in docs/decisions/019-signing-key.md, and leaves the three
# things that key produces beside it.
#
# This is run once, when a repository is first set up, and not again:
# there is one key, the job that publishes signs with it, and nobody
# signs by hand. Contributing to this project needs no key at all. What
# runs it a second time is a fork, setting up a repository of its own.
#
# The current directory becomes the keyring, so run it somewhere empty.
# The fingerprint is the only thing written to standard output.

set -euo pipefail

readonly KEY_NAME="OpinionatedArch Package Signing"
readonly SUBKEY_LIFE="3y"

# Armoured, so that what is committed is text, but named `.gpg`: makepkg reads
# a source ending in `.asc` as a detached signature for another source.
readonly PUBLIC_KEY="oparch.gpg"
readonly CI_SUBKEY="ci-signing-subkey.asc"
readonly BACKUP="oparch-signing-backup.tgz"

say() { printf '%s\n' "$*" >&2; }

# Everything the script says goes to standard error, so that the
# fingerprint on standard output can be redirected on its own.
say "The current directory will hold the keyring: $PWD"

export GNUPGHOME="$PWD"
chmod 700 "$GNUPGHOME"

staging=""
workbench=""
check=""

# gpg starts an agent for each keyring it is pointed at, and that agent
# outlives the command that started it. One left running on a directory
# that is afterwards emptied answers the next run with `agent_genkey
# failed: No such file or directory`, because it is still holding a
# keyring that is no longer there. So every agent this script starts is
# stopped again, and one left over from an earlier run is stopped before
# this one begins.
stop_agent() {
    gpgconf --homedir "$1" --kill gpg-agent >/dev/null 2>&1 || true
}

cleanup() {
    local home
    for home in "$workbench" "$check"; do
        if [[ -n "$home" ]]; then
            stop_agent "$home"
            rm -rf "$home"
        fi
    done
    if [[ -n "$staging" ]]; then
        rm -rf "$staging"
    fi
    stop_agent "$GNUPGHOME"
    return 0
}
trap cleanup EXIT

stop_agent "$GNUPGHOME"

# The address is where someone writes about this key — a bad signature, a
# suspected compromise. It belongs to the repository rather than to
# whoever is standing here, because the key outlives that.
read -r -p "Contact address for this key: " email
key_uid="$KEY_NAME <$email>"

# Asked once. It protects the primary key and the copy of the subkey that
# stays in this keyring; the copy that goes to continuous integration is
# the one that ends up without it.
read -r -s -p "Passphrase for the primary key: " passphrase
printf '\n' >&2
read -r -s -p "Again: " passphrase_again
printf '\n' >&2

if [[ "$passphrase" != "$passphrase_again" ]]; then
    say "The two do not match."
    exit 1
fi
unset passphrase_again

# The primary certifies and revokes and signs nothing, and does not
# expire. Generating it also writes its revocation certificate under
# openpgp-revocs.d/, which is why none is generated here.
say "Creating the primary key."
gpg --quiet --batch --pinentry-mode loopback --passphrase-fd 3 \
    --quick-generate-key "$key_uid" ed25519 cert never 3<<<"$passphrase"

fingerprint="$(gpg --list-keys --with-colons | awk -F: '/^fpr:/ { print $10; exit }')"

say "Adding the signing subkey, good for $SUBKEY_LIFE."
gpg --quiet --batch --pinentry-mode loopback --passphrase-fd 3 \
    --quick-add-key "$fingerprint" ed25519 sign "$SUBKEY_LIFE" 3<<<"$passphrase"

# The public half, which is committed to this repository and packaged as
# oparch-keyring.
gpg --quiet --export --armor "$fingerprint" > "$PUBLIC_KEY"

# The copy for continuous integration carries the subkey alone: exporting
# the subkeys leaves a stub where the primary would be. Its passphrase is
# removed on a keyring of its own, because gpg changes the passphrase of
# every secret key of a certificate at once and doing it here would take
# the primary's with it.
say "Preparing the copy for continuous integration."
staging="$(mktemp -d)"
workbench="$(mktemp -d)"
check="$(mktemp -d)"
chmod 700 "$staging" "$workbench" "$check"

gpg --quiet --batch --pinentry-mode loopback --passphrase-fd 3 \
    --export-secret-subkeys --armor "$fingerprint" 3<<<"$passphrase" > "$staging/subkey.asc"

GNUPGHOME="$workbench" gpg --quiet --batch --pinentry-mode loopback --passphrase-fd 3 \
    --import "$staging/subkey.asc" 3<<<"$passphrase"

# The current passphrase, then an empty new one, then its confirmation.
# There is no non-interactive option for this: gpg has no --new-passphrase.
printf '%s\n\n\n' "$passphrase" |
    GNUPGHOME="$workbench" gpg --quiet --command-fd 0 --pinentry-mode loopback \
        --passwd "$fingerprint" 2>/dev/null || true

GNUPGHOME="$workbench" gpg --quiet --batch --pinentry-mode loopback \
    --export-secret-subkeys --armor "$fingerprint" > "$CI_SUBKEY"
chmod 600 "$CI_SUBKEY"

# It has to sign with nobody answering anything, because that is the whole
# of what it is for.
say "Checking that it signs unattended."
printf 'check\n' > "$check/subject"
GNUPGHOME="$check" gpg --quiet --batch --import "$CI_SUBKEY"
GNUPGHOME="$check" gpg --quiet --batch --pinentry-mode loopback \
    --detach-sign --output "$check/subject.sig" "$check/subject"

if [[ ! -s "$check/subject.sig" ]]; then
    say "It did not sign. The copy for continuous integration is still protected."
    exit 1
fi

# What goes to removable media: the primary, the subkey as this keyring
# holds it, and the revocation certificate. Keeping the subkey is what
# keeps a rotation possible if the secret it was copied into is lost,
# because a secret cannot be read back out of continuous integration.
say "Packing what has to be kept."
backup_entries=()
for entry in private-keys-v1.d openpgp-revocs.d pubring.kbx trustdb.gpg; do
    if [[ -e "$entry" ]]; then
        backup_entries+=("$entry")
    fi
done
tar czf "$BACKUP" "${backup_entries[@]}"
chmod 600 "$BACKUP"

say ""
say "Keep on removable media, away from any network:  $BACKUP"
say "Commit once, when the repository is set up:      $PUBLIC_KEY"
say "Paste raw into the signing secret:               $CI_SUBKEY"
say ""
say "The fingerprint follows on standard output. It goes in the install"
say "script and in the keyring package's scriptlet."

printf '%s\n' "$fingerprint"
