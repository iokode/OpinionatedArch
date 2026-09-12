#!/usr/bin/env bash
#
# A swap file on btrfs is not a file with `mkswap` run over it: the filesystem
# has to make it itself, without copy-on-write and without compression, or the
# kernel refuses to swap to it. The unit suites pin which command is decided
# on; whether the filesystem and the kernel accept what it made is only visible
# on a machine that ran it.

readonly CASE_TITLE="A machine is installed with a swap file."
readonly CASE_OUTCOME=installs
