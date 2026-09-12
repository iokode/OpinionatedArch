#!/usr/bin/env bash
#
# Runs the end-to-end cases against an installation image, as specified in
# docs/development/006-end-to-end-testing.md.
#
# Takes the image by path, because which image is being tested is the whole
# point of the test: an image is an input to this and never something it goes
# and fetches. After it, the cases to run; without any, every case there is.
#
#     tests/e2e/run.sh out/oparch-2026.09.12.1530-x86_64.iso
#     tests/e2e/run.sh out/oparch.iso installs-and-boots
#
# It exits non-zero when any case failed.

set -euo pipefail

readonly HERE="$(cd "$(dirname "$0")" && pwd)"
readonly CASES="$HERE/cases"

. "$HERE/harness.sh"

usage() {
    printf 'Usage: %s [--transcripts <directory>] <image.iso> [case ...]\n' "$0" >&2
}

# Where the guests' consoles are written, which is where a failed case is read
# from. A run that is not told picks a directory of its own and says which,
# because a person is there to go and look. A run on a machine that will stop
# existing when it ends is told, so that what it leaves can be collected before
# it goes.
transcripts=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --transcripts)
            transcripts="${2:-}"
            if [ -z "$transcripts" ]; then
                usage
                exit 2
            fi
            shift 2
            ;;
        *)
            break
            ;;
    esac
done

image="${1:-}"
if [ -z "$image" ]; then
    usage
    exit 2
fi
shift

if [ ! -f "$image" ]; then
    printf 'There is no image at %s\n' "$image" >&2
    exit 2
fi

# The guest is started from a directory of the harness's choosing, so the image
# is named absolutely from here on.
image="$(cd "$(dirname "$image")" && pwd)/$(basename "$image")"

selected=("$@")
if [ "${#selected[@]}" -eq 0 ]; then
    for directory in "$CASES"/*/; do
        selected+=("$(basename "$directory")")
    done
fi

# A name that is not a case is a mistake in the command, and it is answered
# before anything boots rather than after the cases before it have run. A case
# is four files and a directory, and one that is missing any of them is not
# half a case: it is a case that cannot be run.
for name in "${selected[@]}"; do
    if [ ! -d "$CASES/$name" ]; then
        printf 'There is no case named %s in %s\n' "$name" "$CASES" >&2
        exit 2
    fi
    for part in case.sh drive.sh assert.sh share; do
        if [ ! -e "$CASES/$name/$part" ]; then
            printf 'The case %s has no %s\n' "$name" "$part" >&2
            exit 2
        fi
    done
done

if [ -n "$transcripts" ]; then
    mkdir -p "$transcripts"
    work="$(cd "$transcripts" && pwd)"
else
    work="$(mktemp -d --tmpdir oparch-e2e-XXXXXXXX)"
fi

printf 'Image: %s\n' "$image" >&2
printf 'Transcripts: %s\n\n' "$work" >&2

passed=()
failed=()

for name in "${selected[@]}"; do
    # The title is read from the case rather than from the directory's name,
    # because the sentence naming a case is what the case declares.
    title="$( . "$CASES/$name/case.sh"; printf '%s' "$CASE_TITLE" )"
    printf '==> %s: %s\n' "$name" "$title" >&2

    # Each case runs in a subshell, so what one declares is gone before the
    # next one declares its own. `set -e` is suppressed for everything a
    # command whose status is captured this way does, which is why the harness
    # checks every step of a case itself and answers with a status.
    status=0
    ( harness_run_case "$CASES/$name" "$work/$name" "$image" ) || status=$?

    if [ "$status" -eq 0 ]; then
        passed+=("$name")
    else
        failed+=("$name")
    fi
done

printf '\n'
for name in "${passed[@]}"; do
    printf 'passed  %s\n' "$name"
done
for name in "${failed[@]}"; do
    printf 'FAILED  %s\n' "$name"
done
printf '\n%d passed, %d failed. Transcripts are in %s\n' \
    "${#passed[@]}" "${#failed[@]}" "$work"

if [ "${#failed[@]}" -gt 0 ]; then
    exit 1
fi
