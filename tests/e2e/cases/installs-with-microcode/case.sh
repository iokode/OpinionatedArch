#!/usr/bin/env bash
#
# Microcode is loaded by the bootloader before the kernel, from a file on the
# EFI system partition, named by the menu entry the installation generated for
# this machine. What the unit suites pin is which file is moved where; what
# only a machine shows is that the file ends up where the menu looks for it.

readonly CASE_TITLE="A machine is installed with microcode."
readonly CASE_OUTCOME=installs
