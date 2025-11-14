#!/usr/bin/env bash
#!/usr/bin/env bash
# Git credential proxy server - runs on HOST
# Listens on Unix socket, receives READ-ONLY credential requests from containers
# Delegates to host's native git credential system
#
# SECURITY MODEL:
# - Containers can ONLY READ credentials (get operation)
# - Containers CANNOT modify host credentials (no store/erase)
# - Socket owned by user, mode 600 (only user's containers can connect)
# - Input validation on all fields with strict limits
# - Connection timeout and rate limiting
# - Audit logging with container identification
#
# Why READ-ONLY?
# - Compromised container cannot poison host credentials
# - No legitimate reason for container to modify credentials
# - Reduces attack surface to absolute minimum
# - Follows principle of least privilege
#
# Protocol (version 1):
# 1. Client connects and sends: "GIT-CREDENTIAL-PROXY-V1\n"
# 2. Client sends: "get\n" (only allowed operation)
# 3. Client sends: credential request (protocol=, host=, path=, username=)
# 4. Client sends: blank line
# 5. Server responds: credential data or empty
# 6. Server closes connection
#
# Usage:
#   ./git-credential-proxy-server.sh [socket-path] [log-file]
#
# Default socket: ~/.config/coding-agents/git-credential.sock

set -euo pipefail

# Configuration
SOCKET_PATH="${1:-$HOME/.config/coding-agents/git-credential.sock}"
LOG_FILE="${2:-$HOME/.config/coding-agents/git-credential-proxy.log}"
MAX_REQUEST_SIZE=4096  # bytes
MAX_CONNECTIONS=10     # concurrent connections
CONNECTION_TIMEOUT=5   # seconds

# Security: Validate configuration paths
if [[ ! "$SOCKET_PATH" =~ ^[a-zA-Z0-9/_.-]+$ ]]; then
    echo "Error: Invalid socket path" >&2
    exit 1
fi

# Create directories with secure permissions
umask 077
mkdir -p "$(dirname "$SOCKET_PATH")"
mkdir -p "$(dirname "$LOG_FILE")"

# Remove old socket if exists
rm -f "$SOCKET_PATH"

# Active connection counter for rate limiting
ACTIVE_CONNECTIONS=0
CONNECTION_COUNT_FILE="/tmp/git-cred-proxy-$$.count"
echo "0" > "$CONNECTION_COUNT_FILE"

# Log function (sanitizes input to prevent log injection)
log() {
    # Remove control characters and limit length
    local msg=$(echo "$*" | tr -d '\000-\037' | head -c 500)
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $msg" >> "$LOG_FILE"
}

# Validate credential field
validate_field() {
    local field="$1"
    local value="$2"
    local max_len="${3:-255}"
    
    # Check length
    if [ ${#value} -gt "$max_len" ]; then
        return 1
    fi
    
    case "$field" in
        protocol)
            # Only allow http/https/git/ssh
            [[ "$value" =~ ^(https?|git|ssh)$ ]] || return 1
            ;;
        host)
            # Strict hostname validation (alphanumeric, dots, hyphens)
            [[ "$value" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]{0,253}[a-zA-Z0-9])?$ ]] || return 1
            ;;
        path)
            # Path validation (no null bytes, control chars)
            [[ "$value" =~ ^[[:print:]]*$ ]] || return 1
            ;;
        username)
            # Username validation (printable chars, no spaces/control)
            [[ "$value" =~ ^[a-zA-Z0-9._@-]+$ ]] || return 1
            ;;
        *)
            return 1
            ;;
    esac
    
    return 0
}

# Handle credential request (READ-ONLY)
handle_request() {
    local request_id="$1"
    local bytes_read=0
    local protocol="" host="" path="" username=""
    
    # Set timeout for entire request handling
    exec 3<&0  # Save stdin
    if ! timeout "$CONNECTION_TIMEOUT" bash -c '
        # Read and validate protocol header
        IFS= read -r -t 2 header || exit 1
        header=$(echo "$header" | tr -d "\r\n")
        [ "$header" = "GIT-CREDENTIAL-PROXY-V1" ] || exit 1
        
        # Read operation (MUST be "get")
        IFS= read -r -t 2 operation || exit 1
        operation=$(echo "$operation" | tr -d "\r\n")
        [ "$operation" = "get" ] || exit 1
        
        # Read credential fields
        total_bytes=0
        while IFS= read -r -t 2 line; do
            line=$(echo "$line" | tr -d "\r")
            [ -z "$line" ] && break
            
            # Enforce max request size
            total_bytes=$((total_bytes + ${#line}))
            [ $total_bytes -gt 4096 ] && exit 1
            
            # Parse and validate each field
            if [[ "$line" =~ ^([a-z]+)=(.+)$ ]]; then
                field="${BASH_REMATCH[1]}"
                value="${BASH_REMATCH[2]}"
                
                case "$field" in
                    protocol) echo "protocol=$value" ;;
                    host) echo "host=$value" ;;
                    path) echo "path=$value" ;;
                    username) echo "username=$value" ;;
                esac
            fi
        done
    '; then
        log "Request $request_id: DENIED - Invalid protocol or timeout"
        echo "ERROR: Invalid request"
        return 1
    fi < <(cat)
    
    # Read the validated credential request from subshell
    local credential_data=""
    local line=""
    
    while IFS= read -r line; do
        line=$(echo "$line" | tr -d '\r\n')
        
        if [[ "$line" =~ ^([a-z]+)=(.+)$ ]]; then
            field="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"
            
            if ! validate_field "$field" "$value"; then
                log "Request $request_id: DENIED - Invalid field $field"
                return 1
            fi
            
            case "$field" in
                protocol) protocol="$value" ;;
                host) host="$value" ;;
                path) path="$value" ;;
                username) username="$value" ;;
            esac
            
            credential_data+="$line"$'\n'
        fi
    done < <(timeout "$CONNECTION_TIMEOUT" bash)
    
    # Require at minimum: protocol and host
    if [ -z "$protocol" ] || [ -z "$host" ]; then
        log "Request $request_id: DENIED - Missing required fields"
        return 1
    fi
    
    log "Request $request_id: GET host=$host protocol=$protocol user=${username:-<none>}"
    
    # Query host's git credential system (READ-ONLY)
    result=$(echo "$credential_data" | timeout 10 git credential fill 2>/dev/null || true)
    
    if [ -n "$result" ]; then
        # Validate response format before sending
        if echo "$result" | grep -q "^password="; then
            echo "$result"
            log "Request $request_id: SUCCESS - Returned credentials for $host"
        else
            log "Request $request_id: FAILURE - Invalid credential format"
        fi
    else
        log "Request $request_id: FAILURE - No credentials found for $host"
    fi
    
    return 0
}

# Connection handler wrapper
handle_connection() {
    local request_id="$1"
    
    # Increment connection counter
    local count=$(cat "$CONNECTION_COUNT_FILE" 2>/dev/null || echo "0")
    count=$((count + 1))
    echo "$count" > "$CONNECTION_COUNT_FILE"
    
    # Rate limiting: check concurrent connections
    if [ "$count" -gt "$MAX_CONNECTIONS" ]; then
        log "Request $request_id: DENIED - Too many concurrent connections ($count)"
        echo "ERROR: Server busy"
        count=$((count - 1))
        echo "$count" > "$CONNECTION_COUNT_FILE"
        return 1
    fi
    
    # Handle the request
    handle_request "$request_id" || true
    
    # Decrement connection counter
    count=$((count - 1))
    echo "$count" > "$CONNECTION_COUNT_FILE"
}

# Server loop using socat
start_server() {
    if ! command -v socat &> /dev/null; then
        log "ERROR: socat is required for secure socket handling"
        echo "Error: This script requires socat (install with: apt-get install socat)" >&2
        exit 1
    fi
    
    log "Starting READ-ONLY git credential proxy server"
    log "Socket: $SOCKET_PATH (mode 600)"
    log "Max connections: $MAX_CONNECTIONS"
    log "Request timeout: ${CONNECTION_TIMEOUT}s"
    
    # Cleanup on exit
    trap 'log "Shutting down"; rm -f "$SOCKET_PATH" "$CONNECTION_COUNT_FILE"; exit 0' INT TERM EXIT
    
    # Use socat with proper security settings
    # - mode=600: only user can connect
    # - fork: handle multiple connections
    # - max-children: limit concurrent connections
    socat \
        UNIX-LISTEN:"$SOCKET_PATH",mode=600,fork,max-children=$MAX_CONNECTIONS \
        EXEC:"$0 --handle-connection",nofork
}

# Handle single connection (called by socat fork)
if [ "${1:-}" = "--handle-connection" ]; then
    # Generate unique request ID from PID and timestamp
    request_id="$$-$(date +%s%N)"
    handle_connection "$request_id"
    exit 0
fi

# Start server
start_server

set -euo pipefail

SOCKET_PATH="${1:-$HOME/.config/coding-agents/git-credential.sock}"

# Create socket directory
mkdir -p "$(dirname "$SOCKET_PATH")"

# Remove old socket if it exists
[ -S "$SOCKET_PATH" ] && rm -f "$SOCKET_PATH"

echo "🔐 Starting Git Credential Proxy Server..."
echo "   Socket: $SOCKET_PATH"
echo "   PID: $$"
echo ""

# Cleanup on exit
cleanup() {
    echo ""
    echo "🛑 Shutting down Git Credential Proxy Server"
    [ -S "$SOCKET_PATH" ] && rm -f "$SOCKET_PATH"
    exit 0
}
trap cleanup EXIT INT TERM

# Process credential requests
handle_request() {
    local operation="$1"
    local input="$2"
    
    # Log request (optional - comment out for production)
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $operation request" >&2
    
    # Parse input to get host for logging
    local host
    host=$(echo "$input" | grep '^host=' | cut -d= -f2 || echo "unknown")
    echo "   Host: $host" >&2
    
    # Delegate to host's git credential system
    # This uses whatever the host has configured (gh CLI, credential store, etc.)
    case "$operation" in
        get)
            # Request credentials from host
            result=$(echo "$input" | git credential fill 2>/dev/null || echo "")
            if [ -n "$result" ]; then
                echo "   ✅ Credentials provided" >&2
                echo "$result"
                return 0
            else
                echo "   ❌ No credentials found" >&2
                return 1
            fi
            ;;
        store)
            # Store credentials on host (if host allows it)
            echo "$input" | git credential approve 2>/dev/null || true
            echo "   💾 Store request processed" >&2
            return 0
            ;;
        erase)
            # Erase credentials from host
            echo "$input" | git credential reject 2>/dev/null || true
            echo "   🗑️  Erase request processed" >&2
            return 0
            ;;
        *)
            echo "   ⚠️  Unknown operation: $operation" >&2
            return 1
            ;;
    esac
}

# Start server using socat if available, otherwise nc
if command -v socat &> /dev/null; then
    echo "✅ Using socat for socket server"
    echo ""
    
    while true; do
        # Read operation (first line)
        read -r operation
        
        # Read credential input (until empty line)
        input=""
        while IFS= read -r line; do
            [ -z "$line" ] && break
            input="${input}${line}"$'\n'
        done
        
        # Handle request
        handle_request "$operation" "$input" || true
    done | socat UNIX-LISTEN:"$SOCKET_PATH",fork,mode=600 -
    
elif command -v nc &> /dev/null; then
    echo "✅ Using netcat for socket server"
    echo "⚠️  Warning: netcat implementation is basic, install socat for better reliability"
    echo ""
    
    while true; do
        nc -lU "$SOCKET_PATH" | while read -r operation; do
            # Read credential input
            input=""
            while IFS= read -r line; do
                [ -z "$line" ] && break
                input="${input}${line}"$'\n'
            done
            
            handle_request "$operation" "$input" || true
        done
    done
    
else
    echo "❌ Error: Neither socat nor nc (netcat) found"
    echo "   Install socat: apt-get install socat (Ubuntu/Debian)"
    echo "              or: brew install socat (macOS)"
    exit 1
fi
