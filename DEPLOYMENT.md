# PDM Advanced Deployment Guide

Detailed deployment, integration, and migration documentation for Proxmox Datacenter Manager.

## Table of Contents

- [Reverse Proxy Setup](#reverse-proxy-setup)
- [SSL/TLS Considerations](#ssltls-considerations)
- [SDN / EVPN Support](#sdn--evpn-support)
- [Proxmox Backup Server (PBS) Integration](#proxmox-backup-server-pbs-integration)
- [Migration: Docker 0.9 to 1.1](#migration-docker-09-bookworm-to-11-trixie)
- [Migration: Docker to LXC](#migration-docker-to-native-lxc)
- [Backup and Restore](#backup-and-restore)

---

## Reverse Proxy Setup

PDM serves its web UI over HTTPS on port 8443 inside the container with a self-signed certificate. The default Docker compose file binds the host port to `127.0.0.1` only, mapped via `PDM_HOST_PORT` (default `8443`):

```yaml
ports:
  - "127.0.0.1:${PDM_HOST_PORT:-8443}:8443"
```

When placing PDM behind a reverse proxy, the proxy terminates the public TLS connection and forwards traffic to PDM's internal HTTPS endpoint on the host loopback address.

### Traefik

A compose override file is provided at `docker/docker-compose.traefik.yml`.

```bash
cd docker

# Edit the Host rule in docker-compose.traefik.yml
# Replace pdm.example.com with your domain

docker compose -f docker-compose.yml -f docker-compose.traefik.yml up -d
```

Because PDM uses a self-signed certificate internally, Traefik needs a `serversTransport` configured to skip TLS verification on the backend. Add this to your Traefik dynamic configuration:

```yaml
# traefik/dynamic/pdm.yml
http:
  serversTransports:
    pdm-insecure:
      insecureSkipVerify: true
```

### Nginx

```nginx
upstream pdm_backend {
    server 127.0.0.1:8443;
}

server {
    listen 443 ssl http2;
    server_name pdm.example.com;

    ssl_certificate     /etc/letsencrypt/live/pdm.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/pdm.example.com/privkey.pem;

    location / {
        proxy_pass https://pdm_backend;
        proxy_ssl_verify off;

        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}

server {
    listen 80;
    server_name pdm.example.com;
    return 301 https://$host$request_uri;
}
```

Key points:
- `proxy_ssl_verify off` is required because PDM uses a self-signed certificate
- WebSocket upgrade headers are included for real-time console features
- Adjust the upstream port if you changed `PDM_HOST_PORT` from the default

### Caddy

```
pdm.example.com {
    reverse_proxy https://localhost:8443 {
        transport http {
            tls_insecure_skip_verify
        }
    }
}
```

---

## SSL/TLS Considerations

- PDM generates a self-signed certificate on first startup for its HTTPS listener
- In production, use a reverse proxy (Traefik, Nginx, Caddy) to terminate TLS with a proper certificate from Let's Encrypt or your internal CA
- The reverse proxy must be configured to trust or skip verification of PDM's self-signed backend certificate
- PDM's authentication keys (`authkey.key`, `authkey.pub`) and CSRF token (`csrf.key`) are stored in `/etc/proxmox-datacenter-manager/` and are generated automatically if absent

---

## SDN / EVPN Support

PDM 1.1 centralizes Proxmox SDN management across clusters. If you intend to manage BGP/EVPN zones across disjointed clusters:

- The PDM host (container or LXC) **must reside on a network bridge** (`vmbrX`) that has L2/L3 reachability to the SDN underlay networks of all managed PVE nodes
- For Docker deployments, this typically means using `--network host` or a macvlan network that is bridged to the appropriate physical interface
- For LXC deployments, assign the container's `eth0` to the correct bridge in the `--bridge` flag of `setup-lxc.sh`

**Required ports** (between PDM and managed nodes):

| Port | Protocol | Purpose |
|---|---|---|
| 8006 | TCP | PVE API (nodes → PDM) |
| 8443 | TCP | PDM Web UI |
| 3128 | TCP | SPICE proxy |
| 5900-5999 | TCP | VNC console |

---

## Proxmox Backup Server (PBS) Integration

PDM 1.1 supports managing Proxmox Backup Server remotes. Configuration includes:

- PBS remote certificates are cached in `/etc/proxmox-datacenter-manager/`
- Ensure the PDM host can reach your PBS instances on port 8007
- When using Docker, the `./config:/etc/proxmox-datacenter-manager` volume mount persists PBS remote certificates across container restarts
- When using LXC, certificates persist natively in the container filesystem

---

## Migration: Docker 0.9 (Bookworm) to 1.1 (Trixie)

For users running the original Docker container based on Debian Bookworm and the `pdm-test` repository:

### Step 1: Stop and Back Up

```bash
cd docker
docker compose down

# Back up all persistent data
tar -czf pdm-backup-$(date +%Y%m%d).tar.gz config/ pdm-data/ pdm-cache/ pdm-logs/ 2>/dev/null || \
tar -czf pdm-backup-$(date +%Y%m%d).tar.gz config/
```

### Step 2: Update Compose File

Replace your existing `docker-compose.yml` with the new version from `docker/docker-compose.yml`. Key changes:
- Volume mounts for `/etc/proxmox-datacenter-manager`, `/var/lib/proxmox-datacenter-manager`, `/var/cache/proxmox-datacenter-manager`, and `/var/log/proxmox-datacenter-manager`
- Loopback-only host binding via `PDM_HOST_PORT`
- Health check configuration
- No VPN capabilities in the default image

### Step 3: Start

```bash
docker compose up -d
```

The `start-pdm.sh` entrypoint will:
- Run upstream `proxmox-datacenter-privileged-api setup` on first boot if keys are missing
- Set correct ownership for the `www-data` user
- Launch both daemons from `/usr/libexec/proxmox/`

### Step 4: Verify

```bash
# Check container health
docker compose ps

# Check logs
docker compose logs -f pdm

# Verify web UI
curl -fkss https://localhost:8443/api2/json/version
```

---

## Migration: Docker to Native LXC

For users wishing to migrate from Docker to native LXC deployment on Proxmox:

### Step 1: Provision LXC Container

```bash
bash lxc/setup-lxc.sh --vmid 200 --hostname pdm-prod
```

### Step 2: Stop Docker

```bash
cd docker
docker compose down
```

### Step 3: Transfer Data

```bash
# Get the container IP
CONTAINER_IP=$(pct exec 200 -- hostname -I | awk '{print $1}')

# Transfer PDM state and config
rsync -avz ./pdm-data/ root@${CONTAINER_IP}:/var/lib/proxmox-datacenter-manager/
rsync -avz ./config/ root@${CONTAINER_IP}:/etc/proxmox-datacenter-manager/
```

### Step 4: Fix Permissions

```bash
pct exec 200 -- chown -R www-data:www-data /var/lib/proxmox-datacenter-manager /etc/proxmox-datacenter-manager
```

### Step 5: Restart Services

```bash
pct exec 200 -- systemctl restart proxmox-datacenter-privileged-api proxmox-datacenter-api
```

### Step 6: Verify

```bash
pct exec 200 -- systemctl status proxmox-datacenter-api
curl -fkss https://${CONTAINER_IP}:8443/api2/json/version
```

---

## Backup and Restore

### Docker

Back up the persistent volumes while the container is stopped for consistency:

```bash
cd docker
docker compose down

# Create backup
tar -czf pdm-backup-$(date +%Y%m%d).tar.gz config/ pdm-data/ pdm-cache/ pdm-logs/

# Restore
tar -xzf pdm-backup-YYYYMMDD.tar.gz
docker compose up -d
```

Critical paths to back up:
- `config/` (`/etc/proxmox-datacenter-manager`) — auth keys, CSRF token, PBS certs
- `pdm-data/` (`/var/lib/proxmox-datacenter-manager`) — PDM state and cluster data
- `pdm-cache/` (`/var/cache/proxmox-datacenter-manager`) — cached cluster metrics
- `pdm-logs/` (`/var/log/proxmox-datacenter-manager`) — service logs

### LXC

Use Proxmox's native backup tools:

```bash
# Snapshot backup
vzdump <vmid> --storage <backup-storage> --mode snapshot

# Scheduled backups via PVE web UI or /etc/pve/jobs.cfg
```

Alternatively, back up only the PDM data:

```bash
pct exec <vmid> -- tar -czf /tmp/pdm-backup.tar.gz \
    /var/lib/proxmox-datacenter-manager \
    /var/cache/proxmox-datacenter-manager \
    /etc/proxmox-datacenter-manager

# Pull backup from container
pct pull <vmid> /tmp/pdm-backup.tar.gz ./pdm-backup.tar.gz
```
