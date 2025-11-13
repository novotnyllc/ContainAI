#!/bin/bash
set -euo pipefail

SQUID_CONF=${SQUID_CONF:-/etc/squid/squid.conf}
SQUID_CACHE_DIR=${SQUID_CACHE_DIR:-/var/spool/squid}
SQUID_LOG_DIR=${SQUID_LOG_DIR:-/var/log/squid}

# Ensure directories exist with correct ownership
mkdir -p "$SQUID_CACHE_DIR" "$SQUID_LOG_DIR"
chown -R proxy:proxy "$SQUID_CACHE_DIR" "$SQUID_LOG_DIR"

# Initialize cache if needed
if [ ! -f "$SQUID_CACHE_DIR/00/00000000" ]; then
    echo "🧱 Initializing Squid cache directories..."
    /usr/sbin/squid -z -f "$SQUID_CONF"
fi

# Start Squid in foreground so docker can manage lifecycle
echo "🛡️  Starting Squid proxy (listening on 3128)..."
exec /usr/sbin/squid -N -f "$SQUID_CONF"
