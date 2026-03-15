#!/bin/bash
set -euo pipefail

# ============================================================================
# PDM Multi-Process Entrypoint
# Manages: rsyslog, proxmox-datacenter-privileged-api (root),
#           proxmox-datacenter-api (www-data), and optional VPN daemons
# ============================================================================

log() { echo "[pdm] $*"; }
warn() { echo "[pdm] WARNING: $*"; }

PRIV_API_PID=""
API_PID=""
RSYSLOG_PID=""
TAILSCALED_PID=""

cleanup() {
    log "Shutting down PDM services..."

    # Stop in reverse order
    if [[ -n "$API_PID" ]] && kill -0 "$API_PID" 2>/dev/null; then
        log "Stopping proxmox-datacenter-api (PID $API_PID)..."
        kill -TERM "$API_PID" 2>/dev/null || true
    fi

    if [[ -n "$PRIV_API_PID" ]] && kill -0 "$PRIV_API_PID" 2>/dev/null; then
        log "Stopping proxmox-datacenter-privileged-api (PID $PRIV_API_PID)..."
        kill -TERM "$PRIV_API_PID" 2>/dev/null || true
    fi

    # Stop VPN services
    if [[ "${ENABLE_WIREGUARD:-false}" == "true" ]]; then
        log "Stopping WireGuard..."
        wg-quick down wg0 2>/dev/null || true
    fi

    if [[ -n "$TAILSCALED_PID" ]] && kill -0 "$TAILSCALED_PID" 2>/dev/null; then
        log "Stopping Tailscale..."
        kill -TERM "$TAILSCALED_PID" 2>/dev/null || true
    fi

    if [[ -n "$RSYSLOG_PID" ]] && kill -0 "$RSYSLOG_PID" 2>/dev/null; then
        kill -TERM "$RSYSLOG_PID" 2>/dev/null || true
    fi

    wait
    log "All services stopped."
    exit 0
}

trap cleanup SIGTERM SIGINT

# ============================================================================
# Key Generation (idempotent)
# ============================================================================

KEY_DIR="/etc/proxmox-datacenter-manager"
mkdir -p "$KEY_DIR"

if [[ ! -f "$KEY_DIR/authkey.key" ]]; then
    log "Generating authentication keys..."
    openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:4096 -out "$KEY_DIR/authkey.key" 2>/dev/null
    openssl pkey -in "$KEY_DIR/authkey.key" -pubout -out "$KEY_DIR/authkey.pub" 2>/dev/null
    chmod 640 "$KEY_DIR/authkey.key"
    chmod 644 "$KEY_DIR/authkey.pub"
    chown root:www-data "$KEY_DIR/authkey.key"
    log "Authentication keys generated."
fi

if [[ ! -f "$KEY_DIR/csrf.key" ]]; then
    log "Generating CSRF key..."
    openssl rand -base64 32 > "$KEY_DIR/csrf.key"
    chmod 640 "$KEY_DIR/csrf.key"
    chown root:www-data "$KEY_DIR/csrf.key"
    log "CSRF key generated."
fi

# ============================================================================
# Directory Permissions
# ============================================================================

log "Ensuring directory permissions..."
mkdir -p /var/lib/pdm /var/lib/proxmox-datacenter-manager /var/log/proxmox-datacenter-manager
chown -R www-data:www-data /var/lib/proxmox-datacenter-manager
chown -R www-data:www-data /var/lib/pdm
chown -R www-data:www-data /var/log/proxmox-datacenter-manager

# ============================================================================
# Start rsyslog (container logging)
# ============================================================================

log "Starting rsyslog..."
rsyslogd
RSYSLOG_PID=$(cat /var/run/rsyslogd.pid 2>/dev/null || echo "")

# ============================================================================
# VPN Services (conditional)
# ============================================================================

if [[ "${ENABLE_WIREGUARD:-false}" == "true" ]]; then
    if [[ -f /etc/wireguard/wg0.conf ]]; then
        log "Starting WireGuard..."
        wg-quick up wg0
        log "WireGuard interface up."
    else
        warn "ENABLE_WIREGUARD=true but /etc/wireguard/wg0.conf not found."
    fi
fi

if [[ "${ENABLE_TAILSCALE:-false}" == "true" ]]; then
    log "Starting Tailscale daemon..."
    tailscaled --state=/var/lib/tailscale/tailscaled.state --socket=/var/run/tailscale/tailscaled.sock &
    TAILSCALED_PID=$!

    # Wait for the socket to be ready
    for i in $(seq 1 10); do
        if [[ -S /var/run/tailscale/tailscaled.sock ]]; then
            break
        fi
        sleep 1
    done

    if [[ -n "${TAILSCALE_AUTHKEY:-}" ]]; then
        log "Authenticating Tailscale with authkey..."
        tailscale up --authkey="$TAILSCALE_AUTHKEY" --accept-routes
    else
        log "Tailscale daemon started. Run 'tailscale up' manually to authenticate."
    fi
fi

# ============================================================================
# Start PDM Services
# ============================================================================

log "Starting proxmox-datacenter-privileged-api..."
proxmox-datacenter-privileged-api &
PRIV_API_PID=$!

# Wait for the privileged API socket to be ready
log "Waiting for privileged API socket..."
for i in $(seq 1 30); do
    if [[ -S /run/proxmox-datacenter/privileged-api.sock ]]; then
        break
    fi
    sleep 1
done

if [[ ! -S /run/proxmox-datacenter/privileged-api.sock ]]; then
    warn "Privileged API socket not found after 30s, starting API anyway."
fi

log "Starting proxmox-datacenter-api as www-data on port ${PDM_PORT:-8443}..."
su -s /bin/bash -c "proxmox-datacenter-api" www-data &
API_PID=$!

log "PDM is running."
log "  Privileged API PID: $PRIV_API_PID"
log "  API PID:            $API_PID"
log "  Web UI:             https://localhost:${PDM_PORT:-8443}"

# ============================================================================
# Wait for processes
# ============================================================================

wait -n "$PRIV_API_PID" "$API_PID" 2>/dev/null || true
log "A PDM process exited unexpectedly. Shutting down..."
cleanup
