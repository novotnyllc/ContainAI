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

CONFIG_FILE="/usr/local/share/containai/config.json"

# Parse configuration from JSON (SECURITY: don't source untrusted data)
if [[ ! -f "$CONFIG_FILE" ]]; then
    printf 'ERROR: Configuration file not found: %s\n' "$CONFIG_FILE" >&2
    exit 1
fi

# Read config values using jq
ENABLE_SSH=$(jq -r '.enable_ssh // true' "$CONFIG_FILE")

# Re-verify sysbox first (in case container was restarted on different host)
/usr/local/share/containai/verify-sysbox.sh || exit 1

# ──────────────────────────────────────────────────────────────────────
# Check if any process is listening on a port (cross-platform)
# ──────────────────────────────────────────────────────────────────────
is_port_in_use() {
    local port="$1"
    if command -v ss &>/dev/null; then
        ss -tln 2>/dev/null | grep -qE ":${port}[[:space:]]" && return 0
    elif command -v lsof &>/dev/null; then
        lsof -iTCP:"$port" -sTCP:LISTEN &>/dev/null && return 0
    elif command -v netstat &>/dev/null; then
        netstat -tln 2>/dev/null | grep -qE ":${port}[[:space:]]" && return 0
    fi
    return 1
}

# ──────────────────────────────────────────────────────────────────────
# Check if sshd is running via pidfile validation
# Returns 0 if sshd is confirmed running, 1 otherwise
# ──────────────────────────────────────────────────────────────────────
is_sshd_running_from_pidfile() {
    local pidfile="$1"
    local pid

    # Check pidfile exists and is readable
    [[ -f "$pidfile" ]] || return 1

    # Try to read pid (may need sudo if root-owned)
    if [[ -r "$pidfile" ]]; then
        pid=$(cat "$pidfile" 2>/dev/null) || return 1
    elif command -v sudo &>/dev/null && sudo -n true 2>/dev/null; then
        pid=$(sudo cat "$pidfile" 2>/dev/null) || return 1
    else
        return 1
    fi

    # Validate pid is numeric
    [[ "$pid" =~ ^[0-9]+$ ]] || return 1

    # Check process is running and is sshd
    if [[ -d "/proc/$pid" ]]; then
        # Linux: check /proc/$pid/comm or cmdline
        local comm
        comm=$(cat "/proc/$pid/comm" 2>/dev/null || true)
        [[ "$comm" == "sshd" ]] && return 0
    fi

    # Fallback: just check if process exists
    kill -0 "$pid" 2>/dev/null && return 0

    return 1
}

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

    # Get SSH port from env var (set by cai-docker wrapper) or use default
    local SSH_PORT="${CONTAINAI_SSH_PORT:-2322}"
    # Use /var/run/sshd for pidfile (proper location, consistent with sshd conventions)
    local PIDFILE="/var/run/sshd/containai-sshd.pid"

    # Idempotency check 1: Validate pidfile first (works for both root and non-root)
    if is_sshd_running_from_pidfile "$PIDFILE"; then
        printf '✓ sshd already running on port %s (validated via pidfile)\n' "$SSH_PORT"
        return 0
    fi

    # Idempotency check 2: Check if port is in use
    if is_port_in_use "$SSH_PORT"; then
        # Port is in use - assume it's sshd from a previous run (graceful degradation)
        # We can't reliably determine process name without root on some systems
        printf '✓ sshd appears to be running on port %s (port in use)\n' "$SSH_PORT"
        return 0
    fi

    # Clean up stale pidfile if it exists but sshd isn't running
    if [[ -f "$PIDFILE" ]]; then
        if [[ -w "$PIDFILE" ]]; then
            rm -f "$PIDFILE" 2>/dev/null || true
        elif command -v sudo &>/dev/null && sudo -n true 2>/dev/null; then
            sudo rm -f "$PIDFILE" 2>/dev/null || true
        fi
    fi

    # Check if running as root (sshd requires root to bind privileged ports and access keys)
    if [[ "$(id -u)" -ne 0 ]]; then
        # Try sudo if available
        if command -v sudo &>/dev/null && sudo -n true 2>/dev/null; then
            printf 'Running sshd setup as root via sudo...\n'
            sudo mkdir -p /var/run/sshd
            sudo chmod 755 /var/run/sshd
            [[ -f /etc/ssh/ssh_host_rsa_key ]] || sudo ssh-keygen -A
            sudo /usr/sbin/sshd -p "$SSH_PORT" -o "PidFile=$PIDFILE"
            printf '✓ sshd started on port %s (via sudo)\n' "$SSH_PORT"
            return 0
        else
            # SSH was requested but cannot be started - this is an error condition
            printf '╔═══════════════════════════════════════════════════════════════════╗\n' >&2
            printf '║  ⚠️  SSH NOT AVAILABLE                                             ║\n' >&2
            printf '║                                                                   ║\n' >&2
            printf '║  sshd requires root privileges but:                               ║\n' >&2
            printf '║  - Container is running as non-root user                          ║\n' >&2
            printf '║  - Passwordless sudo is not available                             ║\n' >&2
            printf '║                                                                   ║\n' >&2
            printf '║  To fix: Run container as root or configure passwordless sudo     ║\n' >&2
            printf '╚═══════════════════════════════════════════════════════════════════╝\n' >&2
            return 1
        fi
    fi

    # Running as root - ensure runtime directory exists with correct permissions
    mkdir -p /var/run/sshd
    chmod 755 /var/run/sshd

    # Generate host keys if missing
    if [[ ! -f /etc/ssh/ssh_host_rsa_key ]]; then
        ssh-keygen -A
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
        i=$((i + 1))
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
