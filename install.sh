#!/bin/sh
#
# Installs OpinionatedArch from an Arch live environment, as decided in
# docs/decisions/017-installation-script.md. It trusts the project's signing
# key, adds the package repository, installs the installer from it, and starts
# it.
#
# It lives at the top level because it is fetched by its address and run, so
# its path is part of how it is published rather than a place to file it.
#
# The fingerprint below is the one the signing key's *primary* carries, which
# is what `pacman-key --lsign-key` signs; trust reaches the subkey that does
# the signing through the binding the primary made for it. It survives a
# rotation of that subkey, and changes only if the primary ever does.

set -eu

readonly FINGERPRINT="DB29EF45D80039FB8A9A1CA51E2FAAF03FFCBE59"

readonly KEY_URL="https://raw.githubusercontent.com/iokode/OpinionatedArch/master/packages/oparch-keyring/oparch.gpg"
readonly REPOSITORY="https://packages.oparch.iokode.dev"

key="$(mktemp)"
curl -fsSL "$KEY_URL" -o "$key"

# What was fetched has to be the key this script was written for. A key that is
# not that one is either a mistake or a substitution, and there is nothing to
# ask about either.
fetched="$(gpg --with-colons --import-options show-only --import < "$key" \
    | awk -F: '/^fpr:/ { print $10; exit }')"

if [ "$fetched" != "$FINGERPRINT" ]; then
    echo "The key served is not the one this script trusts." >&2
    echo "  expected: $FINGERPRINT" >&2
    echo "  served:   ${fetched:-nothing}" >&2
    rm -f "$key"
    exit 1
fi

# Adding the key leaves it known and untrusted; signing it locally is what
# makes pacman accept what it signed.
pacman-key --add "$key"
pacman-key --lsign-key "$FINGERPRINT"
rm -f "$key"

# The repository, with signatures required of it. It goes at the end of the
# file because order only decides which repository wins a name that two of them
# serve, and nothing here is served twice. Where this repository has to sit
# above the official ones is the installed system, and that is the installer's
# doing rather than this script's.
printf '\n[oparch]\nSigLevel = Required TrustedOnly\nServer = %s\n' \
    "$REPOSITORY" >> /etc/pacman.conf

# One package: the renderer, the dotfiles tool, the BAML runtime and everything
# else the installer calls arrive as its declared dependencies.
pacman -Sy --noconfirm oparch-installer

exec oparch-installer
