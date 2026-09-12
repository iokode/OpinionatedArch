#!/usr/bin/env bash
#
# The installation a person with a cable performs, which is the ordinary one
# and the one no other case reaches. Everything about where packages come from
# is different here: the official repositories decide the versions, this
# project's repository is above them, and the copies the medium carries are a
# cache rather than a source.
#
# It is the one case that is not hermetic. What it installs is whatever Arch
# was serving at the moment it ran, which is the condition it exists to test.

readonly CASE_TITLE="A machine is installed with a network."
readonly CASE_OUTCOME=installs
readonly CASE_NETWORK=present
