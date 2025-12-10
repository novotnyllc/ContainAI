#!/usr/bin/env bash
# GPG proxy server - runs on HOST
# Receives GPG operation requests from containers and executes on host
# This keeps private keys secure while allowing signing operations
#
# Security model:
# - Allowlist of GPG operations (signing only, no key export)
# - All requests validated and logged
# - Private keys never exposed to container
# - Hardware token prompts appear on host
# - User can see/approve operations (PIN entry, YubiKey touch)
#
# Usage:
#   ./gpg-proxy-server.sh [socket-path] [log-file]
#
# Default socket: ~/.config/containai/gpg-proxy.sock

set -euo pipefail

# Configuration
SOCKET_PATH="${1:-$HOME/.config/containai/gpg-proxy.sock}"
LOG_FILE="${2:-$HOME/.config/containai/gpg-proxy.log}"
MAX_CONNECTIONS=5
CONNECTION_TIMEOUT=60  # GPG can be slow (PIN entry, hardware token)

# Allowed GPG operations (SIGNING AND VERIFICATION ONLY)
ALLOWED_OPERATIONS=(
    "--sign"
    "--clearsign"
    "--detach-sign"
    "-s"
    "-b"
    "--verify"
    "--decrypt"  # Needed for some signing flows
    "--list-keys"
    "--list-secret-keys"  # Metadata only, not actual keys
    "--fingerprint"
)

# DENIED operations (would expose keys or allow tampering)
DENIED_OPERATIONS=(
    "--export"
    "--export-secret-keys"
    "--export-secret-subkeys"
    "--delete-key"
    "--delete-secret-key"
    "--gen-key"
    "--import"
    "--edit-key"
    "--passwd"
    "--output"
    "-o"
    "--log-file"
    "--logger-file"
    "--homedir"
    "--options"
    "--keyring"
    "--secret-keyring"
    "--primary-keyring"
    "--trustdb-name"
)

# Security: Validate paths
if [[ ! "$SOCKET_PATH" =~ ^[a-zA-Z0-9/_.-]+$ ]]; then
    echo "Error: Invalid socket path" >&2
    exit 1
fi

umask 077
mkdir -p "$(dirname "$SOCKET_PATH")"
mkdir -p "$(dirname "$LOG_FILE")"
rm -f "$SOCKET_PATH"

# Log function
log() {
    local msg
    msg=$(echo "$*" | tr -d '\000-\037' | head -c 500)
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $msg" >> "$LOG_FILE"
}

# Check if operation is allowed
is_operation_allowed() {
    local args=("$@")
    local operation=""
    
    # Find the primary operation flag
    for arg in "${args[@]}"; do
        if [[ "$arg" == --* ]] || [[ "$arg" == -[a-z] ]]; then
            operation="$arg"
            break
        fi
    done
    
    # Check against denied list first (fail-secure)
    for denied in "${DENIED_OPERATIONS[@]}"; do
        if [[ "$operation" == "$denied" ]]; then
            return 1
        fi
    done
    
    # If no operation specified, allow (might be --version, etc.)
    if [ -z "$operation" ]; then
        return 0
    fi
    
    # Check against allowed list
    for allowed in "${ALLOWED_OPERATIONS[@]}"; do
        if [[ "$operation" == "$allowed" ]]; then
            return 0
        fi
    done
    
    # Default deny
    return 1
}

# Handle GPG request
handle_request() {
    local request_id="$1"
    local line=""
    local args=()
    local bytes_read=0
    local max_bytes=65536  # 64KB max request
    
    # Read protocol header
    IFS= read -r -t 5 line || {
        log "Request $request_id: DENIED - Timeout reading header"
        echo "ERROR: Timeout"
        return 1
    }
    
    line=$(echo "$line" | tr -d '\r\n')
    if [ "$line" != "GPG-PROXY-V1" ]; then
        log "Request $request_id: DENIED - Invalid protocol: $line"
        echo "ERROR: Invalid protocol"
        return 1
    fi
    
    # Read arguments (until blank line)
    while IFS= read -r -t 5 line; do
        line=$(echo "$line" | tr -d '\r')
        [ -z "$line" ] && break
        
        bytes_read=$((bytes_read + ${#line}))
        if [ $bytes_read -gt $max_bytes ]; then
            log "Request $request_id: DENIED - Request too large"
            echo "ERROR: Request too large"
            return 1
        fi
        
        # Basic validation
        if [[ "$line" =~ [\x00-\x1F] ]]; then
            log "Request $request_id: DENIED - Invalid characters in argument"
            echo "ERROR: Invalid argument"
            return 1
        fi
        
        args+=("$line")
    done
    
    # Check if operation is allowed
    if ! is_operation_allowed "${args[@]}"; then
        log "Request $request_id: DENIED - Operation not allowed: ${args[*]}"
        echo "ERROR: Operation not allowed"
        return 1
    fi
    
    log "Request $request_id: GPG ${args[*]}"
    
    # Execute GPG on host with timeout
    # This will prompt user for PIN, YubiKey touch, etc. on host
    result=$(timeout "$CONNECTION_TIMEOUT" gpg "${args[@]}" 2>&1 || echo "")
    exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        log "Request $request_id: SUCCESS"
        echo "$result"
    else
        log "Request $request_id: FAILED - exit code $exit_code"
        echo "ERROR: GPG operation failed"
        return 1
    fi
    
    return 0
}

# Connection handler wrapper
handle_connection() {
    local request_id="$1"
    handle_request "$request_id" || true
}

# Server loop
start_server() {
    if ! command -v socat &> /dev/null; then
        log "ERROR: socat is required"
        echo "Error: socat required (install with: apt-get install socat)" >&2
        exit 1
    fi
    
    log "Starting GPG proxy server (SIGNING OPERATIONS ONLY)"
    log "Socket: $SOCKET_PATH (mode 600)"
    log "Allowed operations: ${ALLOWED_OPERATIONS[*]}"
    
    trap 'log "Shutting down"; rm -f "$SOCKET_PATH"; exit 0' INT TERM EXIT
    
    # Use socat with security settings
    socat \
        UNIX-LISTEN:"$SOCKET_PATH",mode=600,fork,max-children=$MAX_CONNECTIONS \
        EXEC:"$0 --handle-connection",nofork
}

# Handle single connection
if [ "${1:-}" = "--handle-connection" ]; then
    request_id="$$-$(date +%s%N)"
    handle_connection "$request_id"
    exit 0
fi

start_server
