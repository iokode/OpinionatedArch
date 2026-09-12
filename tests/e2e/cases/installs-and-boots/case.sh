#!/usr/bin/env bash
#
# The case that answers the question end-to-end testing exists for: does an
# image this project publishes install a machine that boots?
#
# It is the smallest installation there is — no dotfiles package, no return
# message, no network — because everything it leaves out is something else's
# case, and what is left is the image, the installer and the disk.

readonly CASE_TITLE="A machine is installed and boots."
readonly CASE_OUTCOME=installs
