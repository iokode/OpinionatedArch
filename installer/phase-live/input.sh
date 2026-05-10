#!/usr/bin/env bash

declare TARGET_DISK=""
declare STARTUP_POLICY=""
declare UCODE_PACKAGE=""
declare GPU_DRIVER=""
declare ZRAM_SWAP_GB=""
declare SWAP_PARTITION_GB=""
declare -ag LOGIN_USERS=()
declare SHARED_SECRET=""
declare CONSOLE_KEYMAP=""
declare TIMEZONE=""
declare HOSTNAME_VALUE=""
declare INCLUDE_RETURN_MESSAGE="no"
declare -ag RETURN_MESSAGE_LANGUAGES=()
declare OWNER_NAME=""
declare OWNER_PHONE=""
declare OWNER_EMAIL=""
declare OWNER_RETURN_ADDRESS=""
declare INCLUDE_LOGO="no"
declare LOGO_URL=""
declare OPARCH_TEMP_DIR="/tmp/oparch"
declare LOGO_LOCAL_PATH="/tmp/oparch/logo.png"
declare PROCEED_INSTALL="ask"

parse_login_users_csv() {
  local raw_users="$1"
  local -a parsed=()
  local token=""
  local clean=""

  IFS=',' read -r -a parsed <<< "${raw_users}"
  LOGIN_USERS=()

  for token in "${parsed[@]}"; do
    clean="$(trim "${token}")"
    [[ -z "${clean}" ]] && continue

    if ! validate_username "${clean}"; then
      warn "Invalid username: ${clean}"
      LOGIN_USERS=()
      return 1
    fi

    if [[ "${clean}" == "system" ]]; then
      warn "Username 'system' is reserved."
      LOGIN_USERS=()
      return 1
    fi

    if [[ " ${LOGIN_USERS[*]} " != *" ${clean} "* ]]; then
      LOGIN_USERS+=("${clean}")
    fi
  done

  if [[ "${#LOGIN_USERS[@]}" -eq 0 ]]; then
    warn "At least one valid login username is required."
    return 1
  fi

  return 0
}

parse_return_message_languages_csv() {
  local raw_languages="$1"
  local -a parsed=()
  local token=""
  local clean=""
  local template_path=""

  IFS=',' read -r -a parsed <<< "${raw_languages}"
  RETURN_MESSAGE_LANGUAGES=()

  for token in "${parsed[@]}"; do
    clean="$(trim "${token}")"
    [[ -z "${clean}" ]] && continue

    [[ "${clean}" =~ ^[a-z][a-z]$ ]] || die "Invalid return-message language code: ${clean}"
    template_path="${OPARCH_REPO_ROOT}/assets/returning-templates/${clean}.tpl"
    [[ -f "${template_path}" ]] || die "Return-message template not found: ${template_path}"

    if [[ " ${RETURN_MESSAGE_LANGUAGES[*]} " != *" ${clean} "* ]]; then
      RETURN_MESSAGE_LANGUAGES+=("${clean}")
    fi
  done

  if (( ${#RETURN_MESSAGE_LANGUAGES[@]} == 0 || ${#RETURN_MESSAGE_LANGUAGES[@]} > 4 )); then
    die "RETURN_MESSAGE_LANGUAGES_CSV must include between 1 and 4 languages."
  fi
}

authenticated_logo_download() {
  local url="$1"

  if run_cmd curl -fL --retry 2 --connect-timeout 10 -o "${LOGO_LOCAL_PATH}" "${url}"; then
    return 0
  fi
  return 1
}

prepare_live_temp_dir() {
  run_cmd mkdir -p "${OPARCH_TEMP_DIR}"
}

load_inputs_from_config_file() {
  local config_file="${OPARCH_CONFIG_FILE}"
  [[ -f "${config_file}" ]] || die "Config file not found: ${config_file}"

  local line=""
  local key=""
  local value=""

  while IFS= read -r line || [[ -n "${line}" ]]; do
    line="${line%$'\r'}"
    line="$(trim "${line}")"
    [[ -z "${line}" ]] && continue
    [[ "${line}" =~ ^# ]] && continue

    [[ "${line}" == *"="* ]] || die "Invalid config line (expected key=value): ${line}"

    key="$(trim "${line%%=*}")"
    value="$(trim "${line#*=}")"

    if [[ "${value}" =~ ^\".*\"$ || "${value}" =~ ^\'.*\'$ ]]; then
      value="${value:1:${#value}-2}"
    fi

    case "${key}" in
      TARGET_DISK) TARGET_DISK="${value}" ;;
      STARTUP_POLICY) STARTUP_POLICY="${value}" ;;
      UCODE_PACKAGE) UCODE_PACKAGE="${value}" ;;
      GPU_DRIVER) GPU_DRIVER="${value}" ;;
      ZRAM_SWAP_GB) ZRAM_SWAP_GB="${value}" ;;
      SWAP_PARTITION_GB) SWAP_PARTITION_GB="${value}" ;;
      LOGIN_USERS_CSV) LOGIN_USERS_CSV="${value}" ;;
      SHARED_SECRET) SHARED_SECRET="${value}" ;;
      CONSOLE_KEYMAP) CONSOLE_KEYMAP="${value}" ;;
      TIMEZONE) TIMEZONE="${value}" ;;
      HOSTNAME_VALUE) HOSTNAME_VALUE="${value}" ;;
      INCLUDE_RETURN_MESSAGE) INCLUDE_RETURN_MESSAGE="${value}" ;;
      RETURN_MESSAGE_LANGUAGES_CSV) RETURN_MESSAGE_LANGUAGES_CSV="${value}" ;;
      OWNER_NAME) OWNER_NAME="${value}" ;;
      OWNER_PHONE) OWNER_PHONE="${value}" ;;
      OWNER_EMAIL) OWNER_EMAIL="${value}" ;;
      OWNER_RETURN_ADDRESS) OWNER_RETURN_ADDRESS="${value}" ;;
      INCLUDE_LOGO) INCLUDE_LOGO="${value}" ;;
      LOGO_URL) LOGO_URL="${value}" ;;
      *) die "Unknown key in config file: ${key}" ;;
    esac
  done < "${config_file}"
}

normalize_config_inputs() {
  TARGET_DISK="${TARGET_DISK:-}"
  STARTUP_POLICY="${STARTUP_POLICY:-}"
  UCODE_PACKAGE="${UCODE_PACKAGE:-}"
  GPU_DRIVER="${GPU_DRIVER:-}"
  ZRAM_SWAP_GB="${ZRAM_SWAP_GB:-}"
  SWAP_PARTITION_GB="${SWAP_PARTITION_GB:-}"
  CONSOLE_KEYMAP="${CONSOLE_KEYMAP:-}"
  TIMEZONE="${TIMEZONE:-}"
  HOSTNAME_VALUE="${HOSTNAME_VALUE:-}"
  INCLUDE_RETURN_MESSAGE="${INCLUDE_RETURN_MESSAGE:-no}"
  RETURN_MESSAGE_LANGUAGES_CSV="${RETURN_MESSAGE_LANGUAGES_CSV:-}"
  OWNER_NAME="${OWNER_NAME:-}"
  OWNER_PHONE="${OWNER_PHONE:-}"
  OWNER_EMAIL="${OWNER_EMAIL:-}"
  OWNER_RETURN_ADDRESS="${OWNER_RETURN_ADDRESS:-}"
  INCLUDE_LOGO="${INCLUDE_LOGO:-no}"
  LOGO_URL="${LOGO_URL:-}"
  SHARED_SECRET="${SHARED_SECRET:-}"
  PROCEED_INSTALL="yes"
}

validate_install_inputs() {
  [[ -n "${TARGET_DISK}" && -b "${TARGET_DISK}" ]] || die "TARGET_DISK must be an existing block device."
  [[ "${STARTUP_POLICY}" == "manual" || "${STARTUP_POLICY}" == "automatic" ]] || die "STARTUP_POLICY must be manual or automatic."
  [[ "${UCODE_PACKAGE}" == "intel-ucode" || "${UCODE_PACKAGE}" == "amd-ucode" || "${UCODE_PACKAGE}" == "none" ]] || die "UCODE_PACKAGE must be intel-ucode, amd-ucode, or none."
  [[ "${GPU_DRIVER}" == "nvidia" || "${GPU_DRIVER}" == "nvidia-open" || "${GPU_DRIVER}" == "nouveau" || "${GPU_DRIVER}" == "none" ]] || die "GPU_DRIVER must be nvidia, nvidia-open, nouveau, or none."
  [[ "${ZRAM_SWAP_GB}" =~ ^[0-9]+$ ]] || die "ZRAM_SWAP_GB must be a non-negative integer."
  [[ "${SWAP_PARTITION_GB}" =~ ^[0-9]+$ ]] || die "SWAP_PARTITION_GB must be a non-negative integer."
  [[ -n "${SHARED_SECRET}" ]] || die "SHARED_SECRET cannot be empty."
  [[ -n "${CONSOLE_KEYMAP}" ]] || die "CONSOLE_KEYMAP cannot be empty."
  [[ -e "/usr/share/zoneinfo/${TIMEZONE}" ]] || die "Invalid TIMEZONE: ${TIMEZONE}"
  validate_hostname "${HOSTNAME_VALUE}" || die "Invalid HOSTNAME_VALUE."

  parse_login_users_csv "${LOGIN_USERS_CSV:-}" || die "Invalid LOGIN_USERS_CSV."

  case "${INCLUDE_RETURN_MESSAGE}" in
    yes|no) ;;
    *) die "INCLUDE_RETURN_MESSAGE must be yes or no." ;;
  esac

  if [[ "${INCLUDE_RETURN_MESSAGE}" == "yes" ]]; then
    [[ -n "${OWNER_NAME}" ]] || die "OWNER_NAME cannot be empty."
    [[ -n "${OWNER_PHONE}" ]] || die "OWNER_PHONE cannot be empty."
    [[ -n "${OWNER_EMAIL}" ]] || die "OWNER_EMAIL cannot be empty."
    [[ -n "${OWNER_RETURN_ADDRESS}" ]] || die "OWNER_RETURN_ADDRESS cannot be empty."
    parse_return_message_languages_csv "${RETURN_MESSAGE_LANGUAGES_CSV:-}"
  else
    RETURN_MESSAGE_LANGUAGES=()
  fi

  case "${INCLUDE_LOGO}" in
    yes|no) ;;
    *) die "INCLUDE_LOGO must be yes or no." ;;
  esac
}

prepare_config_logo() {
  if [[ "${INCLUDE_RETURN_MESSAGE}" != "yes" ]]; then
    INCLUDE_LOGO="no"
    LOGO_URL=""
  elif [[ "${INCLUDE_LOGO}" == "yes" ]]; then
    [[ -n "${LOGO_URL}" ]] || die "LOGO_URL is required when INCLUDE_LOGO=yes."
    authenticated_logo_download "${LOGO_URL}" || die "Logo download failed from LOGO_URL in config file."
    log "Logo downloaded to ${LOGO_LOCAL_PATH}."
  else
    LOGO_URL=""
  fi
}

load_config_inputs() {
  load_inputs_from_config_file
  normalize_config_inputs
  validate_install_inputs
  prepare_config_logo
}

collect_login_users() {
  local raw_users=""

  while true; do
    raw_users="$(ask_non_empty "Login usernames (comma-separated): ")"
    parse_login_users_csv "${raw_users}" && return 0
  done
}

collect_return_message_languages() {
  local -a template_codes=()
  local template_path=""
  local selected=""
  local language=""

  while IFS= read -r template_path; do
    [[ -n "${template_path}" ]] || continue
    template_codes+=("$(basename "${template_path}" .tpl)")
  done < <(find "${OPARCH_REPO_ROOT}/assets/returning-templates" -maxdepth 1 -type f -name '*.tpl' | sort)

  [[ "${#template_codes[@]}" -gt 0 ]] || die "No return-message templates found."

  selected="$(printf '%s\n' "${template_codes[@]}" | prompt_choose_up_to "Return-message languages:" 4)"
  RETURN_MESSAGE_LANGUAGES=()
  while IFS= read -r language; do
    [[ -n "${language}" ]] || continue
    RETURN_MESSAGE_LANGUAGES+=("${language}")
  done <<< "${selected}"
}

collect_install_inputs() {
  prepare_live_temp_dir

  if [[ -n "${OPARCH_CONFIG_FILE:-}" ]]; then
    load_config_inputs
    return 0
  fi

  local -a available_disks=()
  local -a disk_labels=()
  local disk_entry=""

  while IFS= read -r disk_entry; do
    [[ -n "${disk_entry}" ]] || continue
    available_disks+=("${disk_entry}")
  done < <(lsblk -dpno NAME,TYPE | awk '$2 == "disk" { print $1 }')

  [[ "${#available_disks[@]}" -gt 0 ]] || die "No selectable disks found."

  local disk_path=""
  local disk_size=""
  local disk_model=""
  for disk_path in "${available_disks[@]}"; do
    disk_size="$(lsblk -dno SIZE "${disk_path}" 2>/dev/null | head -1 | xargs)"
    disk_model="$(lsblk -dno MODEL "${disk_path}" 2>/dev/null | head -1 | xargs)"
    if [[ -n "${disk_model}" ]]; then
      disk_labels+=("${disk_path} (${disk_size}, ${disk_model})")
    else
      disk_labels+=("${disk_path} (${disk_size})")
    fi
  done

  local selected_disk_label
  selected_disk_label="$(printf '%s\n' "${disk_labels[@]}" | prompt_choose)"

  local i=0
  for disk_path in "${available_disks[@]}"; do
    if [[ "${disk_labels[$i]}" == "${selected_disk_label}" ]]; then
      TARGET_DISK="${disk_path}"
      break
    fi
    ((i++))
  done

  STARTUP_POLICY="$(printf 'manual\nautomatic\n' | prompt_choose "Startup policy:")"
  UCODE_PACKAGE="$(printf 'intel-ucode\namd-ucode\nnone\n' | prompt_choose "Install ucode:")"
  GPU_DRIVER="$(printf 'nvidia\nnvidia-open\nnouveau\nnone\n' | prompt_choose "GPU driver:")"

  ZRAM_SWAP_GB="$(ask_uint "zram size in GB: ")"
  SWAP_PARTITION_GB="$(ask_uint "Swap partition size in GB: ")"

  collect_login_users

  SHARED_SECRET="$(read_secret_with_confirmation "Shared secret (LUKS + login users): ")"

  local -a keymap_list=()
  local km=""
  while IFS= read -r km; do
    [[ -n "${km}" ]] || continue
    keymap_list+=("$km")
  done < <(localectl list-keymaps 2>/dev/null)
  CONSOLE_KEYMAP="$(printf '%s\n' "${keymap_list[@]}" | prompt_filter "Console keymap")"
  CONSOLE_KEYMAP="$(trim "${CONSOLE_KEYMAP}")"
  if [[ -z "${CONSOLE_KEYMAP}" ]]; then
    die "Keymap selection cancelled."
  fi

  local -a timezone_list=()
  local tz=""
  while IFS= read -r tz; do
    [[ -n "${tz}" ]] || continue
    timezone_list+=("$tz")
  done < <(find /usr/share/zoneinfo -type f 2>/dev/null | sed 's|/usr/share/zoneinfo/||')
  while true; do
    TIMEZONE="$(printf '%s\n' "${timezone_list[@]}" | prompt_filter "Timezone")"
    TIMEZONE="$(trim "${TIMEZONE}")"
    if [[ -z "${TIMEZONE}" ]]; then
      die "Timezone selection cancelled."
    fi
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

  INCLUDE_RETURN_MESSAGE="$(printf 'yes\nno\n' | prompt_choose "Include pre-boot return message?")"
  if [[ "${INCLUDE_RETURN_MESSAGE}" == "yes" ]]; then
    OWNER_NAME="$(ask_non_empty "Owner name for pre-boot message: ")"
    OWNER_PHONE="$(ask_non_empty "Owner phone for pre-boot message: ")"
    OWNER_EMAIL="$(ask_non_empty "Owner email for pre-boot message: ")"
    OWNER_RETURN_ADDRESS="$(ask_non_empty "Owner return address for pre-boot message: ")"
    collect_return_message_languages

    INCLUDE_LOGO="$(printf 'yes\nno\n' | prompt_choose "Include company logo in pre-boot message?")"
    if [[ "${INCLUDE_LOGO}" == "yes" ]]; then
      while true; do
        LOGO_URL="$(ask_non_empty "Logo URL: ")"
        if authenticated_logo_download "${LOGO_URL}"; then
          log "Logo downloaded to ${LOGO_LOCAL_PATH}."
          break
        fi

        warn "Logo download failed."
        local failed_action
        failed_action="$(printf 'retry\ncontinue-without-logo\n' | prompt_choose "Logo download failed.")"
        if [[ "${failed_action}" == "continue-without-logo" ]]; then
          INCLUDE_LOGO="no"
          LOGO_URL=""
          break
        fi
      done
    fi
  else
    RETURN_MESSAGE_LANGUAGES=()
    INCLUDE_LOGO="no"
    LOGO_URL=""
  fi
}

confirm_destructive_install() {
  local destructive_confirmation=""

  if [[ "${OPARCH_WIPE_ALL:-no}" == "yes" ]]; then
    return 0
  fi

  destructive_confirmation="$(ask_non_empty "Type 'wipe-all' to confirm destructive install: ")"
  [[ "${destructive_confirmation}" == "wipe-all" ]] || die "Aborted. Confirmation value must be 'wipe-all'."
}

summarize_install_plan() {
  local login_user_csv
  local return_language_csv
  login_user_csv="$(join_by ', ' "${LOGIN_USERS[@]}")"
  return_language_csv="$(join_by ', ' "${RETURN_MESSAGE_LANGUAGES[@]}")"

  printf 'Installation summary:\n' >&3
  printf '  target disk: %s\n' "${TARGET_DISK}" >&3
  printf '  startup policy: %s\n' "${STARTUP_POLICY}" >&3
  printf '  ucode package: %s\n' "${UCODE_PACKAGE}" >&3
  printf '  gpu driver: %s\n' "${GPU_DRIVER}" >&3
  printf '  zram size (GB): %s\n' "${ZRAM_SWAP_GB}" >&3
  printf '  swap partition size (GB): %s\n' "${SWAP_PARTITION_GB}" >&3
  printf '  login users: %s\n' "${login_user_csv}" >&3
  printf '  keymap: %s\n' "${CONSOLE_KEYMAP}" >&3
  printf '  timezone: %s\n' "${TIMEZONE}" >&3
  printf '  hostname: %s\n' "${HOSTNAME_VALUE}" >&3
  printf '  include return message: %s\n' "${INCLUDE_RETURN_MESSAGE}" >&3
  if [[ "${INCLUDE_RETURN_MESSAGE}" == "yes" ]]; then
    printf '  return-message languages: %s\n' "${return_language_csv}" >&3
  fi
  printf '  include logo: %s\n' "${INCLUDE_LOGO}" >&3

  if [[ "${PROCEED_INSTALL}" == "yes" ]]; then
    return 0
  fi
  if [[ "${PROCEED_INSTALL}" == "no" ]]; then
    die "Aborted by config file."
  fi

  local proceed
  proceed="$(printf 'yes\nno\n' | prompt_choose "Proceed with installation?")"
  [[ "${proceed}" == "yes" ]] || die "Aborted by user."
}
