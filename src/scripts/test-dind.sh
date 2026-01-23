#!/bin/bash
# Test that Docker-in-Docker is working correctly
# Run after start-dockerd.sh has initialized the environment
#
# This test runs inside a sysbox system container. The inner Docker uses
# runc (default runtime) - all DinD isolation is provided by the outer
# sysbox container runtime.
set -euo pipefail

printf '%s\n' "=== Docker Info ==="
docker info

printf '\n'
printf '%s\n' "=== Test: Run container with default runtime ==="
docker run --rm alpine:3.20 echo "Docker run works"

printf '\n'
printf '%s\n' "=== Test: Build simple image ==="
docker build -t test-build - <<EOF
FROM alpine:3.20
RUN echo "Build test"
EOF
docker rmi test-build

printf '\n'
printf '%s\n' "[OK] All Docker-in-Docker tests passed"
printf '%s\n' ""
printf '%s\n' "This container is running inside a sysbox system container."
printf '%s\n' "The host sysbox runtime provides DinD capability without --privileged."
printf '%s\n' "Inner Docker uses runc; sysbox isolation comes from the outer container."
