# Dockerfile for the Squid proxy sidecar used by coding agents
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends squid ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Copy proxy configuration from build context
# Build context is project root, so docker/proxy/ is the correct path
COPY docker/proxy/squid.conf /etc/squid/squid.conf
COPY docker/proxy/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh \
    && mkdir -p /var/log/squid /var/spool/squid \
    && chown -R proxy:proxy /var/log/squid /var/spool/squid

EXPOSE 3128

ENTRYPOINT ["/entrypoint.sh"]
