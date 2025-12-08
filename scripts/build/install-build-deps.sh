#!/usr/bin/env bash
# Install build dependencies for compiling ContainAI native binaries.
# This script handles both native and cross-compilation toolchains.
#
# Usage:
#   scripts/build/install-build-deps.sh [options]
#
# Options:
#   --native-only      Only install native toolchain (skip cross-compilation tools)
#   --ci               Non-interactive mode for CI environments
#   -h, --help         Show this help message
#
# Requirements:
#   - Ubuntu 22.04+ or Debian 12+ (dpkg-based system)
#   - sudo access for package installation
#
# This script installs:
#   - .NET SDK (via global.json version)
#   - Rust toolchain (via rustup)
#   - Native build dependencies (clang, zlib, libseccomp, libcap)
#   - Cross-compilation toolchain (default: both amd64 and arm64)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

NATIVE_ONLY=false
CI_MODE=false

print_help() {
    cat <<'EOF'
Usage: scripts/build/install-build-deps.sh [options]

Install build dependencies for compiling ContainAI native binaries.

Options:
  --native-only      Only install native toolchain (skip cross-compilation tools)
  --ci               Non-interactive mode for CI environments
  -h, --help         Show this help message

This script installs:
  - .NET SDK (version from src/global.json)
  - Rust toolchain (via rustup)
  - Native build dependencies (clang, zlib, libseccomp, libcap)
  - Cross-compilation toolchain for the other architecture (enabled by default)

By default, this script installs tools to build for BOTH amd64 and arm64,
regardless of which architecture you're running on. Use --native-only to
skip cross-compilation tools if you only need to build for your host arch.

Examples:
  # Install full toolchain (native + cross-compilation)
  ./scripts/build/install-build-deps.sh

  # Install native toolchain only (no cross-compilation)
  ./scripts/build/install-build-deps.sh --native-only

  # CI mode (non-interactive)
  ./scripts/build/install-build-deps.sh --ci
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --native-only)
            NATIVE_ONLY=true
            shift
            ;;
        --ci)
            CI_MODE=true
            shift
            ;;
        -h|--help)
            print_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            print_help >&2
            exit 1
            ;;
    esac
done

# Detect host architecture
HOST_ARCH="$(uname -m)"
case "$HOST_ARCH" in
    x86_64)  HOST_ARCH_SLUG="amd64" ;;
    aarch64) HOST_ARCH_SLUG="arm64" ;;
    *)
        echo "❌ Unsupported host architecture: $HOST_ARCH" >&2
        exit 1
        ;;
esac

# Determine cross-compile target
if [[ "$HOST_ARCH_SLUG" == "amd64" ]]; then
    CROSS_ARCH_SLUG="arm64"
    CROSS_GCC_PKG="gcc-aarch64-linux-gnu"
    CROSS_RUST_TARGET="aarch64-unknown-linux-gnu"
else
    CROSS_ARCH_SLUG="amd64"
    CROSS_GCC_PKG="gcc-x86-64-linux-gnu"
    CROSS_RUST_TARGET="x86_64-unknown-linux-gnu"
fi

echo "🔍 Detecting system..."
echo "   Host architecture: $HOST_ARCH ($HOST_ARCH_SLUG)"
echo "   Cross-compile target: $CROSS_ARCH_SLUG"
echo "   Native-only mode: $NATIVE_ONLY"

# Check for dpkg-based system
if ! command -v dpkg >/dev/null 2>&1; then
    echo "❌ This script requires a dpkg-based system (Ubuntu/Debian)" >&2
    echo "   For other distributions, install these packages manually:" >&2
    echo "   - clang, lld, llvm, zlib1g-dev, libseccomp-dev, libcap-dev" >&2
    echo "   - For arm64 cross-compile: gcc-aarch64-linux-gnu, zlib1g-dev:arm64" >&2
    echo "   - For amd64 cross-compile: gcc-x86-64-linux-gnu, zlib1g-dev:amd64" >&2
    exit 1
fi

# ============================================================================
# System packages
# ============================================================================
echo ""
echo "📦 Installing system packages..."

PACKAGES=(
    # Build essentials
    "build-essential"
    "pkg-config"
    
    # Rust and .NET AOT build dependencies
    "clang"
    "lld"
    "llvm"
    "zlib1g-dev"
    "libseccomp-dev"
    "libcap-dev"
    
    # Useful tools
    "curl"
    "git"
    "jq"
)

# Cross-compilation packages
if [[ "$NATIVE_ONLY" != "true" ]]; then
    echo "   Including cross-compilation toolchain for $CROSS_ARCH_SLUG..."
    PACKAGES+=(
        # GCC cross-compiler for target architecture
        "$CROSS_GCC_PKG"
    )
fi

sudo apt-get update
if [[ "$CI_MODE" == "true" ]]; then
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${PACKAGES[@]}"
else
    sudo apt-get install -y "${PACKAGES[@]}"
fi

# Enable cross-architecture for cross-compilation packages
if [[ "$NATIVE_ONLY" != "true" ]]; then
    echo ""
    echo "📦 Enabling $CROSS_ARCH_SLUG architecture for cross-compilation libraries..."
    sudo dpkg --add-architecture "$CROSS_ARCH_SLUG"
    sudo apt-get update
    
    # Install cross-arch libraries needed for linking
    CROSS_LIBS=(
        "zlib1g-dev:$CROSS_ARCH_SLUG"
    )
    
    if [[ "$CI_MODE" == "true" ]]; then
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${CROSS_LIBS[@]}"
    else
        sudo apt-get install -y "${CROSS_LIBS[@]}"
    fi
fi

# ============================================================================
# Rust toolchain
# ============================================================================
echo ""
echo "🦀 Checking Rust toolchain..."

if ! command -v rustup >/dev/null 2>&1; then
    echo "   Installing Rust via rustup..."
    if [[ "$CI_MODE" == "true" ]]; then
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable
    else
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- --default-toolchain stable
    fi
    # shellcheck source=/dev/null
    source "$HOME/.cargo/env"
else
    echo "   Rust already installed: $(rustc --version)"
fi

# Install target architectures
echo "   Adding Rust targets..."
rustup target add x86_64-unknown-linux-gnu
rustup target add aarch64-unknown-linux-gnu

# ============================================================================
# .NET SDK
# ============================================================================
echo ""
echo "🔧 Checking .NET SDK..."

# Read required version from global.json
DOTNET_VERSION=""
if [[ -f "$PROJECT_ROOT/src/global.json" ]]; then
    DOTNET_VERSION=$(jq -r '.sdk.version // empty' "$PROJECT_ROOT/src/global.json" 2>/dev/null || true)
fi

if [[ -z "$DOTNET_VERSION" ]]; then
    echo "   ⚠️  Could not read .NET version from src/global.json, using latest 9.0"
    DOTNET_VERSION="9.0"
fi

# Check if .NET is installed with correct version
DOTNET_INSTALLED=false
if command -v dotnet >/dev/null 2>&1; then
    INSTALLED_VERSION=$(dotnet --version 2>/dev/null || true)
    if [[ "$INSTALLED_VERSION" == "$DOTNET_VERSION"* ]]; then
        DOTNET_INSTALLED=true
        echo "   .NET SDK already installed: $INSTALLED_VERSION"
    else
        echo "   .NET SDK found ($INSTALLED_VERSION) but need $DOTNET_VERSION"
    fi
fi

if [[ "$DOTNET_INSTALLED" == "false" ]]; then
    echo "   Installing .NET SDK $DOTNET_VERSION..."
    
    # Use Microsoft's install script
    curl -sSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh
    chmod +x /tmp/dotnet-install.sh
    
    # Install to user directory (doesn't require sudo)
    /tmp/dotnet-install.sh --version "$DOTNET_VERSION" --install-dir "$HOME/.dotnet"
    
    # Add to PATH if not already there
    if [[ ":$PATH:" != *":$HOME/.dotnet:"* ]]; then
        echo ""
        echo "   ⚠️  Add the following to your shell profile:"
        echo "      export DOTNET_ROOT=\"\$HOME/.dotnet\""
        echo "      export PATH=\"\$HOME/.dotnet:\$PATH\""
        echo ""
        # Set for current session
        export DOTNET_ROOT="$HOME/.dotnet"
        export PATH="$HOME/.dotnet:$PATH"
    fi
    
    rm -f /tmp/dotnet-install.sh
fi

# ============================================================================
# Verification
# ============================================================================
echo ""
echo "✅ Build dependencies installed!"
echo ""
echo "Installed tools:"
echo "   - clang:       $(clang --version 2>/dev/null | head -1 || echo 'not found')"
echo "   - lld:         $(ld.lld --version 2>/dev/null | head -1 || echo 'not found')"
echo "   - llvm-objcopy: $(llvm-objcopy --version 2>/dev/null | head -1 || echo 'not found')"
echo "   - rustc:       $(rustc --version 2>/dev/null || echo 'not found')"
echo "   - cargo:       $(cargo --version 2>/dev/null || echo 'not found')"
echo "   - dotnet:      $(dotnet --version 2>/dev/null || echo 'not found')"

if [[ "$NATIVE_ONLY" != "true" ]]; then
    echo ""
    echo "Cross-compilation tools (for $CROSS_ARCH_SLUG):"
    if [[ "$CROSS_ARCH_SLUG" == "arm64" ]]; then
        echo "   - aarch64-linux-gnu-gcc: $(aarch64-linux-gnu-gcc --version 2>/dev/null | head -1 || echo 'not found')"
    else
        echo "   - x86_64-linux-gnu-gcc:  $(x86_64-linux-gnu-gcc --version 2>/dev/null | head -1 || echo 'not found')"
    fi
fi

echo ""
echo "You can now build native binaries with:"
echo "   ./scripts/build/compile-binaries.sh $HOST_ARCH_SLUG artifacts"
if [[ "$NATIVE_ONLY" != "true" ]]; then
    echo "   ./scripts/build/compile-binaries.sh $CROSS_ARCH_SLUG artifacts  # cross-compile to $CROSS_ARCH_SLUG"
fi
