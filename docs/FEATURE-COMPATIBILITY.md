# Feature Compatibility: Native PDM vs Containers

This project packages [Proxmox Datacenter Manager](https://www.proxmox.com/en/products/proxmox-datacenter-manager) for Docker/Podman and LXC. PDM is a dual-daemon system service, not a typical web app. Several “local host” surfaces change meaning outside a full VM or the official ISO.

Statuses used below:

| Status | Meaning |
|---|---|
| **Native** | Behaves like a Debian/ISO install |
| **Container-equivalent** | Same intent; implementation adapted for the runtime |
| **Container-scoped** | Works, but observes the container/guest, not the physical Docker host |
| **Requires sidecar / host** | Needs overlay, VPN, proxy, or host integration |
| **Unsupported** | Do not expect this in that pathway |
| **Tested experimental** | Works in smoke tests; not upstream-supported |

## Pathway summary

| Pathway | Confidence | Notes |
|---|---|---|
| Official PDM ISO / Debian VM | Upstream preferred | Best production match |
| LXC (this repo) | Closest container match | systemd, vzdump, PVE HA |
| Docker / Podman (this repo) | Tested experimental | Evaluation, CI, homelab |

## Compatibility matrix

| PDM surface | LXC | Docker app container |
|---|---|---|
| Web UI / public API (8443) | Native | Container-equivalent |
| Privileged API (Unix socket) | Native (systemd) | Container-equivalent (`start-pdm.sh`) |
| Auth / CSRF / TLS setup | Native | Container-equivalent (upstream `setup`) |
| Remotes (PVE / PBS) | Native | Container-equivalent |
| Persistent config & state | Native | Container-equivalent (named/bind volumes) |
| Daily maintenance timer | Native (systemd timer) | Container-equivalent (entrypoint catch-up loop) |
| Local host metrics / physical inventory | Container-scoped (LXC guest) | Container-scoped (container cgroup/namespace) |
| Local shell / package updater UI | Container-scoped | Container-scoped; APT changes vanish on image replace |
| DNS / time / network OS settings | Guest OS | Container-local; prefer host or sidecar |
| Certificates | Native service cert | May conflict with reverse-proxy termination |
| Logs / journal | Guest journal | Container logs; journal may be incomplete |
| Reboot / shutdown | Guest lifecycle | Container lifecycle |
| VPN (Tailscale / WireGuard) | Optional (`--vpn`) | Requires sidecar / host (not in base image) |
| Reverse proxy | Manual | Requires sidecar (`compose.traefik.yml`) |
| ARM64 packages / images | Untested | Unsupported for published images (amd64 only) |

## Docker-specific warnings

1. **Local host means the container.** Metrics, shell, and updater views describe container-visible resources.
2. **Immutable image lifecycle.** Do not treat in-container APT upgrades as durable; rebuild/pull a new image instead.
3. **Default publish binds loopback.** `127.0.0.1:${PDM_HOST_PORT:-8443}:8443` — expose deliberately via proxy, VPN, or a chosen address.
4. **No VPN or extra capabilities in the base image.** Add networking as overlays, not by privileged defaults.

## LXC notes

LXC keeps systemd units and timers closer to upstream. Still treat the guest as the “local host.” Match `--storage` and `--bridge` to the PVE node; defaults (`local-lvm`, `vmbr0`) are not universal.

## Related docs

- [README.md](../README.md) — quick start and positioning
- [DEPLOYMENT.md](../DEPLOYMENT.md) — proxy, backup, migration
- [TRADEMARKS.md](../TRADEMARKS.md) — unofficial project notice
