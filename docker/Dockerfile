FROM debian:trixie

ARG PDM_APT_CHANNEL=no-subscription

LABEL org.opencontainers.image.title="Proxmox Datacenter Manager (unofficial experimental container)"
LABEL org.opencontainers.image.description="Unofficial experimental container image for Proxmox Datacenter Manager on Debian trixie"
LABEL org.opencontainers.image.source="https://github.com/willmortimer/proxmox-datacenter-manager-docker"
LABEL org.opencontainers.image.licenses="Mixed"
LABEL io.proxmox-datacenter-manager-docker.tooling-license="MIT"
LABEL io.proxmox-datacenter-manager-docker.pdm-license="AGPL-3.0"

ENV DEBIAN_FRONTEND=noninteractive
ENV DEBCONF_NOWARNINGS=yes

RUN apt-get update && apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    wget \
    procps \
    rsyslog \
    openssl \
    iproute2 \
    --no-install-recommends && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

RUN echo 'DPkg::options { "--force-confdef"; "--force-confnew"; };' > /etc/apt/apt.conf.d/99force-conf

COPY build/common/repositories.sh /tmp/repositories.sh
RUN chmod +x /tmp/repositories.sh && \
    PDM_APT_CHANNEL="${PDM_APT_CHANNEL}" /tmp/repositories.sh && \
    apt-get update && \
    apt-get install -y proxmox-datacenter-manager-container-meta --no-install-recommends && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

RUN mkdir -p \
    /etc/proxmox-datacenter-manager \
    /var/lib/proxmox-datacenter-manager \
    /var/cache/proxmox-datacenter-manager \
    /var/log/proxmox-datacenter-manager \
    /run/proxmox-datacenter-manager && \
    chown www-data:www-data \
    /var/lib/proxmox-datacenter-manager \
    /var/cache/proxmox-datacenter-manager \
    /var/log/proxmox-datacenter-manager

RUN dpkg-query -W -f='${Version}\n' proxmox-datacenter-manager > /etc/pdm-package-version 2>/dev/null || \
    dpkg-query -W -f='${Version}\n' proxmox-datacenter-manager-container-meta > /etc/pdm-package-version

COPY docker/start-pdm.sh /usr/local/bin/start-pdm.sh
RUN chmod +x /usr/local/bin/start-pdm.sh

EXPOSE 8443

VOLUME /etc/proxmox-datacenter-manager
VOLUME /var/lib/proxmox-datacenter-manager
VOLUME /var/cache/proxmox-datacenter-manager
VOLUME /var/log/proxmox-datacenter-manager

ENTRYPOINT ["/usr/local/bin/start-pdm.sh"]
