#!/usr/bin/env bash
#
# What this case claims is that nothing happened, and the harness claims it for
# every `refuses` case: the installer said no, and the disk the guest does have
# is as it was. There is nothing about this refusal in particular to add.

case_assert() {
    return 0
}
