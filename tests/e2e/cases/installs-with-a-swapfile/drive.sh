#!/usr/bin/env bash
#
# The installer is handed the file in `share/` and asks nothing.

readonly CASE_CONFIG="$SHARE_MOUNT/config.yaml"
readonly CASE_PASSPHRASE="$(harness_secret_in "$CASE_DIR/share/config.yaml")"

case_drive() {
    guest_run "oparch-installer --config $CASE_CONFIG" "$WAIT_INSTALL"
}
