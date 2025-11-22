# Dockerfile for the Squid proxy sidecar used by containai
FROM debian:12-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends squid ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Copy proxy configuration from build context
# Build context is project root, so docker/proxy/ is the correct path
COPY docker/proxy/squid.conf /etc/squid/squid.conf
COPY docker/proxy/entrypoint.sh /entrypoint.sh
COPY docker/proxy/error_pages/ERR_TOO_BIG /usr/share/squid/errors/en/ERR_TOO_BIG
RUN chmod +x /entrypoint.sh \
    && mkdir -p /var/log/squid /var/spool/squid \
    && chown -R proxy:proxy /var/log/squid /var/spool/squid

EXPOSE 3128

ENTRYPOINT ["/entrypoint.sh"]
