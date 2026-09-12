#!/usr/bin/env bash
#
# The installation this case performs: the installer is handed the file in
# `share/` and asks nothing. It reports as plain timestamped lines, so the
# whole of the run is on the console the harness is reading.

readonly CASE_CONFIG="$SHARE_MOUNT/config.yaml"

# What unlocks the disk is in the file that was handed over, so it is read from
# there: the machine that comes out is answered with the value it was installed
# with, and not with a second copy of it written somewhere else.
readonly CASE_PASSPHRASE="$(harness_secret_in "$CASE_DIR/share/config.yaml")"

case_drive() {
    guest_run "oparch-installer --config $CASE_CONFIG" "$WAIT_INSTALL"
}
