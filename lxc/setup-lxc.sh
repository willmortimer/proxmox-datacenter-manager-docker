#!/bin/bash
set -euo pipefail

# ============================================================================
# PDM LXC Provisioning Script
# Run this script on a Proxmox VE host node to create and configure
# a Debian Trixie LXC container running Proxmox Datacenter Manager.
# ============================================================================

# Defaults
VMID=""
HOSTNAME="pdm"
VPN="none"
STORAGE="local-lvm"
MEMORY=2048
CORES=2
BRIDGE="vmbr0"
DISK_SIZE=8

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Provision a Proxmox Datacenter Manager (PDM) LXC container on this PVE host.

Options:
  --vmid <id>           Container VMID (required)
  --hostname <name>     Container hostname (default: pdm)
  --vpn <type>          VPN support: tailscale, wireguard, or none (default: none)
  --storage <pool>      Storage pool for rootfs (default: local-lvm)
  --memory <MB>         Memory in MB (default: 2048)
  --cores <n>           CPU cores (default: 2)
  --bridge <name>       Network bridge (default: vmbr0)
  --disk <GB>           Root disk size in GB (default: 8)
  -h, --help            Show this help message

Examples:
  $(basename "$0") --vmid 200
  $(basename "$0") --vmid 200 --hostname pdm-prod --vpn tailscale
  $(basename "$0") --vmid 200 --memory 4096 --cores 4 --storage local-zfs
EOF
    exit 0
}

# ============================================================================
# Argument Parsing
# ============================================================================

while [[ $# -gt 0 ]]; do
    case "$1" in
        --vmid)     VMID="$2"; shift 2 ;;
        --hostname) HOSTNAME="$2"; shift 2 ;;
        --vpn)      VPN="$2"; shift 2 ;;
        --storage)  STORAGE="$2"; shift 2 ;;
        --memory)   MEMORY="$2"; shift 2 ;;
        --cores)    CORES="$2"; shift 2 ;;
        --bridge)   BRIDGE="$2"; shift 2 ;;
        --disk)     DISK_SIZE="$2"; shift 2 ;;
        -h|--help)  usage ;;
        *)          echo "Unknown option: $1"; usage ;;
    esac
done

# ============================================================================
# Preflight Checks
# ============================================================================

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: This script must be run as root on a Proxmox VE host."
    exit 1
fi

if ! command -v pct &>/dev/null; then
    echo "ERROR: 'pct' not found. This script must be run on a Proxmox VE host."
    exit 1
fi

if [[ -z "$VMID" ]]; then
    echo "ERROR: --vmid is required."
    usage
fi

if [[ "$VPN" != "none" && "$VPN" != "tailscale" && "$VPN" != "wireguard" ]]; then
    echo "ERROR: --vpn must be 'none', 'tailscale', or 'wireguard'."
    exit 1
fi

if pct status "$VMID" &>/dev/null; then
    echo "ERROR: Container with VMID $VMID already exists."
    exit 1
fi

# ============================================================================
# Download Debian Trixie Template
# ============================================================================

TEMPLATE_STORAGE="local"
TEMPLATE_NAME=$(pveam available --section system | grep 'debian-13.*standard' | tail -1 | awk '{print $2}')

if [[ -z "$TEMPLATE_NAME" ]]; then
    echo "ERROR: Could not find a Debian 13 (Trixie) template. Update template list with:"
    echo "  pveam update"
    exit 1
fi

if ! pveam list "$TEMPLATE_STORAGE" | grep -q "$TEMPLATE_NAME"; then
    echo "[setup] Downloading $TEMPLATE_NAME..."
    pveam download "$TEMPLATE_STORAGE" "$TEMPLATE_NAME"
fi

TEMPLATE_PATH="${TEMPLATE_STORAGE}:vztmpl/${TEMPLATE_NAME}"

# ============================================================================
# Create Container
# ============================================================================

echo "[setup] Creating LXC container $VMID ($HOSTNAME)..."
pct create "$VMID" "$TEMPLATE_PATH" \
    --hostname "$HOSTNAME" \
    --memory "$MEMORY" \
    --cores "$CORES" \
    --rootfs "${STORAGE}:${DISK_SIZE}" \
    --net0 "name=eth0,bridge=${BRIDGE},ip=dhcp" \
    --unprivileged 1 \
    --features nesting=1,keyctl=1 \
    --start 0

# ============================================================================
# VPN Configuration (inject into LXC config before first start)
# ============================================================================

LXC_CONF="/etc/pve/lxc/${VMID}.conf"

if [[ "$VPN" == "tailscale" || "$VPN" == "wireguard" ]]; then
    echo "[setup] Injecting VPN (${VPN}) configuration into ${LXC_CONF}..."

    TUN_CONF="${SCRIPT_DIR}/config-templates/tailscale-tun.conf"
    if [[ -f "$TUN_CONF" ]]; then
        echo "" >> "$LXC_CONF"
        grep -v '^#' "$TUN_CONF" | grep -v '^$' >> "$LXC_CONF"
    else
        # Inline fallback if config template is missing
        cat >> "$LXC_CONF" <<VPNEOF

# VPN TUN/TAP device access
lxc.cgroup2.devices.allow: c 10:200 rwm
lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file
VPNEOF
    fi
fi

# ============================================================================
# Start Container and Install PDM
# ============================================================================

echo "[setup] Starting container $VMID..."
pct start "$VMID"

# Wait for container networking
echo "[setup] Waiting for container networking..."
for i in $(seq 1 30); do
    if pct exec "$VMID" -- ping -c1 -W1 download.proxmox.com &>/dev/null; then
        break
    fi
    sleep 2
done

echo "[setup] Installing PDM packages inside container..."
pct exec "$VMID" -- bash -c '
    set -e
    export DEBIAN_FRONTEND=noninteractive

    apt-get update
    apt-get install -y wget gnupg ca-certificates --no-install-recommends

    # Add PDM repository
    echo "deb http://download.proxmox.com/debian/pdm trixie pdm" \
        > /etc/apt/sources.list.d/pdm.list
    wget -qO /etc/apt/trusted.gpg.d/proxmox-release-trixie.gpg \
        https://enterprise.proxmox.com/debian/proxmox-release-trixie.gpg

    apt-get update
    apt-get install -y proxmox-datacenter-manager proxmox-datacenter-manager-ui --no-install-recommends
    apt-get clean
    rm -rf /var/lib/apt/lists/*

    # Enable and start PDM services
    systemctl enable proxmox-datacenter-privileged-api.service
    systemctl enable proxmox-datacenter-api.service
    systemctl start proxmox-datacenter-privileged-api.service
    systemctl start proxmox-datacenter-api.service
'

# Install VPN software if requested
if [[ "$VPN" == "tailscale" ]]; then
    echo "[setup] Installing Tailscale..."
    pct exec "$VMID" -- bash -c '
        set -e
        export DEBIAN_FRONTEND=noninteractive
        curl -fsSL https://pkgs.tailscale.com/stable/debian/trixie.noarmor.gpg \
            -o /usr/share/keyrings/tailscale-archive-keyring.gpg
        curl -fsSL https://pkgs.tailscale.com/stable/debian/trixie.tailscale-keyring.list \
            -o /etc/apt/sources.list.d/tailscale.list
        apt-get update
        apt-get install -y tailscale --no-install-recommends
        systemctl enable tailscaled
        systemctl start tailscaled
        apt-get clean && rm -rf /var/lib/apt/lists/*
    '
    echo "[setup] Tailscale installed. Run: pct exec $VMID -- tailscale up"
fi

if [[ "$VPN" == "wireguard" ]]; then
    echo "[setup] Installing WireGuard tools..."
    pct exec "$VMID" -- bash -c '
        set -e
        export DEBIAN_FRONTEND=noninteractive
        apt-get update
        apt-get install -y wireguard-tools --no-install-recommends
        apt-get clean && rm -rf /var/lib/apt/lists/*
    '
    echo "[setup] WireGuard installed. Place your config at /etc/wireguard/wg0.conf inside the container."
fi

# ============================================================================
# Summary
# ============================================================================

CONTAINER_IP=$(pct exec "$VMID" -- hostname -I 2>/dev/null | awk '{print $1}')

echo ""
echo "============================================"
echo "  PDM LXC Container Ready"
echo "============================================"
echo "  VMID:     $VMID"
echo "  Hostname: $HOSTNAME"
echo "  IP:       ${CONTAINER_IP:-<pending DHCP>}"
echo "  VPN:      $VPN"
echo ""
echo "  Web UI:   https://${CONTAINER_IP:-<ip>}:8443"
echo ""
if [[ "$VPN" == "tailscale" ]]; then
    echo "  Tailscale: pct exec $VMID -- tailscale up"
fi
echo "============================================"
