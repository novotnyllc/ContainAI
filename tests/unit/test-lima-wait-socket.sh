#!/usr/bin/env bash
# ==============================================================================
# Unit tests for _cai_lima_wait_socket behavior
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SETUP_LIB="$PROJECT_ROOT/src/lib/setup.sh"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

log_pass() {
    printf 'PASS: %s\n' "$1"
    ((TESTS_PASSED++)) || true
}

log_fail() {
    printf 'FAIL: %s\n' "$1" >&2
    ((TESTS_FAILED++)) || true
}

run_test() {
    local name="$1"
    local func="$2"
    ((TESTS_RUN++)) || true
    if "$func"; then
        log_pass "$name"
    else
        log_fail "$name"
    fi
}

# Source setup.sh for _cai_lima_wait_socket
# shellcheck source=/dev/null
source "$SETUP_LIB"

# Stub logging helpers used by _cai_lima_wait_socket
_cai_step() { :; }
_cai_ok() { :; }
_cai_warn() { :; }
_cai_error() { :; }
_cai_info() { :; }

test_wait_socket_repairs_on_eof() {
    local tmpdir socket_path
    tmpdir=$(mktemp -d)
    socket_path="$tmpdir/docker.sock"

    # Create a dummy unix socket file so -S checks pass
    python3 - <<'PY' "$socket_path"
import socket
import sys
path = sys.argv[1]
sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
sock.bind(path)
sock.listen(1)
sock.close()
PY

    _CAI_LIMA_SOCKET_PATH="$socket_path"
    _CAI_LIMA_VM_NAME="containai-docker"
    CONTAINAI_LIMA_EOF_REPAIR_AFTER=0

    local calls_file="$tmpdir/calls"
    printf '0' >"$calls_file"
    docker() {
        if [[ "${1:-}" == "info" ]]; then
            local calls
            calls=$(cat "$calls_file" 2>/dev/null || printf '0')
            calls=$((calls + 1))
            printf '%s' "$calls" >"$calls_file"
            if [[ $calls -lt 2 ]]; then
                printf '%s\n' "error during connect: EOF" >&2
                return 1
            fi
            return 0
        fi
        return 0
    }

    REPAIR_CALLED=0
    _cai_lima_repair_docker_access() {
        REPAIR_CALLED=1
        return 0
    }

    _cai_lima_wait_socket 3 false
    [[ "${REPAIR_CALLED}" -eq 1 ]]
}

run_test "EOF triggers repair path" test_wait_socket_repairs_on_eof

printf 'Tests run: %s\n' "$TESTS_RUN"
printf 'Passed:    %s\n' "$TESTS_PASSED"
printf 'Failed:    %s\n' "$TESTS_FAILED"

if [[ "$TESTS_FAILED" -gt 0 ]]; then
    exit 1
fi
