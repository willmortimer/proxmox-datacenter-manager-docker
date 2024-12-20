# Use Debian Bookworm as the base image
FROM debian:bookworm

# Set environment variables to prevent interactive prompts
ENV DEBIAN_FRONTEND=noninteractive
ENV DEBCONF_NOWARNINGS=yes

# Install core dependencies
RUN apt-get update && apt-get install -y \
    wget \
    gnupg \
    ca-certificates \
    curl \
    iproute2 \
    debconf-utils \
    --no-install-recommends && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Add PDM repository and install PDM
RUN echo 'deb http://download.proxmox.com/debian/pdm bookworm pdm-test' > /etc/apt/sources.list.d/pdm-test.list && \
    wget https://enterprise.proxmox.com/debian/proxmox-release-bookworm.gpg -O /etc/apt/trusted.gpg.d/proxmox-release-bookworm.gpg && \
    apt-get update && \
    echo 'proxmox-datacenter-manager proxmox-datacenter-manager/conffile/reconfigure select keep-current' | debconf-set-selections && \
    apt-get install -y \
    proxmox-datacenter-manager proxmox-datacenter-manager-ui && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Expose the PDM port
EXPOSE 8443

# Set up a persistent volume for configuration and logs
VOLUME /var/lib/pdm

# Start the PDM service
CMD ["/usr/sbin/proxmox-datacenter-manager"]
