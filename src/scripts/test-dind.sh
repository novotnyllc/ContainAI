#!/bin/bash
# Test that Docker + Sysbox is working correctly
# Run after start-dockerd.sh has initialized the environment
set -e

echo "=== Docker Info ==="
docker info

echo ""
echo "=== Available Runtimes ==="
docker info --format "{{json .Runtimes}}" | jq .

echo ""
echo "=== Test: Run container with default runtime ==="
docker run --rm alpine:3.20 echo "Default runtime works"

echo ""
echo "=== Test: Run container with Sysbox runtime ==="
docker run --rm --runtime=sysbox-runc alpine:3.20 echo "Sysbox runtime works"

echo ""
echo "=== Test: Build simple image ==="
docker build -t test-build - <<EOF
FROM alpine:3.20
RUN echo "Build test"
EOF
docker rmi test-build

echo ""
echo "[OK] All Docker + Sysbox tests passed"
