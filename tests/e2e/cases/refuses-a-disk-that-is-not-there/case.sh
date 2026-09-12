#!/usr/bin/env bash
#
# The earliest gate there is: a file is checked against the machine it will run
# on before a single value has been acted on, and a disk that is not there is
# the plainest thing that check can find. What this holds is that the run stops
# with the disk as it was.
#
# It costs seconds. Nothing is installed, nothing is downloaded, and no machine
# is booted afterwards, because there is no machine.

readonly CASE_TITLE="A configuration naming a disk that is not there is refused."
readonly CASE_OUTCOME=refuses
