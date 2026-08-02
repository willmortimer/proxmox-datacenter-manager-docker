#!/bin/bash
set -euo pipefail

# ============================================================================
# PDM Multi-Process Entrypoint
# Manages: rsyslog, proxmox-datacenter-privileged-api (root),
#           proxmox-datacenter-api (www-data)
# ============================================================================

log() { echo "[pdm] $*"; }

PRIV_API_PID=""
API_PID=""
RSYSLOG_PID=""
MAINT_PID=""

cleanup() {
    log "Shutting down PDM services..."

    if [[ -n "$API_PID" ]] && kill -0 "$API_PID" 2>/dev/null; then
        log "Stopping proxmox-datacenter-api (PID $API_PID)..."
        kill -TERM "$API_PID" 2>/dev/null || true
    fi

    if [[ -n "$PRIV_API_PID" ]] && kill -0 "$PRIV_API_PID" 2>/dev/null; then
        log "Stopping proxmox-datacenter-privileged-api (PID $PRIV_API_PID)..."
        kill -TERM "$PRIV_API_PID" 2>/dev/null || true
    fi

    if [[ -n "$MAINT_PID" ]] && kill -0 "$MAINT_PID" 2>/dev/null; then
        kill -TERM "$MAINT_PID" 2>/dev/null || true
    fi

    if [[ -n "$RSYSLOG_PID" ]] && kill -0 "$RSYSLOG_PID" 2>/dev/null; then
        kill -TERM "$RSYSLOG_PID" 2>/dev/null || true
    fi

    wait
    log "All services stopped."
    exit 0
}

trap cleanup SIGTERM SIGINT

CONFIG_DIR="/etc/proxmox-datacenter-manager"
PRIV_SOCK="/run/proxmox-datacenter-manager/priv.sock"

log "Ensuring directory structure..."
mkdir -p \
    "$CONFIG_DIR" \
    /var/lib/proxmox-datacenter-manager \
    /var/cache/proxmox-datacenter-manager \
    /var/log/proxmox-datacenter-manager \
    /run/proxmox-datacenter-manager

chown www-data:www-data \
    /var/lib/proxmox-datacenter-manager \
    /var/cache/proxmox-datacenter-manager \
    /var/log/proxmox-datacenter-manager

if [[ ! -f "$CONFIG_DIR/authkey.key" ]] || [[ ! -f "$CONFIG_DIR/csrf.key" ]]; then
    log "Running privileged API setup (first boot)..."
    /usr/libexec/proxmox/proxmox-datacenter-privileged-api setup
fi

log "Starting rsyslog..."
rsyslogd
RSYSLOG_PID=$(cat /var/run/rsyslogd.pid 2>/dev/null || echo "")

log "Starting proxmox-datacenter-privileged-api..."
/usr/libexec/proxmox/proxmox-datacenter-privileged-api &
PRIV_API_PID=$!

log "Waiting for privileged API socket at $PRIV_SOCK..."
for i in $(seq 1 60); do
    if [[ -S "$PRIV_SOCK" ]]; then
        break
    fi
    sleep 1
done

if [[ ! -S "$PRIV_SOCK" ]]; then
    log "ERROR: Privileged API socket not found after 60s. Aborting."
    exit 1
fi

log "Starting proxmox-datacenter-api as www-data..."
su -s /bin/bash -c '/usr/libexec/proxmox/proxmox-datacenter-api' www-data &
API_PID=$!

log "PDM is running."
log "  Privileged API PID: $PRIV_API_PID"
log "  API PID:            $API_PID"
log "  Web UI:             https://localhost:8443"

# Reproduce upstream daily maintenance without systemd timers: catch up when
# the last successful run is older than 24h, then re-check hourly with jitter.
maintenance_loop() {
    local daily="/usr/libexec/proxmox/proxmox-datacenter-manager-daily-update"
    local stamp="/var/lib/proxmox-datacenter-manager/.maintenance-last-run"
    local now last age jitter

    if [[ ! -x "$daily" ]]; then
        log "Daily maintenance binary not found; skipping scheduler."
        return 0
    fi

    while true; do
        now="$(date +%s)"
        last=0
        if [[ -f "$stamp" ]]; then
            last="$(cat "$stamp" 2>/dev/null || echo 0)"
        fi
        age=$((now - last))
        if (( last == 0 || age >= 86400 )); then
            jitter=$((RANDOM % 300))
            log "Daily maintenance due (age=${age}s); waiting ${jitter}s jitter..."
            sleep "$jitter"
            if "$daily"; then
                date +%s >"$stamp"
                log "Daily maintenance completed."
            else
                log "WARNING: daily maintenance exited non-zero."
            fi
        fi
        sleep 3600
    done
}

maintenance_loop &
MAINT_PID=$!

wait -n "$PRIV_API_PID" "$API_PID" 2>/dev/null || true
log "A PDM process exited unexpectedly. Shutting down..."
cleanup
