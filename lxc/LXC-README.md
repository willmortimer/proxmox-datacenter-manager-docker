# PDM Native LXC Deployment

Deploy Proxmox Datacenter Manager directly in an LXC container on your Proxmox VE host. This approach reduces overhead compared to Docker and allows native Proxmox HA/clustering features.

## Prerequisites

- Proxmox VE 8.x or later
- Root access on the PVE host node
- Internet connectivity (to download templates and packages)

## Quick Start

```bash
# Clone the repository on your PVE host
git clone https://github.com/willmortimer/proxmox-datacenter-manager-docker.git
cd proxmox-datacenter-manager-docker

# Basic deployment
bash lxc/setup-lxc.sh --vmid 200

# With Tailscale VPN support
bash lxc/setup-lxc.sh --vmid 200 --vpn tailscale

# Fully customized
bash lxc/setup-lxc.sh --vmid 200 \
    --hostname pdm-prod \
    --vpn tailscale \
    --memory 4096 \
    --cores 4 \
    --storage local-zfs \
    --bridge vmbr1
```

Access the web UI at `https://<container-ip>:8443` after setup completes.

## Script Options

| Option | Default | Description |
|---|---|---|
| `--vmid <id>` | *(required)* | LXC container VMID |
| `--hostname <name>` | `pdm` | Container hostname |
| `--vpn <type>` | `none` | VPN support: `tailscale`, `wireguard`, or `none` |
| `--storage <pool>` | `local-lvm` | Storage pool for root filesystem |
| `--memory <MB>` | `2048` | Memory allocation |
| `--cores <n>` | `2` | CPU core count |
| `--bridge <name>` | `vmbr0` | Network bridge |
| `--disk <GB>` | `8` | Root disk size |

## Manual Setup

If you prefer to set up PDM manually in an existing container:

```bash
# 1. Create an unprivileged Debian Trixie container with nesting
pct create 200 local:vztmpl/debian-13-standard_13.2-1_amd64.tar.zst \
    --hostname pdm --memory 2048 --cores 2 \
    --rootfs local-lvm:8 --net0 name=eth0,bridge=vmbr0,ip=dhcp \
    --unprivileged 1 --features nesting=1,keyctl=1

# 2. Start the container
pct start 200

# 3. Install PDM inside the container
pct exec 200 -- bash -c '
    apt-get update && apt-get install -y wget gnupg ca-certificates
    echo "deb http://download.proxmox.com/debian/pdm trixie pdm" \
        > /etc/apt/sources.list.d/pdm.list
    wget -qO /etc/apt/trusted.gpg.d/proxmox-release-trixie.gpg \
        https://enterprise.proxmox.com/debian/proxmox-release-trixie.gpg
    apt-get update
    apt-get install -y proxmox-datacenter-manager proxmox-datacenter-manager-ui
    systemctl enable --now proxmox-datacenter-privileged-api proxmox-datacenter-api
'
```

## VPN in Unprivileged LXC

Running Tailscale or WireGuard in an unprivileged LXC container requires TUN/TAP device access. The `setup-lxc.sh` script handles this automatically when `--vpn` is specified.

For manual configuration, append the following to `/etc/pve/lxc/<vmid>.conf` on the PVE host (**while the container is stopped**):

```
lxc.cgroup2.devices.allow: c 10:200 rwm
lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file
```

Then start the container and install the VPN software:

```bash
# Tailscale
pct exec 200 -- bash -c '
    curl -fsSL https://pkgs.tailscale.com/stable/debian/trixie.noarmor.gpg \
        -o /usr/share/keyrings/tailscale-archive-keyring.gpg
    curl -fsSL https://pkgs.tailscale.com/stable/debian/trixie.tailscale-keyring.list \
        -o /etc/apt/sources.list.d/tailscale.list
    apt-get update && apt-get install -y tailscale
    systemctl enable --now tailscaled
'
pct exec 200 -- tailscale up

# WireGuard
pct exec 200 -- apt-get install -y wireguard-tools
# Place your config at /etc/wireguard/wg0.conf inside the container
pct exec 200 -- wg-quick up wg0
```

## Managing PDM Services

```bash
# Check service status
pct exec <vmid> -- systemctl status proxmox-datacenter-api
pct exec <vmid> -- systemctl status proxmox-datacenter-privileged-api

# Restart services
pct exec <vmid> -- systemctl restart proxmox-datacenter-api

# View logs
pct exec <vmid> -- journalctl -u proxmox-datacenter-api -f
```

## Backup

LXC containers can be backed up natively through the Proxmox VE web UI or CLI:

```bash
vzdump <vmid> --storage <backup-storage> --mode snapshot
```

This captures the entire container state including PDM configuration, database, and certificates.

## Troubleshooting

**TUN device errors with VPN:**
Ensure the cgroup2 device rules are in the LXC config. The container must be fully stopped and restarted after modifying `/etc/pve/lxc/<vmid>.conf`.

**Permission denied on PDM data directories:**
```bash
pct exec <vmid> -- chown -R www-data:www-data /var/lib/pdm /etc/proxmox-datacenter-manager
```

**Container cannot reach Proxmox nodes:**
Verify the container's network bridge has L2/L3 reachability to your managed PVE nodes. If using SDN/EVPN, the container must reside on a bridge with access to the SDN underlay.
