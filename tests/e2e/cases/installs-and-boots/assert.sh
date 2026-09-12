#!/usr/bin/env bash
#
# This case asserts nothing of its own, and that is the point of it: what it
# holds an image to is the checks every `installs` case gets — the layout on
# the disk, and then the disk booted on its own, asked for its passphrase and
# reaching a login — and those live in the harness because they are true of
# every completed installation.

case_assert() {
    return 0
}
