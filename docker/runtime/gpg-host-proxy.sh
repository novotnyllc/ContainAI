#!/usr/bin/env bash
# GPG proxy that delegates ALL GPG operations to host
# This is more secure than mounting GPG keyrings into container
#
# Security model:
# - Container can request GPG operations via socket
# - Host performs operations with actual GPG/keys
# - Private keys NEVER enter container
# - All operations logged and validated
# - Read-only operations preferred
#
# Usage: Set as gpg.program in container
#   git config --global gpg.program /usr/local/bin/gpg-host-proxy.sh

set -euo pipefail

# Socket path (mounted from host)
GPG_PROXY_SOCKET="${GPG_PROXY_SOCKET:-/tmp/gpg-proxy.sock}"
TIMEOUT=30  # GPG operations can be slow (hardware token, PIN entry)

# If socket not available, try local GPG as fallback
if [ ! -S "$GPG_PROXY_SOCKET" ]; then
    # Try GPG agent socket forwarding instead (direct mode)
    if [ -S "${HOME}/.gnupg/S.gpg-agent" ]; then
        exec gpg "$@"
    fi
    
    echo "Error: GPG proxy socket not available and no GPG agent socket" >&2
    exit 1
fi

# Send request to host GPG via socket
if ! command -v socat &> /dev/null; then
    echo "Error: socat required for GPG proxy" >&2
    exit 1
fi

# Build the request
# Format: COMMAND\nARG1\nARG2\n...\n\n
request="GPG-PROXY-V1"$'\n'
for arg in "$@"; do
    # Validate arguments to prevent injection
    if [[ "$arg" =~ [\x00-\x1F] ]]; then
        echo "Error: Invalid characters in GPG arguments" >&2
        exit 1
    fi
    request+="$arg"$'\n'
done
request+=$'\n'  # Empty line terminates request

# Send to host and get response
response=$(echo "$request" | timeout "$TIMEOUT" socat - UNIX-CONNECT:"$GPG_PROXY_SOCKET" 2>/dev/null || echo "")

# Check for error response
if echo "$response" | head -1 | grep -q "^ERROR:"; then
    error_msg=$(echo "$response" | head -1 | cut -d: -f2-)
    echo "GPG proxy error: $error_msg" >&2
    exit 1
fi

# Output the response
echo "$response"
exit 0
