# Proxmox Datacenter Manager (PDM) Docker & LXC

Containerized deployment of [Proxmox Datacenter Manager](https://www.proxmox.com/en/products/proxmox-datacenter-manager) (PDM) 1.0 Stable, providing centralized management of multiple Proxmox VE clusters from a single interface.

This repository offers two deployment pathways: a **hardened Docker environment** with VPN sidecar support, and a **native LXC deployment** for Proxmox administrators who prefer minimal overhead and native HA integration.

## Feature Matrix

| Feature | Docker | LXC |
|---|:---:|:---:|
| PDM 1.0 Stable (Debian Trixie) | ✓ | ✓ |
| Dual-daemon security model | ✓ | ✓ |
| WireGuard VPN | ✓ | ✓ |
| Tailscale VPN | ✓ | ✓ |
| Automated key bootstrapping | ✓ | ✓ |
| Persistent data & config | ✓ | ✓ |
| Health checks | ✓ | systemd |
| Multi-arch (amd64/arm64) | ✓ | ✓ |
| Reverse proxy (Traefik) | ✓ | manual |
| Proxmox HA/clustering | — | ✓ |
| Native vzdump backup | — | ✓ |

## Architecture

PDM 1.0 uses a dual-daemon security model:

- **`proxmox-datacenter-api`** — The main web API, runs unprivileged as `www-data` (port 8443)
- **`proxmox-datacenter-privileged-api`** — System-level operations, runs as `root`, communicates via UNIX socket

Both daemons are managed by the `start-pdm.sh` entrypoint (Docker) or systemd (LXC). Authentication keys and CSRF tokens are generated automatically on first startup.

## Quick Start: Docker

```bash
git clone https://github.com/willmortimer/proxmox-datacenter-manager-docker.git
cd proxmox-datacenter-manager-docker/docker

# Start PDM
docker compose up -d

# Check health
docker compose ps
```

Access the web UI at **https://localhost:8443**

### Build Locally

```bash
cd docker
docker compose up -d --build
```

### Use Pre-built Image

Update `docker-compose.yml` to remove the `build: .` line and use:
```yaml
image: ghcr.io/willmortimer/pdm:latest
```

## Quick Start: LXC

Run directly on a Proxmox VE host node:

```bash
git clone https://github.com/willmortimer/proxmox-datacenter-manager-docker.git
cd proxmox-datacenter-manager-docker

# Basic deployment
bash lxc/setup-lxc.sh --vmid 200

# With Tailscale
bash lxc/setup-lxc.sh --vmid 200 --vpn tailscale
```

Access the web UI at **https://\<container-ip\>:8443**

See [lxc/LXC-README.md](lxc/LXC-README.md) for full options and manual setup instructions.

## Configuration

### Environment Variables (Docker)

| Variable | Default | Description |
|---|---|---|
| `PDM_PORT` | `8443` | HTTPS port for the PDM web UI |
| `ENABLE_WIREGUARD` | `false` | Enable WireGuard VPN interface |
| `ENABLE_TAILSCALE` | `false` | Enable Tailscale mesh VPN |
| `TAILSCALE_AUTHKEY` | *(empty)* | Tailscale auth key for automatic authentication |

### Persistent Volumes (Docker)

| Mount | Container Path | Purpose |
|---|---|---|
| `./data` | `/var/lib/pdm` | PDM state and SQLite database |
| `./pdm-data` | `/var/lib/proxmox-datacenter-manager` | Cached cluster metrics |
| `./config` | `/etc/proxmox-datacenter-manager` | Auth keys, CSRF token, certificates |
| `./wireguard` | `/etc/wireguard` | WireGuard configuration |
| `./tailscale` | `/var/lib/tailscale` | Tailscale state |

## VPN Setup

### WireGuard

1. Place your WireGuard configuration at `docker/wireguard/wg0.conf`
2. Set `ENABLE_WIREGUARD: "true"` in `docker-compose.yml`
3. Restart the container: `docker compose restart`

### Tailscale

1. Set `ENABLE_TAILSCALE: "true"` in `docker-compose.yml`
2. Optionally set `TAILSCALE_AUTHKEY` for headless authentication
3. Restart the container: `docker compose restart`
4. If no auth key is set, authenticate manually:
   ```bash
   docker exec -it proxmox-datacenter-manager tailscale up
   ```

## Reverse Proxy

A Traefik override compose file is provided:

```bash
cd docker
docker compose -f docker-compose.yml -f docker-compose.traefik.yml up -d
```

Edit `docker-compose.traefik.yml` to set your domain. See [DEPLOYMENT.md](DEPLOYMENT.md) for Nginx examples and SSL details.

## Migration

### From PDM 0.9 (Bookworm) to 1.0 (Trixie)

1. `docker compose down`
2. Back up `./data` directory
3. Replace your compose file with the new version from `docker/`
4. Add the new `./config` volume mount for `/etc/proxmox-datacenter-manager`
5. `docker compose up -d` — the database will auto-upgrade

### From Docker to Native LXC

1. Provision the LXC container: `bash lxc/setup-lxc.sh --vmid 200`
2. Stop the Docker container: `docker compose down`
3. Transfer data:
   ```bash
   rsync -avz ./data/ root@<lxc-ip>:/var/lib/pdm/
   rsync -avz ./config/ root@<lxc-ip>:/etc/proxmox-datacenter-manager/
   ```
4. Fix permissions on the PVE host:
   ```bash
   pct exec 200 -- chown -R www-data:www-data /var/lib/pdm /etc/proxmox-datacenter-manager
   ```
5. Restart services:
   ```bash
   pct exec 200 -- systemctl restart proxmox-datacenter-api
   ```

## Repository Structure

```
├── README.md                        # This file
├── DEPLOYMENT.md                    # Advanced deployment guides
├── docker/
│   ├── Dockerfile                   # Trixie-based PDM image
│   ├── start-pdm.sh                 # Multi-process entrypoint
│   ├── docker-compose.yml           # Production-ready compose
│   └── docker-compose.traefik.yml   # Traefik reverse proxy overlay
├── lxc/
│   ├── setup-lxc.sh                 # Automated PVE host provisioning
│   ├── config-templates/
│   │   └── tailscale-tun.conf       # TUN device config for unprivileged LXC
│   └── LXC-README.md               # LXC deployment documentation
└── .github/workflows/
    └── docker-publish.yml           # Multi-arch CI/CD
```

## Contributing

Contributions are welcome. Please open an issue or pull request.

## License

This project is provided as-is for the Proxmox community. Proxmox Datacenter Manager is a product of [Proxmox Server Solutions GmbH](https://www.proxmox.com/).
