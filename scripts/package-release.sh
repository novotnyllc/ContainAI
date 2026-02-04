#!/usr/bin/env bash
# ==============================================================================
# ContainAI Release Packager
# ==============================================================================
# Creates release tarballs containing runtime dependencies only.
# Called by CI to create per-architecture release packages.
#
# Usage: ./scripts/package-release.sh --arch <arch> --version <version> [--output-dir <dir>]
#
# Arguments:
#   --arch        Architecture (linux-x64, linux-arm64, macos-x64, macos-arm64)
#   --version     Version string (e.g., 0.2.0-dev.5)
#   --output-dir  Output directory (default: ./artifacts)
#
# Output: containai-<version>-<arch>.tar.gz
#
# Tarball structure:
#   containai-<version>-<arch>/
#   ├── containai.sh            # Main CLI entry point
#   ├── lib/                    # Shell libraries
#   ├── scripts/
#   │   └── parse-manifest.sh   # ONLY this runtime script
#   ├── manifests/              # Per-agent manifest files (required by sync.sh)
#   ├── templates/              # User templates
#   ├── acp-proxy               # AOT binary
#   ├── install.sh              # Installer (works locally)
#   ├── VERSION                 # Version file
#   └── LICENSE
# ==============================================================================
set -euo pipefail

ARCH=""
VERSION=""
OUTPUT_DIR="./artifacts"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --arch)
            ARCH="$2"
            shift 2
            ;;
        --version)
            VERSION="$2"
            shift 2
            ;;
        --output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --help|-h)
            printf 'Usage: %s --arch <arch> --version <version> [--output-dir <dir>]\n' "$0"
            printf '\nArguments:\n'
            printf '  --arch        Architecture (linux-x64, linux-arm64, macos-x64, macos-arm64)\n'
            printf '  --version     Version string (e.g., 0.2.0-dev.5)\n'
            printf '  --output-dir  Output directory (default: ./artifacts)\n'
            exit 0
            ;;
        *)
            printf 'ERROR: Unknown argument: %s\n' "$1" >&2
            exit 1
            ;;
    esac
done

# Validate required arguments
if [[ -z "$ARCH" ]]; then
    printf 'ERROR: --arch is required\n' >&2
    exit 1
fi

if [[ -z "$VERSION" ]]; then
    printf 'ERROR: --version is required\n' >&2
    exit 1
fi

# Validate architecture
case "$ARCH" in
    linux-x64|linux-arm64|macos-x64|macos-arm64)
        ;;
    *)
        printf 'ERROR: Unsupported architecture: %s\n' "$ARCH" >&2
        printf '  Supported: linux-x64, linux-arm64, macos-x64, macos-arm64\n' >&2
        exit 1
        ;;
esac

# Determine repository root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Map architecture to .NET RID
case "$ARCH" in
    linux-x64)
        DOTNET_RID="linux-x64"
        ;;
    linux-arm64)
        DOTNET_RID="linux-arm64"
        ;;
    macos-x64)
        DOTNET_RID="osx-x64"
        ;;
    macos-arm64)
        DOTNET_RID="osx-arm64"
        ;;
esac

# Paths
SRC_DIR="$REPO_ROOT/src"
TARBALL_NAME="containai-${VERSION}-${ARCH}"
STAGING_DIR="$(mktemp -d)"
PACKAGE_DIR="$STAGING_DIR/$TARBALL_NAME"

# Cleanup on exit
cleanup() {
    rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

printf 'Creating release package: %s.tar.gz\n' "$TARBALL_NAME"
printf '  Architecture: %s\n' "$ARCH"
printf '  Version: %s\n' "$VERSION"

# Create package directory structure
mkdir -p "$PACKAGE_DIR"
mkdir -p "$PACKAGE_DIR/lib"
mkdir -p "$PACKAGE_DIR/scripts"
mkdir -p "$PACKAGE_DIR/templates"
mkdir -p "$PACKAGE_DIR/manifests"

# Copy main CLI entry point
printf '  Copying containai.sh...\n'
cp "$SRC_DIR/containai.sh" "$PACKAGE_DIR/containai.sh"
chmod +x "$PACKAGE_DIR/containai.sh"

# Copy shell libraries
printf '  Copying lib/...\n'
cp "$SRC_DIR/lib/"*.sh "$PACKAGE_DIR/lib/"

# Copy ONLY parse-manifest.sh (runtime dependency of sync.sh)
printf '  Copying scripts/parse-manifest.sh...\n'
cp "$SRC_DIR/scripts/parse-manifest.sh" "$PACKAGE_DIR/scripts/"
chmod +x "$PACKAGE_DIR/scripts/parse-manifest.sh"

# Copy manifests directory (runtime dependency of sync.sh)
printf '  Copying manifests/...\n'
if ! compgen -G "$SRC_DIR/manifests/*.toml" >/dev/null; then
    printf 'ERROR: no .toml files found in manifests directory: %s/manifests/\n' "$SRC_DIR" >&2
    exit 1
fi
cp "$SRC_DIR/manifests/"*.toml "$PACKAGE_DIR/manifests/"

# Copy templates
printf '  Copying templates/...\n'
if [[ -d "$SRC_DIR/templates" ]]; then
    cp -r "$SRC_DIR/templates/"* "$PACKAGE_DIR/templates/" 2>/dev/null || true
fi

# Copy acp-proxy binary (must be pre-built)
ACP_BINARY="$REPO_ROOT/artifacts/publish/acp-proxy/release_${DOTNET_RID}/acp-proxy"
if [[ -f "$ACP_BINARY" ]]; then
    printf '  Copying acp-proxy binary...\n'
    cp "$ACP_BINARY" "$PACKAGE_DIR/acp-proxy"
    chmod +x "$PACKAGE_DIR/acp-proxy"
else
    printf 'ERROR: acp-proxy binary not found at: %s\n' "$ACP_BINARY" >&2
    printf '  Build it first: dotnet publish src/acp-proxy -r %s -c Release --self-contained\n' "$DOTNET_RID" >&2
    exit 1
fi

# Copy install.sh
printf '  Copying install.sh...\n'
cp "$REPO_ROOT/install.sh" "$PACKAGE_DIR/install.sh"
chmod +x "$PACKAGE_DIR/install.sh"

# Create VERSION file
printf '  Creating VERSION file...\n'
printf '%s\n' "$VERSION" > "$PACKAGE_DIR/VERSION"

# Copy LICENSE
printf '  Copying LICENSE...\n'
cp "$REPO_ROOT/LICENSE" "$PACKAGE_DIR/LICENSE"

# Create output directory and resolve to absolute path (tar runs from staging dir)
mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"

# Create tarball
TARBALL_PATH="$OUTPUT_DIR/${TARBALL_NAME}.tar.gz"
printf '  Creating tarball: %s\n' "$TARBALL_PATH"
(cd "$STAGING_DIR" && tar -czf "$TARBALL_PATH" "$TARBALL_NAME")

# Verify tarball
if [[ -f "$TARBALL_PATH" ]]; then
    TARBALL_SIZE=$(stat -f%z "$TARBALL_PATH" 2>/dev/null || stat -c%s "$TARBALL_PATH" 2>/dev/null || echo "unknown")
    printf 'Package created successfully:\n'
    printf '  Path: %s\n' "$TARBALL_PATH"
    printf '  Size: %s bytes\n' "$TARBALL_SIZE"

    # Show contents
    printf '\nPackage contents:\n'
    tar -tzf "$TARBALL_PATH" | sed -n '1,20p'
    printf '...\n'
else
    printf 'ERROR: Failed to create tarball\n' >&2
    exit 1
fi
