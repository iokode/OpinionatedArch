#!/usr/bin/env bash
#
# What the phase leaves behind, in the order it produces it: the values it
# composed, the theme it installed, the images the renderer drew into that
# theme, and the theme being the one the machine boots with.
#
# The images are what says the drawing happened. Everything before them can
# succeed with ImageMagick missing or unable to draw text; a file with pixels
# in it cannot.

case_assert() {
    harness_check "the values the message is made of are on the machine" \
        "grep -q 'OpinionatedArch End to End' /mnt/etc/opinionatedarch/return-message.yaml"

    harness_check "the theme is installed" \
        "test -f /mnt/usr/share/plymouth/themes/opinionatedarch/opinionatedarch.plymouth"

    harness_check "the renderer drew the message into it" \
        "test -n \"\$(find /mnt/usr/share/plymouth/themes/opinionatedarch -name '*.png' -size +1k)\""

    harness_check "it is the theme the machine boots with" \
        "grep -q '^Theme=opinionatedarch' /mnt/etc/plymouth/plymouthd.conf"
}
