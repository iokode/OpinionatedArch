#!/bin/sh
#
# What goes on PATH. The installer's host loads the BAML runtime as a shared
# library rather than carrying it, so it has to be told where the copy on this
# system is; and BAML_LIBRARY_DISABLE_DOWNLOAD turns a library that is not
# there into a failure of the run rather than a silent fetch, which is what
# lets an installation be made with no network at all.
#
# The assets are named here because the tool's own default is a directory
# beside the binary, and the binary is not where the project keeps its assets.
# An --assets given on the command line is left to win.

set -eu

readonly OPARCH_LIB=/usr/lib/oparch
readonly OPARCH_ASSETS=/usr/share/opinionatedarch/assets

BAML_LIBRARY_PATH="${OPARCH_LIB}/libbaml_cffi-x86_64-unknown-linux-gnu.so"
BAML_LIBRARY_DISABLE_DOWNLOAD=1
export BAML_LIBRARY_PATH BAML_LIBRARY_DISABLE_DOWNLOAD

for argument in "$@"; do
    if [ "$argument" = "--assets" ]; then
        exec "${OPARCH_LIB}/oparch-installer" "$@"
    fi
done

exec "${OPARCH_LIB}/oparch-installer" --assets "${OPARCH_ASSETS}" "$@"
