#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPARCH_REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=../lib/log.sh
source "${OPARCH_REPO_ROOT}/lib/log.sh"
# shellcheck source=../lib/validate.sh
source "${OPARCH_REPO_ROOT}/lib/validate.sh"
# shellcheck source=../lib/input.sh
source "${OPARCH_REPO_ROOT}/lib/input.sh"
# shellcheck source=../lib/exec.sh
source "${OPARCH_REPO_ROOT}/lib/exec.sh"

# shellcheck source=phase-live/input.sh
source "${SCRIPT_DIR}/phase-live/input.sh"
# shellcheck source=phase-live/disk.sh
source "${SCRIPT_DIR}/phase-live/disk.sh"
# shellcheck source=phase-live/bootstrap.sh
source "${SCRIPT_DIR}/phase-live/bootstrap.sh"
# shellcheck source=phase-live/main.sh
source "${SCRIPT_DIR}/phase-live/main.sh"

# shellcheck source=phase-chroot/main.sh
source "${SCRIPT_DIR}/phase-chroot/main.sh"

parse_args() {
  OPARCH_VERBOSE="${OPARCH_VERBOSE:-0}"
  OPARCH_CONFIG_FILE="${OPARCH_CONFIG_FILE:-}"
  OPARCH_WIPE_ALL="${OPARCH_WIPE_ALL:-no}"

  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --verbose|-v)
        [[ "$#" -ge 2 ]] || die "Missing value for --verbose/-v (expected 1 or 2)"
        case "$2" in
          1|2)
            OPARCH_VERBOSE="$2"
            ;;
          *)
            die "Invalid --verbose/-v value: $2 (expected 1 or 2)"
            ;;
        esac
        shift 2
        ;;
      --file|-f)
        [[ "$#" -ge 2 ]] || die "Missing value for --file/-f"
        OPARCH_CONFIG_FILE="$2"
        shift 2
        ;;
      --wipe-all|-w)
        OPARCH_WIPE_ALL="yes"
        shift
        ;;
      *)
        die "Unknown argument: $1"
        ;;
    esac
  done

  export OPARCH_VERBOSE
  export OPARCH_CONFIG_FILE
  export OPARCH_WIPE_ALL
  export OPARCH_REPO_ROOT
}

main() {
  parse_args "$@"

  run_phase_live
  run_phase_chroot

  log "Installation completed. Review /mnt and reboot when ready."
}

main "$@"
