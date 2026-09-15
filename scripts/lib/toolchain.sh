#!/usr/bin/env bash
#
# Building the tools of a working tree on the machine it is checked out on.
# archiso/debug/build.sh builds the tools the debug image carries with it, and
# scripts/vm.sh builds the packages it puts on the machine it installs.
#
# Whoever sources it sets ROOT to the working tree.

# A build that allocates without bound takes a machine with no swap down before
# anything can stop it, so each one is held to a ceiling where the user's
# systemd is there to hold it.
capped() {
    if systemd-run --user --scope -q -p MemoryMax=8G -p MemorySwapMax=0 true 2>/dev/null; then
        systemd-run --user --scope -q -p MemoryMax=8G -p MemorySwapMax=0 "$@"
    else
        "$@"
    fi
}

# The path of the runtime library a tool's host loads, for the toolchain the
# hosts are built against. It is fetched the way the setup-baml action fetches
# it, and kept where a host itself would keep it.
baml_runtime_library() {
    local target=x86_64-unknown-linux-gnu
    local toolchain library manifest url sha

    toolchain="$(awk '
        /^name = "baml_bridge"$/ { found = 1; next }
        found && /^version = / { gsub(/[",]/, "", $3); print $3; exit }
    ' "$ROOT/tools/installer/interactive/host/Cargo.lock")"
    library="$HOME/.cache/baml/libs/$toolchain/libbaml_cffi-$target.so"
    if [ ! -f "$library" ]; then
        manifest="$HOME/.baml/manifest-cache/prod/version/$toolchain.json"
        if [ ! -f "$manifest" ]; then
            printf "==> There is no manifest for BAML %s. 'baml toolchain use %s' leaves one.\n" \
                "$toolchain" "$toolchain" >&2
            return 1
        fi
        printf '==> Fetching the BAML runtime library for %s\n' "$toolchain" >&2
        url="$(jq -er --arg t "$target" '.cffi[$t].url' "$manifest")"
        sha="$(jq -er --arg t "$target" '.cffi[$t].sha256' "$manifest")"
        mkdir -p "$(dirname "$library")"
        curl -fsSL -o "$library.part" "$url"
        printf '%s  %s\n' "$sha" "$library.part" | sha256sum -c --quiet -
        mv "$library.part" "$library"
    fi
    printf '%s\n' "$library"
}
