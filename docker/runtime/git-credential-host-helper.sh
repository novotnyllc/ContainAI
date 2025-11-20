#!/usr/bin/env bash
# Git credential helper that delegates to HOST via READ-ONLY socket proxy
# This is more secure than mounting credential files into the container
#
# Security model:
# - Container can ONLY READ credentials (get operation)
# - Container CANNOT modify host credentials (store/erase blocked)
# - All requests validated by host proxy
# - Follows principle of least privilege
#
# Why no write access?
# - Compromised container cannot poison host credentials
# - No legitimate reason for container to store/erase credentials
# - Reduces attack surface to absolute minimum
#
# Fallback chain if socket not available:
# 1. Socket proxy (preferred - most secure, read-only)
# 2. gh CLI for github.com (OAuth via read-only mount)
# 3. git-credential-store (if read-only mounted)
#
# Usage: Automatically configured by entrypoint.sh

set -euo pipefail

# Socket path (mounted from host)
CREDENTIAL_SOCKET="${CREDENTIAL_SOCKET:-/tmp/git-credential-proxy.sock}"
SOCKET_TIMEOUT=5  # seconds

# Read the credential request from stdin with size limit
read_credential_request() {
    local line
    local protocol=""
    local host=""
    local path=""
    local username=""
    local bytes=0
    local max_bytes=2048
    
    while IFS= read -r line; do
        [ -z "$line" ] && break
        
        bytes=$((bytes + ${#line}))
        if [ $bytes -gt $max_bytes ]; then
            echo "Error: Request too large" >&2
            return 1
        fi
        
        case "$line" in
            protocol=*) protocol="${line#protocol=}" ;;
            host=*) host="${line#host=}" ;;
            path=*) path="${line#path=}" ;;
            username=*) username="${line#username=}" ;;
        esac
    done
    
    echo "$protocol|$host|$path|$username"
}

# Validate credential field
validate_field() {
    local field="$1"
    local value="$2"
    
    case "$field" in
        protocol)
            [[ "$value" =~ ^(https?|git|ssh)$ ]] || return 1
            ;;
        host)
            # Strict hostname validation
            [[ "$value" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]{0,253}[a-zA-Z0-9])?$ ]] || return 1
            ;;
        path)
            # No control characters or null bytes
            [[ "$value" =~ ^[[:print:]]*$ ]] || return 1
            [ ${#value} -le 255 ] || return 1
            ;;
        username)
            # Alphanumeric, dots, underscores, @, hyphens
            [[ "$value" =~ ^[a-zA-Z0-9._@-]+$ ]] || return 1
            [ ${#value} -le 128 ] || return 1
            ;;
    esac
    return 0
}

# Send READ-ONLY request to socket proxy on host
query_socket_proxy() {
    local input="$1"
    
    # Check if socket exists and is accessible
    if [ ! -S "$CREDENTIAL_SOCKET" ]; then
        return 1
    fi
    
    # Require socat for secure communication
    if ! command -v socat &> /dev/null; then
        return 1
    fi
    
    # Send request with protocol header and timeout
    result=$(timeout "$SOCKET_TIMEOUT" socat - UNIX-CONNECT:"$CREDENTIAL_SOCKET" 2>/dev/null <<EOF || echo ""
GIT-CREDENTIAL-PROXY-V1
get
$input

EOF
)
    
    # Validate response format
    if [ -n "$result" ] && ! echo "$result" | grep -q "^ERROR:"; then
        echo "$result"
        return 0
    fi
    
    return 1
}

# Main logic
operation="${1:-get}"

case "$operation" in
    get)
        # Read and parse the credential request
        cred_info=$(read_credential_request) || exit 1
        
        protocol=$(echo "$cred_info" | cut -d'|' -f1)
        host=$(echo "$cred_info" | cut -d'|' -f2)
        path=$(echo "$cred_info" | cut -d'|' -f3)
        username=$(echo "$cred_info" | cut -d'|' -f4)
        
        # Validate all fields
        [ -n "$protocol" ] && validate_field "protocol" "$protocol" || exit 1
        [ -n "$host" ] && validate_field "host" "$host" || exit 1
        [ -n "$path" ] && validate_field "path" "$path" || true
        [ -n "$username" ] && validate_field "username" "$username" || true
        
        # Reconstruct validated input
        input="protocol=$protocol
host=$host"
        [ -n "$path" ] && input="$input
path=$path"
        [ -n "$username" ] && input="$input
username=$username"
        
        # PRIMARY: Try socket proxy to host (most secure, read-only)
        if result=$(query_socket_proxy "$input"); then
            echo "$result"
            exit 0
        fi
        
        # FALLBACK 1: Try gh CLI for github.com (OAuth via read-only mount)
        if [ "$host" = "github.com" ] && command -v gh &> /dev/null 2>&1; then
            if timeout 5 gh auth status &> /dev/null 2>&1; then
                result=$(echo "$input" | timeout 10 gh auth git-credential get 2>/dev/null || true)
                if [ -n "$result" ]; then
                    echo "$result"
                    exit 0
                fi
            fi
        fi
        
        # FALLBACK 2: Try git-credential-store ONLY if read-only mounted
        if [ -f "$HOME/.git-credentials" ] && command -v git-credential-store &> /dev/null 2>&1; then
            # Verify the file is read-only mounted (security check)
            if [ ! -w "$HOME/.git-credentials" ]; then
                result=$(echo "$input" | timeout 5 git-credential-store get 2>/dev/null || true)
                if [ -n "$result" ]; then
                    echo "$result"
                    exit 0
                fi
            fi
        fi
        
        # No credentials found - return empty (git will use SSH or fail)
        exit 1
        ;;
        
    store|erase)
        # SECURITY: Containers CANNOT modify host credentials
        # This prevents credential poisoning by compromised containers
        # Silently succeed to avoid breaking git operations
        exit 0
        ;;
        
    *)
        echo "Usage: $0 {get|store|erase}" >&2
        exit 1
        ;;
esac
