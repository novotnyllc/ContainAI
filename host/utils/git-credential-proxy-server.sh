#!/usr/bin/env bash
set -euo pipefail

DEFAULT_SOCKET="${HOME}/.config/coding-agents/git-credential.sock"
DEFAULT_LOG="${HOME}/.config/coding-agents/git-credential-proxy.log"
MAX_REQUEST_SIZE=4096
MAX_CONNECTIONS=10
CONNECTION_TIMEOUT=5

HANDLE_MODE=false
if [ "${1:-}" = "--handle-connection" ]; then
    HANDLE_MODE=true
    shift || true
else
    SOCKET_PATH="${1:-$DEFAULT_SOCKET}"
    LOG_FILE="${2:-$DEFAULT_LOG}"
    export SOCKET_PATH LOG_FILE
fi

SOCKET_PATH="${SOCKET_PATH:-$DEFAULT_SOCKET}"
LOG_FILE="${LOG_FILE:-$DEFAULT_LOG}"
CONNECTION_COUNT_FILE="${CONNECTION_COUNT_FILE:-/tmp/git-credential-proxy.$$}"
CURRENT_FIFO_IN=""
CURRENT_FIFO_OUT=""

log() {
    local msg
    msg=$(echo "$*" | tr -d '\000-\037' | head -c 500)
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $msg" >> "$LOG_FILE"
}

validate_field() {
    local field="$1"
    local value="$2"
    local max_len="${3:-255}"

    if [ ${#value} -gt "$max_len" ]; then
        return 1
    fi

    case "$field" in
        protocol)
            [[ "$value" =~ ^(https?|git|ssh)$ ]] || return 1
            ;;
        host)
            [[ "$value" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]{0,253}[a-zA-Z0-9])?$ ]] || return 1
            ;;
        path)
            [[ "$value" =~ ^[[:print:]]*$ ]] || return 1
            ;;
        username)
            [[ "$value" =~ ^[a-zA-Z0-9._@-]+$ ]] || return 1
            ;;
        *)
            return 1
            ;;
    esac

    return 0
}

handle_secure_request() {
    local request_id="$1"
    local protocol="" host="" path="" username=""
    local credential_data=""

    if ! timeout "$CONNECTION_TIMEOUT" bash -c '
        IFS= read -r -t 2 header || exit 1
        header=$(echo "$header" | tr -d "\r\n")
        [ "$header" = "GIT-CREDENTIAL-PROXY-V1" ] || exit 1

        IFS= read -r -t 2 operation || exit 1
        operation=$(echo "$operation" | tr -d "\r\n")
        [ "$operation" = "get" ] || exit 1

        total_bytes=0
        while IFS= read -r -t 2 line; do
            line=$(echo "$line" | tr -d "\r")
            [ -z "$line" ] && break
            total_bytes=$((total_bytes + ${#line}))
            [ $total_bytes -gt $MAX_REQUEST_SIZE ] && exit 1
            if [[ "$line" =~ ^([a-z]+)=(.+)$ ]]; then
                field="${BASH_REMATCH[1]}"
                value="${BASH_REMATCH[2]}"
                case "$field" in
                    protocol|host|path|username)
                        echo "$field=$value"
                        ;;
                esac
            fi
        done
    '; then
        log "Request $request_id: DENIED - Invalid protocol or timeout"
        echo "ERROR: Invalid request"
        return 1
    fi < <(cat)

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

    if [ -z "$protocol" ] || [ -z "$host" ]; then
        log "Request $request_id: DENIED - Missing required fields"
        return 1
    fi

    log "Request $request_id: GET host=$host protocol=$protocol user=${username:-<none>}"
    local result
    result=$(echo "$credential_data" | timeout 10 git credential fill 2>/dev/null || true)
    if [ -n "$result" ]; then
        if echo "$result" | grep -q "^password="; then
            echo "$result"
            log "Request $request_id: SUCCESS - Returned credentials for $host"
        else
            log "Request $request_id: FAILURE - Invalid credential format"
        fi
    else
        log "Request $request_id: FAILURE - No credentials found for $host"
    fi
}

handle_connection() {
    local request_id="$1"
    local count
    count=$(cat "$CONNECTION_COUNT_FILE" 2>/dev/null || echo "0")
    count=$((count + 1))
    echo "$count" > "$CONNECTION_COUNT_FILE"

    if [ "$count" -gt "$MAX_CONNECTIONS" ]; then
        log "Request $request_id: DENIED - Too many concurrent connections ($count)"
        echo "ERROR: Server busy"
        count=$((count - 1))
        echo "$count" > "$CONNECTION_COUNT_FILE"
        return 1
    fi

    handle_secure_request "$request_id" || true

    count=$((count - 1))
    echo "$count" > "$CONNECTION_COUNT_FILE"
}

start_socat_server() {
    log "Starting READ-ONLY git credential proxy server"
    log "Socket: $SOCKET_PATH (mode 600)"
    log "Max connections: $MAX_CONNECTIONS"
    log "Request timeout: ${CONNECTION_TIMEOUT}s"

    trap cleanup EXIT INT TERM
    socat \
        UNIX-LISTEN:"$SOCKET_PATH",mode=600,fork,max-children=$MAX_CONNECTIONS \
        EXEC:"$0 --handle-connection",nofork
}

start_nc_server() {
    echo "✅ Using netcat fallback for credential proxy (socat not available)"
    trap cleanup EXIT INT TERM

    while true; do
        rm -f "$SOCKET_PATH"

        local handler_pid status
        CURRENT_FIFO_IN=$(mktemp -u /tmp/git-cred-proxy-in.XXXXXX)
        CURRENT_FIFO_OUT=$(mktemp -u /tmp/git-cred-proxy-out.XXXXXX)
        mkfifo "$CURRENT_FIFO_IN" "$CURRENT_FIFO_OUT"

        "$0" --handle-connection <"$CURRENT_FIFO_IN" >"$CURRENT_FIFO_OUT" &
        handler_pid=$!

        if ! nc -lU "$SOCKET_PATH" <"$CURRENT_FIFO_OUT" >"$CURRENT_FIFO_IN"; then
            status=$?
            log "Netcat fallback exited with status $status"
        else
            status=0
        fi

        kill "$handler_pid" >/dev/null 2>&1 || true
        wait "$handler_pid" >/dev/null 2>&1 || true

        rm -f "$CURRENT_FIFO_IN" "$CURRENT_FIFO_OUT"
        CURRENT_FIFO_IN=""
        CURRENT_FIFO_OUT=""
        rm -f "$SOCKET_PATH"

        # Avoid tight loop if nc fails immediately
        if [ $status -ne 0 ]; then
            sleep 1
        fi
    done
}

cleanup() {
    [ -S "$SOCKET_PATH" ] && rm -f "$SOCKET_PATH"
    [ -f "$CONNECTION_COUNT_FILE" ] && rm -f "$CONNECTION_COUNT_FILE"
    [ -n "$CURRENT_FIFO_IN" ] && rm -f "$CURRENT_FIFO_IN"
    [ -n "$CURRENT_FIFO_OUT" ] && rm -f "$CURRENT_FIFO_OUT"
}

if $HANDLE_MODE; then
    SOCKET_PATH="${SOCKET_PATH:-$DEFAULT_SOCKET}"
    LOG_FILE="${LOG_FILE:-$DEFAULT_LOG}"
    CONNECTION_COUNT_FILE="${CONNECTION_COUNT_FILE:-/tmp/git-credential-proxy.$$}"
    handle_connection "$$-$(date +%s%N)"
    exit 0
fi

umask 077
mkdir -p "$(dirname "$SOCKET_PATH")"
mkdir -p "$(dirname "$LOG_FILE")"
rm -f "$SOCKET_PATH"
echo "0" > "$CONNECTION_COUNT_FILE"
export CONNECTION_COUNT_FILE

if command -v socat >/dev/null 2>&1; then
    start_socat_server
elif command -v nc >/dev/null 2>&1; then
    start_nc_server
else
    echo "❌ Error: Neither socat nor nc (netcat) found"
    echo "   Install socat: apt-get install socat (Ubuntu/Debian)"
    echo "              or: brew install socat (macOS)"
    exit 1
fi
