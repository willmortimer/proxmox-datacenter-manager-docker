FROM debian:trixie

LABEL org.opencontainers.image.title="Proxmox Datacenter Manager"
LABEL org.opencontainers.image.description="Containerized PDM 1.0 with VPN support (WireGuard/Tailscale)"
LABEL org.opencontainers.image.source="https://github.com/willmortimer/proxmox-datacenter-manager-docker"
LABEL org.opencontainers.image.licenses="MIT"

ENV DEBIAN_FRONTEND=noninteractive
ENV DEBCONF_NOWARNINGS=yes

# Install system dependencies
RUN apt-get update && apt-get install -y \
    wget \
    gnupg \
    ca-certificates \
    curl \
    iproute2 \
    rsyslog \
    openssl \
    wireguard-tools \
    procps \
    --no-install-recommends && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Force dpkg non-interactive behavior
RUN echo 'DPkg::options { "--force-confdef"; "--force-confnew"; };' > /etc/apt/apt.conf.d/99force-conf

# Install Tailscale
RUN curl -fsSL https://pkgs.tailscale.com/stable/debian/trixie.noarmor.gpg \
        -o /usr/share/keyrings/tailscale-archive-keyring.gpg && \
    curl -fsSL https://pkgs.tailscale.com/stable/debian/trixie.tailscale-keyring.list \
        -o /etc/apt/sources.list.d/tailscale.list && \
    apt-get update && \
    apt-get install -y tailscale --no-install-recommends && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Install Proxmox Datacenter Manager (PDM 1.0 Stable)
RUN echo 'deb http://download.proxmox.com/debian/pdm trixie pdm' \
        > /etc/apt/sources.list.d/pdm.list && \
    wget -qO /etc/apt/trusted.gpg.d/proxmox-release-trixie.gpg \
        https://enterprise.proxmox.com/debian/proxmox-release-trixie.gpg && \
    apt-get update && \
    apt-get install -y \
        proxmox-datacenter-manager \
        proxmox-datacenter-manager-ui \
        --no-install-recommends && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Create required directories and set permissions
RUN mkdir -p \
        /var/lib/pdm \
        /var/lib/proxmox-datacenter-manager \
        /etc/proxmox-datacenter-manager \
        /var/log/proxmox-datacenter-manager \
        /var/run/tailscale \
        /run/proxmox-datacenter && \
    chown www-data:www-data \
        /var/lib/pdm \
        /var/lib/proxmox-datacenter-manager \
        /var/log/proxmox-datacenter-manager

# Copy and set entrypoint
COPY start-pdm.sh /usr/local/bin/start-pdm.sh
RUN chmod +x /usr/local/bin/start-pdm.sh

EXPOSE 8443

VOLUME /var/lib/pdm
VOLUME /var/lib/proxmox-datacenter-manager
VOLUME /etc/proxmox-datacenter-manager

ENTRYPOINT ["/usr/local/bin/start-pdm.sh"]
