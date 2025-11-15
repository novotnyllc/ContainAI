#!/usr/bin/env bash
set -euo pipefail

SQUID_CONF=${SQUID_CONF:-/etc/squid/squid.conf}
SQUID_CACHE_DIR=${SQUID_CACHE_DIR:-/var/spool/squid}
SQUID_LOG_DIR=${SQUID_LOG_DIR:-/var/log/squid}
ALLOWED_DOMAINS_FILE=/etc/squid/allowed-domains.txt

# Ensure directories exist with correct ownership
mkdir -p "$SQUID_CACHE_DIR" "$SQUID_LOG_DIR" "$(dirname "$ALLOWED_DOMAINS_FILE")"
chown -R proxy:proxy "$SQUID_CACHE_DIR" "$SQUID_LOG_DIR"

# Generate allowed domains file from environment variable
if [ -n "${SQUID_ALLOWED_DOMAINS:-}" ]; then
    echo "🌐 Configuring allowed domains for Squid proxy..."
    echo "$SQUID_ALLOWED_DOMAINS" | tr ',' '\n' | grep -v '^$' > "$ALLOWED_DOMAINS_FILE"
    echo "✅ Allowed domains configured: $(wc -l < "$ALLOWED_DOMAINS_FILE") domains"
else
    echo "⚠️  No SQUID_ALLOWED_DOMAINS set - using default allow all"
    echo ".github.com" > "$ALLOWED_DOMAINS_FILE"
fi

# Initialize cache if needed
if [ ! -f "$SQUID_CACHE_DIR/00/00000000" ]; then
    echo "🧱 Initializing Squid cache directories..."
    /usr/sbin/squid -z -f "$SQUID_CONF"
fi

# Start Squid in foreground so docker can manage lifecycle
echo "🛡️  Starting Squid proxy (listening on 3128)..."
exec /usr/sbin/squid -N -f "$SQUID_CONF"
