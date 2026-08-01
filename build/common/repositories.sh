#!/usr/bin/env bash
# Configure the Proxmox Datacenter Manager APT repository on Debian trixie.
#
# Usage:
#   ./build/common/repositories.sh
#   PDM_APT_CHANNEL=enterprise ./build/common/repositories.sh
#   source build/common/repositories.sh
#
# Environment:
#   PDM_APT_CHANNEL  Repository component suffix (default: no-subscription).
#                    Allowed values: no-subscription, enterprise, test.

set -euo pipefail

PDM_APT_CHANNEL="${PDM_APT_CHANNEL:-no-subscription}"

case "${PDM_APT_CHANNEL}" in
  no-subscription | enterprise | test) ;;
  *)
    echo "ERROR: invalid PDM_APT_CHANNEL=${PDM_APT_CHANNEL} (allowed: no-subscription, enterprise, test)" >&2
    exit 1
    ;;
esac

KEYRING_PATH="/usr/share/keyrings/proxmox-archive-keyring.gpg"
SOURCES_PATH="/etc/apt/sources.list.d/proxmox-pdm.sources"
PROXMOX_RELEASE_URL="https://enterprise.proxmox.com/debian/proxmox-release-trixie.gpg"

mkdir -p "$(dirname "${KEYRING_PATH}")" "$(dirname "${SOURCES_PATH}")"

curl -fsSL "${PROXMOX_RELEASE_URL}" -o "${KEYRING_PATH}"
chmod 644 "${KEYRING_PATH}"

cat >"${SOURCES_PATH}" <<EOF
Types: deb
URIs: http://download.proxmox.com/debian/pdm
Suites: trixie
Components: pdm-${PDM_APT_CHANNEL}
Signed-By: ${KEYRING_PATH}
EOF
