#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════
# start.sh - ContainAI postStartCommand (runs every container start)
#
# Responsibilities:
# - Re-verify sysbox (in case container was restarted on different host)
# - Start sshd if enabled (with idempotency)
# - Start dockerd for DinD (with retry and idempotency)
# ══════════════════════════════════════════════════════════════════════
set -euo pipefail

# Source configuration from install.sh
# shellcheck source=/dev/null
source /usr/local/share/containai/config

# Re-verify sysbox first (in case container was restarted on different host)
/usr/local/share/containai/verify-sysbox.sh || exit 1

# ──────────────────────────────────────────────────────────────────────
# Start sshd if enabled (devcontainer-style, not systemd)
# Port is dynamically allocated by the wrapper via CONTAINAI_SSH_PORT env var
# ──────────────────────────────────────────────────────────────────────
start_sshd() {
    if [[ "$ENABLE_SSH" != "true" ]]; then
        return 0
    fi

    if ! command -v sshd &>/dev/null; then
        printf 'Warning: sshd not installed\n' >&2
        return 0
    fi

    # Generate host keys if missing
    if [[ ! -f /etc/ssh/ssh_host_rsa_key ]]; then
        ssh-keygen -A
    fi

    # Get SSH port from env var (set by cai-docker wrapper) or use default
    local SSH_PORT="${CONTAINAI_SSH_PORT:-2322}"

    # Idempotency: check if already running
    local PIDFILE="/tmp/containai-sshd.pid"
    if [[ -f "$PIDFILE" ]]; then
        local pid
        pid=$(cat "$PIDFILE")
        if kill -0 "$pid" 2>/dev/null; then
            printf '✓ sshd already running on port %s (pid %s)\n' "$SSH_PORT" "$pid"
            return 0
        fi
        # Stale pidfile
        rm -f "$PIDFILE"
    fi

    # Start sshd on configured port
    /usr/sbin/sshd -p "$SSH_PORT" -o "PidFile=$PIDFILE"
    printf '✓ sshd started on port %s\n' "$SSH_PORT"
}

# ──────────────────────────────────────────────────────────────────────
# Start dockerd for DinD (if Docker installed)
# Sysbox provides the isolation, no --privileged needed
# ──────────────────────────────────────────────────────────────────────
start_dockerd() {
    if ! command -v dockerd &>/dev/null; then
        return 0
    fi

    local PIDFILE="/var/run/docker.pid"
    local LOGFILE="/var/log/containai-dockerd.log"
    local RETRIES=30

    # Idempotency: check if already running
    if [[ -f "$PIDFILE" ]]; then
        local pid
        pid=$(cat "$PIDFILE")
        if kill -0 "$pid" 2>/dev/null; then
            printf '✓ dockerd already running (pid %s)\n' "$pid"
            return 0
        fi
        # Stale pidfile
        rm -f "$PIDFILE"
    fi

    # Also check if docker socket works
    if docker info &>/dev/null; then
        printf '✓ dockerd already running (socket active)\n'
        return 0
    fi

    # Start dockerd in background
    printf 'Starting dockerd...\n'
    nohup dockerd --pidfile="$PIDFILE" > "$LOGFILE" 2>&1 &

    # Wait for socket to become available
    local i=0
    while [[ $i -lt $RETRIES ]]; do
        if docker info &>/dev/null; then
            printf '✓ dockerd started (DinD ready)\n'
            return 0
        fi
        sleep 1
        ((i++))
    done

    printf '✗ dockerd failed to start (see %s)\n' "$LOGFILE" >&2
    return 1
}

# ──────────────────────────────────────────────────────────────────────
# Main execution
# ──────────────────────────────────────────────────────────────────────
start_sshd
start_dockerd || printf 'Warning: DinD not available\n' >&2

printf '✓ ContainAI devcontainer ready\n'
