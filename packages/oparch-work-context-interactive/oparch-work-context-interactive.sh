#!/bin/sh
#
# What goes on PATH. The host loads the BAML runtime as a shared library rather
# than carrying it, so it has to be told where the copy on this system is; and
# BAML_LIBRARY_DISABLE_DOWNLOAD turns a library that is not there into a failure
# of the run rather than a silent fetch.

set -eu

readonly OPARCH_LIB=/usr/lib/oparch

BAML_LIBRARY_PATH="${OPARCH_LIB}/libbaml_cffi-x86_64-unknown-linux-gnu.so"
BAML_LIBRARY_DISABLE_DOWNLOAD=1
export BAML_LIBRARY_PATH BAML_LIBRARY_DISABLE_DOWNLOAD

exec "${OPARCH_LIB}/oparch-work-context-interactive" "$@"
