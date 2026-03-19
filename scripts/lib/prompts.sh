#!/usr/bin/env bash

# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

declare TARGET_DISK=""
declare MACHINE_ROLE=""
declare CPU_VENDOR=""
declare ZRAM_SWAP_GB=""
declare SWAP_PARTITION_GB=""
declare -ag LOGIN_USERS=()
declare SHARED_SECRET=""
declare CONSOLE_KEYMAP=""
declare TIMEZONE=""
declare HOSTNAME_VALUE=""
declare OWNER_NAME=""
declare OWNER_PHONE=""
declare OWNER_EMAIL=""
declare OWNER_RETURN_ADDRESS=""
declare INCLUDE_LOGO="no"
declare LOGO_URL=""
declare LOGO_LOCAL_PATH="/tmp/oparch-logo.png"

authenticated_logo_download() {
  local url="$1"

  rm -f "${LOGO_LOCAL_PATH}"
  if curl -fL --retry 2 --connect-timeout 10 -o "${LOGO_LOCAL_PATH}" "${url}"; then
    return 0
  fi
  return 1
}

collect_login_users() {
  local raw_users=""
  local -a parsed=()
  local token=""
  local clean=""

  while true; do
    raw_users="$(ask_non_empty "Login usernames (comma-separated): ")"
    IFS=',' read -r -a parsed <<< "${raw_users}"

    LOGIN_USERS=()
    for token in "${parsed[@]}"; do
      clean="$(trim "${token}")"
      [[ -z "${clean}" ]] && continue

      if ! validate_username "${clean}"; then
        warn "Invalid username: ${clean}"
        LOGIN_USERS=()
        break
      fi

      if [[ " ${LOGIN_USERS[*]} " != *" ${clean} "* ]]; then
        LOGIN_USERS+=("${clean}")
      fi
    done

    if [[ "${#LOGIN_USERS[@]}" -eq 0 ]]; then
      warn "At least one valid login username is required."
      continue
    fi

    return 0
  done
}

collect_install_inputs() {
  log "Detected disks:"
  lsblk -dpno NAME,SIZE,MODEL | sed 's/^/  - /'

  while true; do
    TARGET_DISK="$(ask_non_empty "Target disk (example: /dev/nvme0n1): ")"
    if [[ -b "${TARGET_DISK}" ]]; then
      break
    fi
    warn "${TARGET_DISK} is not a block device."
  done

  local destructive_confirmation
  destructive_confirmation="$(ask_non_empty "Type 'wipe-all' to confirm destructive install: ")"
  [[ "${destructive_confirmation}" == "wipe-all" ]] || die "Aborted. Confirmation value must be 'wipe-all'."

  MACHINE_ROLE="$(ask_choice "Machine role (Laptop/MainPC): " "Laptop" "MainPC")"
  CPU_VENDOR="$(ask_choice "CPU vendor (Intel/AMD): " "Intel" "AMD")"

  ZRAM_SWAP_GB="$(ask_uint "zram size in GB: ")"
  SWAP_PARTITION_GB="$(ask_uint "Swap partition size in GB: ")"

  collect_login_users

  SHARED_SECRET="$(read_secret_with_confirmation "Shared secret (LUKS + login users): ")"

  CONSOLE_KEYMAP="$(ask_non_empty "Console keymap (example: us, es): ")"

  while true; do
    TIMEZONE="$(ask_non_empty "Timezone (example: Europe/Madrid): ")"
    if [[ -e "/usr/share/zoneinfo/${TIMEZONE}" ]]; then
      break
    fi
    warn "Timezone not found in /usr/share/zoneinfo/${TIMEZONE}"
  done

  while true; do
    HOSTNAME_VALUE="$(ask_non_empty "Hostname: ")"
    if validate_hostname "${HOSTNAME_VALUE}"; then
      break
    fi
    warn "Invalid hostname format."
  done

  OWNER_NAME="$(ask_non_empty "Owner name for pre-boot message: ")"
  OWNER_PHONE="$(ask_non_empty "Owner phone for pre-boot message: ")"
  OWNER_EMAIL="$(ask_non_empty "Owner email for pre-boot message: ")"
  OWNER_RETURN_ADDRESS="$(ask_non_empty "Owner return address for pre-boot message: ")"

  INCLUDE_LOGO="$(ask_yes_no "Include company logo in pre-boot message?")"
  if [[ "${INCLUDE_LOGO}" == "yes" ]]; then
    while true; do
      LOGO_URL="$(ask_non_empty "Logo URL: ")"
      if authenticated_logo_download "${LOGO_URL}"; then
        log "Logo downloaded to ${LOGO_LOCAL_PATH}."
        break
      fi

      warn "Logo download failed."
      local failed_action
      failed_action="$(ask_choice "Type retry or continue-without-logo: " "retry" "continue-without-logo")"
      if [[ "${failed_action}" == "continue-without-logo" ]]; then
        INCLUDE_LOGO="no"
        LOGO_URL=""
        rm -f "${LOGO_LOCAL_PATH}"
        break
      fi
    done
  fi
}

summarize_install_plan() {
  local login_user_csv
  login_user_csv="$(join_by ', ' "${LOGIN_USERS[@]}")"

  log "Installation summary"
  printf '  target disk: %s\n' "${TARGET_DISK}"
  printf '  machine role: %s\n' "${MACHINE_ROLE}"
  printf '  cpu vendor: %s\n' "${CPU_VENDOR}"
  printf '  zram size (GB): %s\n' "${ZRAM_SWAP_GB}"
  printf '  swap partition size (GB): %s\n' "${SWAP_PARTITION_GB}"
  printf '  login users: %s\n' "${login_user_csv}"
  printf '  keymap: %s\n' "${CONSOLE_KEYMAP}"
  printf '  timezone: %s\n' "${TIMEZONE}"
  printf '  hostname: %s\n' "${HOSTNAME_VALUE}"
  printf '  include logo: %s\n' "${INCLUDE_LOGO}"

  local proceed
  proceed="$(ask_yes_no "Proceed with installation?")"
  [[ "${proceed}" == "yes" ]] || die "Aborted by user."
}
