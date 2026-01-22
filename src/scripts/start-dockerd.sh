#!/bin/bash
# Start Docker daemon with Sysbox services for testing
# Used by Dockerfile.test as the container entrypoint
set -e

# Start Sysbox services
echo "[INFO] Starting sysbox-mgr..."
sysbox-mgr &
SYSBOX_MGR_PID=$!

echo "[INFO] Starting sysbox-fs..."
sysbox-fs &
SYSBOX_FS_PID=$!

# Wait for Sysbox to be ready (poll for socket, max 10 seconds)
echo "[INFO] Waiting for Sysbox services..."
SYSBOX_TIMEOUT=10
SYSBOX_COUNTER=0
while [ ! -S /run/sysbox/sysmgr.sock ]; do
    if ! kill -0 $SYSBOX_MGR_PID 2>/dev/null; then
        echo "[ERROR] sysbox-mgr process died"
        exit 1
    fi
    sleep 1
    SYSBOX_COUNTER=$((SYSBOX_COUNTER + 1))
    if [ $SYSBOX_COUNTER -ge $SYSBOX_TIMEOUT ]; then
        echo "[ERROR] Sysbox failed to create socket within $SYSBOX_TIMEOUT seconds"
        exit 1
    fi
done

# Verify both Sysbox services are still running
if ! kill -0 $SYSBOX_MGR_PID 2>/dev/null; then
    echo "[ERROR] sysbox-mgr failed to start"
    exit 1
fi
if ! kill -0 $SYSBOX_FS_PID 2>/dev/null; then
    echo "[ERROR] sysbox-fs failed to start"
    exit 1
fi

# Start Docker daemon (hosts configured in daemon.json; do NOT use -H flag to avoid conflict)
echo "[INFO] Starting dockerd on /var/run/docker-test.sock..."
dockerd --config-file /etc/docker/daemon.json &
DOCKERD_PID=$!

# Wait for Docker to be ready (max 30 seconds)
echo "[INFO] Waiting for Docker to be ready..."
TIMEOUT=30
COUNTER=0
while ! docker info >/dev/null 2>&1; do
    if ! kill -0 $DOCKERD_PID 2>/dev/null; then
        echo "[ERROR] dockerd process died"
        exit 1
    fi
    sleep 1
    COUNTER=$((COUNTER + 1))
    if [ $COUNTER -ge $TIMEOUT ]; then
        echo "[ERROR] Docker failed to start within $TIMEOUT seconds"
        exit 1
    fi
done

echo "[OK] Docker + Sysbox ready on /var/run/docker-test.sock"
echo "[INFO] Sysbox runtime available as: --runtime=sysbox-runc"

# Execute the command passed to the container
exec "$@"
