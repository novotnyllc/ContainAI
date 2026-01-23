#!/bin/bash
# Start Docker daemon for DinD testing
# Used by Dockerfile.test as the container entrypoint
#
# This script runs inside a sysbox system container, so no manual sysbox
# service startup is needed - the host's sysbox runtime provides coordination.
# Inner Docker uses sysbox-runc as its default runtime.
set -euo pipefail

DOCKERD_LOG="/var/log/dockerd.log"

# Start Docker daemon (hosts configured in daemon.json; do NOT use -H flag to avoid conflict)
printf '%s\n' "[INFO] Starting dockerd on /var/run/docker-test.sock..."
dockerd --config-file /etc/docker/daemon.json >"$DOCKERD_LOG" 2>&1 &
DOCKERD_PID=$!

# Wait for Docker to be ready (max 30 seconds)
printf '%s\n' "[INFO] Waiting for Docker to be ready..."
TIMEOUT=30
COUNTER=0
while ! docker info >/dev/null 2>&1; do
    if ! kill -0 "$DOCKERD_PID" 2>/dev/null; then
        printf '%s\n' "[ERROR] dockerd process died"
        printf '%s\n' "[ERROR] Last 50 lines of dockerd log:"
        tail -50 "$DOCKERD_LOG" 2>/dev/null || printf '%s\n' "(no log available)"
        exit 1
    fi
    sleep 1
    COUNTER=$((COUNTER + 1))
    if [ "$COUNTER" -ge "$TIMEOUT" ]; then
        printf '%s\n' "[ERROR] Docker failed to start within $TIMEOUT seconds"
        printf '%s\n' "[ERROR] Last 50 lines of dockerd log:"
        tail -50 "$DOCKERD_LOG" 2>/dev/null || printf '%s\n' "(no log available)"
        exit 1
    fi
done

printf '%s\n' "[OK] Docker ready on /var/run/docker-test.sock"
printf '%s\n' "[INFO] Inner Docker default runtime: $(docker info --format '{{.DefaultRuntime}}')"

# Execute the command passed to the container
exec "$@"
