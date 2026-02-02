#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Build ACP Proxy native binary
# ==============================================================================
# Usage: ./build.sh [options]
#   --release       Build release configuration (default)
#   --debug         Build debug configuration
#   --install       Copy binary to ../bin/acp-proxy after build
#   --help          Show this help
#
# Requirements:
#   - .NET 10 SDK (dotnet --version)
#
# Examples:
#   ./build.sh                    # Build release
#   ./build.sh --install          # Build and install to src/bin/
#   ./build.sh --debug            # Build debug configuration
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="Release"
INSTALL=0

# Detect runtime identifier
case "$(uname -s)-$(uname -m)" in
    Linux-x86_64)  RID="linux-x64" ;;
    Linux-aarch64) RID="linux-arm64" ;;
    Darwin-x86_64) RID="osx-x64" ;;
    Darwin-arm64)  RID="osx-arm64" ;;
    *)
        printf '[ERROR] Unsupported platform: %s-%s\n' "$(uname -s)" "$(uname -m)" >&2
        exit 1
        ;;
esac

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --release)
            CONFIG="Release"
            shift
            ;;
        --debug)
            CONFIG="Debug"
            shift
            ;;
        --install)
            INSTALL=1
            shift
            ;;
        --help|-h)
            sed -n '2,/^# ==/p' "$0" | grep '^#' | sed 's/^# //' | sed 's/^#//'
            exit 0
            ;;
        *)
            printf '[ERROR] Unknown option: %s\n' "$1" >&2
            exit 1
            ;;
    esac
done

# Check for dotnet
if ! command -v dotnet >/dev/null 2>&1; then
    printf '[ERROR] .NET SDK not found. Install from https://dot.net\n' >&2
    exit 1
fi

# Build
printf '[INFO] Building acp-proxy (%s, %s)...\n' "$CONFIG" "$RID"
cd "$SCRIPT_DIR"
dotnet publish -c "$CONFIG" -r "$RID" --self-contained true

# Install if requested
if [[ "$INSTALL" -eq 1 ]]; then
    local_bin="$SCRIPT_DIR/../bin"
    mkdir -p "$local_bin"

    src_binary="$SCRIPT_DIR/bin/$CONFIG/net10.0/$RID/publish/acp-proxy"
    if [[ ! -f "$src_binary" ]]; then
        printf '[ERROR] Binary not found at %s\n' "$src_binary" >&2
        exit 1
    fi

    printf '[INFO] Installing to %s/acp-proxy\n' "$local_bin"
    cp "$src_binary" "$local_bin/acp-proxy"
    chmod +x "$local_bin/acp-proxy"
    printf '[OK] Installed acp-proxy\n'
fi

printf '[OK] Build complete\n'
