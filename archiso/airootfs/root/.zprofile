# Starts the installer, which is the only thing this medium is for.
#
# On the first console only. Every other one gives a shell, which is what makes
# the installer reachable as a command as well as being the thing that starts:
# it can be left, and getting back into it is typing its name.
#
# `.zprofile` rather than `.zlogin`, because `releng` owns that one and runs its
# own script from it. This runs first and leaves that alone.

if [[ "$(tty)" == /dev/tty1 ]]; then
    oparch-installer
fi
