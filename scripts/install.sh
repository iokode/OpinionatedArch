#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPARCH_REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=lib/log.sh
source "${SCRIPT_DIR}/lib/log.sh"
# shellcheck source=lib/validate.sh
source "${SCRIPT_DIR}/lib/validate.sh"
# shellcheck source=lib/input.sh
source "${SCRIPT_DIR}/lib/input.sh"
# shellcheck source=lib/exec.sh
source "${SCRIPT_DIR}/lib/exec.sh"

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

  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      -verbose)
        [[ "$#" -ge 2 ]] || die "Missing value for -verbose (expected 1 or 2)"
        case "$2" in
          1|2)
            OPARCH_VERBOSE="$2"
            ;;
          *)
            die "Invalid -verbose value: $2 (expected 1 or 2)"
            ;;
        esac
        shift 2
        ;;
      -file)
        [[ "$#" -ge 2 ]] || die "Missing value for -file"
        OPARCH_CONFIG_FILE="$2"
        shift 2
        ;;
      *)
        die "Unknown argument: $1"
        ;;
    esac
  done

  export OPARCH_VERBOSE
  export OPARCH_CONFIG_FILE
  export OPARCH_REPO_ROOT
}

main() {
  parse_args "$@"

  run_phase_live
  run_phase_chroot

  log "Installation completed."
  log "Review /mnt and reboot when ready."
}

main "$@"
