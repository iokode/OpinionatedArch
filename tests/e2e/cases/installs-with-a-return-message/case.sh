#!/usr/bin/env bash
#
# The phase with the most outside it: it writes the values the message is made
# of, installs the Plymouth theme, and runs the renderer, which draws with
# ImageMagick through Pango and needs fonts to do it. Nothing else an
# installation does depends on that much it did not write itself, and what
# broke there before was the medium's ImageMagick against the mirrors' glibc.
#
# The message cannot be seen from here — the guest has no display, so Plymouth
# falls back to the text prompt — so what is checked is that it was made.

readonly CASE_TITLE="A machine is installed with a return message."
readonly CASE_OUTCOME=installs
