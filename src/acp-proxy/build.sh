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
#   - .NET 10 SDK (dotnet --version) OR Docker for fallback
#
# Version:
#   Uses NBGV for versioning. Detects local SDK or falls back to Docker.
#
# Examples:
#   ./build.sh                    # Build release
#   ./build.sh --install          # Build and install to src/bin/
#   ./build.sh --debug            # Build debug configuration
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
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

# ==============================================================================
# Version detection via NBGV
# ==============================================================================

get_version_with_local_sdk() {
    cd "$REPO_ROOT"
    dotnet tool restore >/dev/null 2>&1 || true
    dotnet nbgv get-version --variable SemVer2 2>/dev/null
}

get_version_with_docker() {
    docker run --rm -v "$REPO_ROOT:/src" -w /src \
        mcr.microsoft.com/dotnet/sdk:10.0 \
        sh -c "dotnet tool restore >/dev/null 2>&1 && dotnet nbgv get-version --variable SemVer2 2>/dev/null"
}

# Try to get version from NBGV
VERSION=""
if command -v dotnet >/dev/null 2>&1; then
    printf '[INFO] Detecting version via local .NET SDK...\n'
    if VERSION=$(get_version_with_local_sdk); then
        printf '[INFO] Version: %s\n' "$VERSION"
    else
        printf '[WARN] NBGV failed with local SDK\n' >&2
        VERSION=""
    fi
fi

# Fallback to Docker if no local SDK or NBGV failed
if [[ -z "$VERSION" ]] && command -v docker >/dev/null 2>&1; then
    printf '[INFO] Falling back to Docker SDK image for version detection...\n'
    if VERSION=$(get_version_with_docker); then
        printf '[INFO] Version: %s\n' "$VERSION"
    else
        printf '[WARN] NBGV failed with Docker SDK\n' >&2
        VERSION=""
    fi
fi

# Use fallback version if NBGV failed
if [[ -z "$VERSION" ]]; then
    VERSION="0.0.0-local"
    printf '[WARN] Using fallback version: %s\n' "$VERSION"
fi

# Export for downstream use
export NBGV_SemVer2="$VERSION"

# ==============================================================================
# Build
# ==============================================================================

# Check for dotnet
if ! command -v dotnet >/dev/null 2>&1; then
    printf '[ERROR] .NET SDK not found. Install from https://dot.net\n' >&2
    exit 1
fi

# Build with version
printf '[INFO] Building acp-proxy (%s, %s, v%s)...\n' "$CONFIG" "$RID" "$VERSION"
cd "$SCRIPT_DIR"
dotnet publish -c "$CONFIG" -r "$RID" --self-contained true -p:Version="$VERSION"

# Install if requested
if [[ "$INSTALL" -eq 1 ]]; then
    local_bin="$SCRIPT_DIR/../bin"
    mkdir -p "$local_bin"

    src_binary="$REPO_ROOT/artifacts/publish/acp-proxy/release_$RID/acp-proxy"
    if [[ ! -f "$src_binary" ]]; then
        # Try legacy path structure
        src_binary="$SCRIPT_DIR/bin/$CONFIG/net10.0/$RID/publish/acp-proxy"
    fi

    if [[ ! -f "$src_binary" ]]; then
        printf '[ERROR] Binary not found. Checked:\n' >&2
        printf '  - %s\n' "$REPO_ROOT/artifacts/publish/acp-proxy/release_$RID/acp-proxy" >&2
        printf '  - %s\n' "$SCRIPT_DIR/bin/$CONFIG/net10.0/$RID/publish/acp-proxy" >&2
        exit 1
    fi

    printf '[INFO] Installing to %s/acp-proxy\n' "$local_bin"
    cp "$src_binary" "$local_bin/acp-proxy"
    chmod +x "$local_bin/acp-proxy"

    # Preserve symbols for local debugging when available.
    if [[ -f "${src_binary}.pdb" ]]; then
        cp "${src_binary}.pdb" "$local_bin/acp-proxy.pdb"
    fi

    printf '[OK] Installed acp-proxy\n'
fi

printf '[OK] Build complete\n'
