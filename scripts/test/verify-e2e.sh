#!/bin/bash
set -euo pipefail

CONFIGURATION="Debug"

while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--configuration)
            CONFIGURATION="$2"
            shift 2
            ;;
        *)
            echo "Unknown argument: $1"
            exit 1
            ;;
    esac
done

REPO_ROOT=$(git rev-parse --show-toplevel)
TEMP_DIR=$(mktemp -d)
SOCKET_PATH="$TEMP_DIR/audit.sock"
LOG_DIR="$TEMP_DIR/logs"
mkdir -p "$LOG_DIR"

cleanup() {
    echo "Cleaning up..."
    if [ -n "${HOST_PID:-}" ]; then
        kill $HOST_PID || true
    fi
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

echo "Building Rust shim ($CONFIGURATION)..."
cd "$REPO_ROOT/src/audit-shim"
if [ "$CONFIGURATION" == "Release" ]; then
    cargo build --release
    SHIM_PATH="$REPO_ROOT/src/target/release/libaudit_shim.so"
else
    cargo build
    SHIM_PATH="$REPO_ROOT/src/target/debug/libaudit_shim.so"
fi

if [ ! -f "$SHIM_PATH" ]; then
    echo "Error: Shim not found at $SHIM_PATH"
    exit 1
fi

echo "Building C# Host ($CONFIGURATION)..."
cd "$REPO_ROOT"
dotnet publish src/ContainAI.Host/ContainAI.Host.csproj -c "$CONFIGURATION"

# Convert configuration to lower case for path
CONFIG_LOWER=$(echo "$CONFIGURATION" | tr '[:upper:]' '[:lower:]')
HOST_PATH="$REPO_ROOT/artifacts/publish/ContainAI.Host/$CONFIG_LOWER/containai"

if [ ! -f "$HOST_PATH" ]; then
    echo "Error: Host binary not found at $HOST_PATH"
    exit 1
fi

echo "Starting Host..."
export CONTAINAI_SOCKET_PATH="$SOCKET_PATH"
"$HOST_PATH" --socket-path "$SOCKET_PATH" --log-dir "$LOG_DIR" &
HOST_PID=$!

# Wait for socket
echo "Waiting for socket..."
for i in {1..50}; do
    if [ -S "$SOCKET_PATH" ]; then
        break
    fi
    sleep 0.1
done

if [ ! -S "$SOCKET_PATH" ]; then
    echo "Error: Socket was not created"
    exit 1
fi

echo "Running test command with shim..."
TEST_FILE="$TEMP_DIR/test_file"
touch "$TEST_FILE"

# Create a small C program to trigger open
cat <<EOF > "$TEMP_DIR/test.c"
#include <fcntl.h>
#include <unistd.h>
#include <stdio.h>

int main() {
    int fd = open("$TEST_FILE", O_RDONLY);
    if (fd < 0) {
        perror("open");
        return 1;
    }
    close(fd);
    return 0;
}
EOF

gcc "$TEMP_DIR/test.c" -o "$TEMP_DIR/test_prog"

LD_PRELOAD="$SHIM_PATH" "$TEMP_DIR/test_prog"

# Give it a moment to flush
sleep 1

echo "Verifying logs..."
LOG_FILE=$(find "$LOG_DIR" -name "session-*.jsonl" | head -n 1)

if [ -z "$LOG_FILE" ]; then
    echo "Error: No log file created"
    exit 1
fi

echo "Log file: $LOG_FILE"
cat "$LOG_FILE"

if grep -qE "open|openat" "$LOG_FILE"; then
    echo "SUCCESS: Found 'open' or 'openat' event in logs"
else
    echo "FAILURE: Did not find 'open' or 'openat' event in logs"
    exit 1
fi
