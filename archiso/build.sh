#!/usr/bin/env bash
#
# Builds the installation image.
#
# It does not hold a profile of its own. `releng` is archiso's, it moves with
# archiso, and copying it here would be maintaining a fork of a bootloader
# configuration nobody in this project wrote. So the profile is assembled: a
# copy of `releng` as it is on the day, with this project's differences applied
# over it. What lives in this directory is only the difference.
#
# Run as root, which mkarchiso requires. Takes the directory to leave the image
# in; everything else it works out.

set -eu

readonly RELENG=/usr/share/archiso/configs/releng
readonly HERE="$(cd "$(dirname "$0")" && pwd)"
readonly REPOSITORY_NAME=oparch
readonly REPOSITORY="https://packages.oparch.iokode.dev"

# What the medium's own repository is called, and where it sits on the finished
# system. Its own name and not the published one, because they are different
# repositories with different contents and different precedence: what the
# medium carries is the last place to look, and what the project publishes is
# the first.
readonly MEDIUM_REPO=oparch-medium
readonly MEDIUM_REPO_DIR=/usr/share/oparch/repo

# The pacman configuration an installation without a network is run with, which
# the installer names by this path. It holds the medium's repository and no
# other, so a run given it synchronises nothing and reaches for nothing.
readonly MEDIUM_CONF=/usr/share/oparch/medium.conf

# The stanza that names the repository the medium carries. Both files that
# mention it are written from here, so they cannot come to disagree about where
# it is or what is asked of what it holds.
#
# Signatures are not checked here, and the reason is that checking them would
# not be a check. The packages, the key that would validate them and the file
# that says to validate them all travel in this image: whoever can alter one
# can alter the rest, so the image would be vouching for itself. The check that
# means something was made when this repository was filled, against the keyring
# of whoever published each package; and what says this image is the one the
# project published is the checksum published beside it, which comes from
# somewhere else.
medium_repository() {
    printf '\n[%s]\nSigLevel = Never\nServer = file://%s\n' \
        "$MEDIUM_REPO" "$MEDIUM_REPO_DIR"
}

output="${1:?the directory to leave the image in}"
work="$(mktemp -d)"
profile="$work/profile"
trap 'rm -rf "$work"' EXIT

say() { printf '==> %s\n' "$*" >&2; }

say "Taking the profile from $RELENG"
cp -r "$RELENG" "$profile"

# ------------------------------------------------------ what the medium holds

# The image is this project's and says so: its file name, the label the
# bootloader finds it by, and what a system that mounts it calls it. Dated
# rather than numbered, because what distinguishes one from the next is when it
# was built and not anything decided about it.
#
# Down to the minute rather than to the day, because more than one image is
# built on some days and two of them sharing a name is the second silently
# replacing the first. Nothing has to be counted or looked up for it, and it
# keeps the property everything downstream rests on: what sorts last was built
# last, at a width that never changes.
say "Naming the image"
{
    printf '\niso_name="oparch"\n'
    printf 'iso_label="OPARCH_%s"\n' "$(date +%Y%m)"
    printf 'iso_version="%s"\n' "$(date +%Y.%m.%d.%H%M)"
    printf 'iso_publisher="OpinionatedArch <https://oparch.iokode.dev>"\n'
    printf 'iso_application="OpinionatedArch installation medium"\n'
} >> "$profile/profiledef.sh"

say "Applying this project's package list"
lines() { grep -v '^\s*#' "$1" | grep -v '^\s*$'; }

remove="$(lines "$HERE/packages.remove")"
grep -vxF "$remove" "$profile/packages.x86_64" > "$profile/packages.x86_64.kept"
mv "$profile/packages.x86_64.kept" "$profile/packages.x86_64"
lines "$HERE/packages.add" >> "$profile/packages.x86_64"

# ------------------------------------------------- trusting the project's key
#
# The airootfs is built by pacman running on this machine, so it is this
# machine's keyring that decides whether the project's own packages are
# installable. The key comes from the repository rather than from the network,
# which is the arrangement Package Repository asks for: what says which key to
# trust is not the server the packages come from.

say "Trusting the project's signing key"
fingerprint="$(gpg --with-colons --import-options show-only --import \
    < "$HERE/../packages/oparch-keyring/oparch.gpg" |
    awk -F: '/^fpr:/ { print $10; exit }')"
pacman-key --add "$HERE/../packages/oparch-keyring/oparch.gpg"
pacman-key --lsign-key "$fingerprint"

# The published repository, above the official ones, so that the medium is
# built out of the same packages an installed system would update to.
cat >> "$profile/pacman.conf" <<EOF

[$REPOSITORY_NAME]
SigLevel = Required TrustedOnly
Server = $REPOSITORY
EOF

# ------------------------------------------- the repository the medium carries

say "Filling the medium's own repository"
carried="$profile/airootfs$MEDIUM_REPO_DIR"

# Both of these are paths handed to something else, and handing a path over
# does not bring it into being: pacman refuses a `--dbpath` that is not there,
# and neither of them is anybody's to create but this script's.
mkdir -p "$carried" "$work/db" "$work/build"

# Downloaded and not installed: what is wanted is the package files, so that an
# installation with nothing to fetch from has something to install.
pacman --config "$profile/pacman.conf" --dbpath "$work/db" \
    --cachedir "$carried" -Syw --noconfirm $(lines "$HERE/bootstrap.packages")

repo-add "$carried/$MEDIUM_REPO.db.tar.gz" "$carried"/*.pkg.tar.zst

# --------------------------------------------------- what the live system sees
#
# Generated from the profile's own configuration rather than written out again,
# so that the repositories the medium was built from and the ones it installs
# from cannot come to disagree. The medium's own goes last: it is what answers
# when nothing else can, and never what wins while something else can.

say "Writing the live system's pacman.conf"
mkdir -p "$profile/airootfs/etc"
{
    cat "$profile/pacman.conf"
    medium_repository
} > "$profile/airootfs/etc/pacman.conf"

# And the one an installation without a network is run with: the same options
# the medium was built under, and the medium's repository as the only one there
# is. Everything from the top of the file down to the first repository is what
# `[options]` is, so the section is taken rather than written out again and the
# two configurations cannot disagree about how packages are checked.
say "Writing the configuration an installation without a network uses"
{
    awk '/^\[/ && $0 != "[options]" { exit } { print }' "$profile/pacman.conf"
    medium_repository
} > "$profile/airootfs$MEDIUM_CONF"

say "Applying this project's overlay"
cp -r "$HERE/airootfs/." "$profile/airootfs/"

# ------------------------------------------------------------------- the image

say "Building"
set -o pipefail
mkarchiso -v -w "$work/build" -o "$output" "$profile" 2>&1 | tee "$work/build.log"

# A package's install scriptlet is what puts that package's own arrangements in
# place — the project's key where the medium will look for it, for one. pacman
# does not fail a transaction when one of them fails: it says so and carries
# on, and mkarchiso then finishes and exits zero, so an image missing what a
# scriptlet was there to do is published with nothing having gone wrong. The
# line pacman prints is the only thing it offers about it, so that is what is
# read for.
#
# Only for this project's own packages. Upstream scriptlets fail here as a
# matter of course and always have: mkinitcpio ends every build of this image
# reporting errors, because it looks for firmware that nobody ships for modules
# nobody here uses, and a build stopped by that is a build that never finishes.
# What this project ships is its own business and is held to working.
# A scriptlet's failure is reported after the line naming the package being
# installed, so what is being installed is tracked and the report attributed to
# it. pacman announces each phase of its work with a line of its own, and the
# hooks that run after the packages are in are not any package's doing — one of
# them is that mkinitcpio — so a phase line ends the attribution rather than
# leaving whatever was installed last to answer for the rest of the build.
failed="$(awk '
    /^:: / { package = ""; next }
    /^(installing|upgrading) oparch-/ { package = $2; sub(/\.\.\.$/, "", package); next }
    /^(installing|upgrading) / { package = ""; next }
    /command failed to execute correctly/ { if (package != "") print package }
' "$work/build.log")"

if [ -n "$failed" ]; then
    say "The install scriptlet of $failed failed. The image is not to be published."
    exit 1
fi
