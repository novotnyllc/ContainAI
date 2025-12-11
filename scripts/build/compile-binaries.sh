#!/usr/bin/env bash
# Compiles Rust and .NET components for a specific architecture
# Usage: ./compile-binaries.sh [amd64|arm64] [output_dir]
#
# Supports cross-compilation on Linux (x64 → arm64 or arm64 → x64)
# Requirements for cross-compilation:
#   - clang, lld (LLVM linker)
#   - Cross-architecture toolchain (e.g., gcc-aarch64-linux-gnu for arm64)
#   - Cross-architecture zlib (e.g., zlib1g-dev:arm64)
#
# See: https://learn.microsoft.com/en-us/dotnet/core/deploying/native-aot/cross-compile

set -euo pipefail

# Helper to copy files only if content changed (preserves mtime/docker cache)
install_if_changed() {
    local src="$1"
    local dst="$2"
    if [ ! -f "$src" ]; then
        echo "❌ Source file not found: $src"
        exit 1
    fi
    if [ -f "$dst" ] && cmp -s "$src" "$dst"; then
        # Files are identical, do nothing to preserve mtime
        return
    fi
    cp "$src" "$dst"
    echo "  -> Updated $dst"
}

ARCH="${1:-amd64}"
OUT_DIR="${2:-artifacts}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../" && pwd)"

# Make OUT_DIR absolute if it's relative
if [[ "$OUT_DIR" != /* ]]; then
    OUT_DIR="$REPO_ROOT/$OUT_DIR"
fi

# Detect host architecture
HOST_ARCH="$(uname -m)"
case "$HOST_ARCH" in
    x86_64)  HOST_ARCH="amd64" ;;
    aarch64) HOST_ARCH="arm64" ;;
esac

# Determine if we're cross-compiling
CROSS_COMPILE="false"
if [ "$HOST_ARCH" != "$ARCH" ]; then
    CROSS_COMPILE="true"
    echo "🔀 Cross-compiling from $HOST_ARCH to $ARCH"
fi

echo "🚀 Starting build for architecture: $ARCH (host: $HOST_ARCH)"
mkdir -p "$OUT_DIR"

# Map docker arch to rust/dotnet targets
if [ "$ARCH" = "amd64" ]; then
    RUST_TARGET="x86_64-unknown-linux-gnu"
    DOTNET_RID="linux-x64"
    CROSS_TRIPLE="x86_64-linux-gnu"
elif [ "$ARCH" = "arm64" ]; then
    RUST_TARGET="aarch64-unknown-linux-gnu"
    DOTNET_RID="linux-arm64"
    CROSS_TRIPLE="aarch64-linux-gnu"
else
    echo "❌ Unsupported architecture: $ARCH"
    exit 1
fi

# Configure Rust cross-compilation
if [ "$CROSS_COMPILE" = "true" ]; then
    # Set linker for the target architecture
    if [ "$ARCH" = "arm64" ]; then
        export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER="aarch64-linux-gnu-gcc"
    else
        export CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="x86_64-linux-gnu-gcc"
    fi
fi

# ============================================================================
# Rust Build (Agent Task Runner)
# ============================================================================
echo "🦀 Building Rust components ($RUST_TARGET)..."
pushd "$REPO_ROOT/src/agent-task-runner" >/dev/null

# Ensure target is added
rustup target add "$RUST_TARGET"

# Build
cargo build --release --target "$RUST_TARGET"

# Define Rust output directory (workspace target)
RUST_OUT_DIR="$REPO_ROOT/src/target/$RUST_TARGET/release"

# Copy binaries
install_if_changed "$RUST_OUT_DIR/agentcli-exec" "$OUT_DIR/agentcli-exec"
install_if_changed "$RUST_OUT_DIR/agent-task-runnerd" "$OUT_DIR/agent-task-runnerd"
install_if_changed "$RUST_OUT_DIR/agent-task-sandbox" "$OUT_DIR/agent-task-sandbox"
install_if_changed "$RUST_OUT_DIR/mcp-wrapper-runner" "$OUT_DIR/mcp-wrapper-runner"

popd >/dev/null

# ============================================================================
# Rust Build (Audit Shim)
# ============================================================================
echo "🦀 Building Audit Shim ($RUST_TARGET)..."
pushd "$REPO_ROOT/src/audit-shim" >/dev/null

# Build
cargo build --release --target "$RUST_TARGET"

# Copy library
# The library name depends on the OS, but for Linux it's libaudit_shim.so
install_if_changed "$RUST_OUT_DIR/libaudit_shim.so" "$OUT_DIR/libaudit_shim.so"

popd >/dev/null

# ============================================================================
# .NET Build (LogCollector)
# ============================================================================
echo "🔧 Building .NET components ($DOTNET_RID)..."

# Build LogCollector with cross-compilation support
echo "  - ContainAI.LogCollector"

# Prepare cross-compilation properties for .NET AOT
DOTNET_EXTRA_ARGS=()
if [ "$CROSS_COMPILE" = "true" ]; then
    # Use clang with LLVM linker for cross-compilation
    # .NET AOT auto-detects the target triple from RID and uses --target= flag
    DOTNET_EXTRA_ARGS+=(
        "-p:CppCompilerAndLinker=clang"
        "-p:LinkerFlavor=lld"
        "-p:ObjCopyName=llvm-objcopy"
    )
    echo "  (cross-compiling with clang/lld)"
fi

dotnet publish "$REPO_ROOT/src/ContainAI.LogCollector/ContainAI.LogCollector.csproj" \
    -p:PublishProfile=FolderProfile \
    -r "$DOTNET_RID" \
    "${DOTNET_EXTRA_ARGS[@]}" \
    -o "$OUT_DIR/log-collector"

# Move binaries to flat output structure for Dockerfile simplicity
install_if_changed "$OUT_DIR/log-collector/containai-log-collector" "$OUT_DIR/containai-log-collector"

# Cleanup intermediate folders
rm -rf "$OUT_DIR/log-collector"

echo "✅ Build complete. Artifacts in $OUT_DIR:"
ls -lh "$OUT_DIR"
