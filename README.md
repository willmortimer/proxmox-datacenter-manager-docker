# Proxmox Datacenter Manager (PDM) Docker & LXC

> **Important:** Pre-built images on GHCR published before the current P0 remediation work may be outdated or broken. The **Docker pathway in this repository is experimental and unofficial** — see [TRADEMARKS.md](TRADEMARKS.md) for the official/unofficial distinction. Deployment tooling is [MIT licensed](LICENSE); Proxmox Datacenter Manager itself is AGPLv3; container images contain mixed licenses.

Containerized deployment of [Proxmox Datacenter Manager](https://www.proxmox.com/en/products/proxmox-datacenter-manager) (PDM), providing centralized management of multiple Proxmox VE clusters from a single interface. Docker images install current PDM packages via `proxmox-datacenter-manager-container-meta` (PDM 1.1 series on Debian Trixie).

This repository offers two deployment pathways: an **experimental Docker environment** for evaluation and homelab use, and a **native LXC deployment** for Proxmox administrators who prefer minimal overhead and native HA integration.

## Feature Matrix

| Feature | Docker | LXC |
|---|:---:|:---:|
| PDM 1.1 (Debian Trixie, via container-meta) | ✓ | ✓ |
| Dual-daemon security model | ✓ | ✓ |
| WireGuard VPN | — | optional |
| Tailscale VPN | — | optional |
| Automated key bootstrapping | ✓ | ✓ |
| Persistent data & config | ✓ | ✓ |
| Health checks | ✓ | systemd |
| Multi-arch (amd64/arm64) | ✓ | ✓ |
| Reverse proxy (Traefik) | ✓ | manual |
| Proxmox HA/clustering | — | ✓ |
| Native vzdump backup | — | ✓ |

The Docker base image does **not** include VPN software or privileges. VPN support is available as an optional add-on in the LXC pathway (`--vpn tailscale` or `--vpn wireguard`).

## Architecture

PDM uses a dual-daemon security model:

- **`proxmox-datacenter-api`** — The main web API, runs unprivileged as `www-data` (port 8443)
- **`proxmox-datacenter-privileged-api`** — System-level operations, runs as `root`, communicates via UNIX socket at `/run/proxmox-datacenter-manager/priv.sock`

On first boot, the Docker entrypoint runs upstream `proxmox-datacenter-privileged-api setup` to generate authentication keys and CSRF tokens. Both daemons are launched from `/usr/libexec/proxmox/` by `start-pdm.sh` (Docker) or systemd (LXC).

## Quick Start: Docker

```bash
git clone https://github.com/willmortimer/proxmox-datacenter-manager-docker.git
cd proxmox-datacenter-manager-docker/docker

# Start PDM
docker compose up -d

# Check health
docker compose ps
```

By default the web UI is bound to **127.0.0.1** on the host. Access it at **https://localhost:8443** (or the port set by `PDM_HOST_PORT`).

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

# With Tailscale (optional)
bash lxc/setup-lxc.sh --vmid 200 --vpn tailscale
```

Access the web UI at **https://\<container-ip\>:8443**

See [lxc/LXC-README.md](lxc/LXC-README.md) for full options and manual setup instructions.

## Configuration

### Environment Variables (Docker)

| Variable | Default | Description |
|---|---|---|
| `PDM_HOST_PORT` | `8443` | Host port mapped to PDM's internal HTTPS listener (8443). Binds to `127.0.0.1` only. |

### Persistent Volumes (Docker)

| Mount | Container Path | Purpose |
|---|---|---|
| `./config` | `/etc/proxmox-datacenter-manager` | Auth keys, CSRF token, certificates |
| `./pdm-data` | `/var/lib/proxmox-datacenter-manager` | PDM state and cluster data |
| `./pdm-cache` | `/var/cache/proxmox-datacenter-manager` | Cached cluster metrics |
| `./pdm-logs` | `/var/log/proxmox-datacenter-manager` | Service logs |

## Reverse Proxy

A Traefik override compose file is provided:

```bash
cd docker
docker compose -f docker-compose.yml -f docker-compose.traefik.yml up -d
```

Edit `docker-compose.traefik.yml` to set your domain. PDM listens on port 8443 inside the container; the host maps it via `PDM_HOST_PORT` to loopback. See [DEPLOYMENT.md](DEPLOYMENT.md) for Nginx examples and SSL details.

## Migration

### From PDM 0.9 (Bookworm) to 1.1 (Trixie)

1. `docker compose down`
2. Back up `./config`, `./pdm-data`, `./pdm-cache`, and `./pdm-logs`
3. Replace your compose file with the new version from `docker/`
4. `docker compose up -d` — PDM will run first-boot setup if keys are missing

### From Docker to Native LXC

1. Provision the LXC container: `bash lxc/setup-lxc.sh --vmid 200`
2. Stop the Docker container: `docker compose down`
3. Transfer data:
   ```bash
   rsync -avz ./pdm-data/ root@<lxc-ip>:/var/lib/proxmox-datacenter-manager/
   rsync -avz ./config/ root@<lxc-ip>:/etc/proxmox-datacenter-manager/
   ```
4. Fix permissions on the PVE host:
   ```bash
   pct exec 200 -- chown -R www-data:www-data /var/lib/proxmox-datacenter-manager /etc/proxmox-datacenter-manager
   ```
5. Restart services:
   ```bash
   pct exec 200 -- systemctl restart proxmox-datacenter-api
   ```

## Repository Structure

```
├── README.md                        # This file
├── DEPLOYMENT.md                    # Advanced deployment guides
├── LICENSE                          # MIT license for deployment tooling
├── TRADEMARKS.md                    # Trademark and licensing notice
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

Deployment tooling in this repository is licensed under the [MIT License](LICENSE). Proxmox Datacenter Manager and other Proxmox software installed from Debian packages is licensed under AGPLv3 and other upstream licenses. See [TRADEMARKS.md](TRADEMARKS.md) for the full trademark and licensing notice.
