#!/usr/bin/env bash
#
# Building the tools and the packages of a working tree on the machine it is
# checked out on. archiso/debug/build.sh builds every package the tree defines
# with it, into the repository the debug image carries.
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

# What a package packages, put beside the copy of its PKGBUILD in the directory
# given. A tool's package is named after the tool, oparch-<entity>-<action>, and
# the tool is tools/<entity>/<action>/: packed by `baml pack`, or built with its
# host when it has one. The installer's package carries the two installers, the
# assets and the runtime library are the packages that carry no tool, and every
# other file a PKGBUILD names is committed beside it.
stage() {
    local name="$1" directory="$2"
    local project library

    case "$name" in
        oparch-assets)
            tar czf "$directory/assets.tar.gz" -C "$ROOT" assets
            ;;
        oparch-baml-runtime)
            library="$(baml_runtime_library)"
            cp "$library" "$directory/"
            ;;
        oparch-installer)
            ( cd "$ROOT/tools/installer/unattended" && capped baml pack main --output ./oparch-installer )
            capped baml --directory "$ROOT/tools/installer/interactive" generate
            capped cargo build --release --manifest-path "$ROOT/tools/installer/interactive/host/Cargo.toml"
            cp "$ROOT/tools/installer/unattended/oparch-installer" \
                "$ROOT/tools/installer/interactive/host/target/release/oparch-installer-interactive" \
                "$directory/"
            ;;
    esac

    for project in "$ROOT"/tools/*/*/baml.toml; do
        project="$(dirname "$project")"
        [ "oparch-$(basename "$(dirname "$project")")-$(basename "$project")" = "$name" ] || continue
        if [ -d "$project/host" ]; then
            capped baml --directory "$project" generate
            capped cargo build --release --manifest-path "$project/host/Cargo.toml"
            cp "$project/host/target/release/$name" "$directory/"
        else
            ( cd "$project" && capped baml pack main --output "./$name" )
            cp "$project/$name" "$directory/"
        fi
    done
}

# A package of this tree, built the way the publish workflow builds it: what it
# packages is built from the tree and staged beside a copy of its PKGBUILD under
# the build directory given, and makepkg packages it into the destination given.
build_package() {
    local name="$1" build="$2" destination="$3"

    cp -r "$ROOT/packages/$name" "$build/$name"
    stage "$name" "$build/$name"
    PKGDEST="$destination" makepkg --dir "$build/$name" --nodeps --clean
}
