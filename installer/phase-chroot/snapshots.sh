#!/usr/bin/env bash

chroot_configure_snapshots() {
  cat > /usr/local/bin/oparch-snapshot-system <<'SYSTEM_SNAP_EOF'
#!/usr/bin/env bash
set -euo pipefail

reason="${1:-}"
if [[ -z "${reason}" ]]; then
  echo "Usage: oparch-snapshot-system <reason>" >&2
  exit 1
fi

timestamp="$(date +%Y%m%d-%H%M%S)"
slug="$(printf '%s' "${reason}" | tr '[:space:]/' '__' | tr -cd '[:alnum:]_.-')"
[[ -n "${slug}" ]] || slug="manual"
target="/snapshots/system/${timestamp}-${slug}"

btrfs subvolume snapshot -r / "${target}"
SYSTEM_SNAP_EOF
  chmod 755 /usr/local/bin/oparch-snapshot-system

  cat > /usr/local/bin/oparch-snapshot-home <<'HOME_SNAP_EOF'
#!/usr/bin/env bash
set -euo pipefail

target_user="${1:-}"
reason="${2:-}"
if [[ -z "${target_user}" || -z "${reason}" ]]; then
  echo "Usage: oparch-snapshot-home <user> <reason>" >&2
  exit 1
fi

source_subvol="/home/${target_user}"
target_dir="/snapshots/${target_user}"
[[ -d "${source_subvol}" ]] || { echo "Home subvolume not found: ${source_subvol}" >&2; exit 1; }

timestamp="$(date +%Y%m%d-%H%M%S)"
slug="$(printf '%s' "${reason}" | tr '[:space:]/' '__' | tr -cd '[:alnum:]_.-')"
[[ -n "${slug}" ]] || slug="manual"
target="${target_dir}/${timestamp}-${slug}"

btrfs subvolume snapshot -r "${source_subvol}" "${target}"
HOME_SNAP_EOF
  chmod 755 /usr/local/bin/oparch-snapshot-home
}
