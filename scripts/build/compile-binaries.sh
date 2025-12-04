#!/usr/bin/env bash
# Compiles Rust and .NET components for a specific architecture
# Usage: ./compile-binaries.sh [amd64|arm64] [output_dir]

set -euo pipefail

ARCH="${1:-amd64}"
OUT_DIR="${2:-artifacts}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../" && pwd)"

echo "🚀 Starting build for architecture: $ARCH"
mkdir -p "$OUT_DIR"

# Map docker arch to rust/dotnet targets
if [ "$ARCH" = "amd64" ]; then
    RUST_TARGET="x86_64-unknown-linux-gnu"
    DOTNET_RID="linux-x64"
    CC_LINKER=""
elif [ "$ARCH" = "arm64" ]; then
    RUST_TARGET="aarch64-unknown-linux-gnu"
    DOTNET_RID="linux-arm64"
    # Set linker for Rust cross-compilation
    export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER="aarch64-linux-gnu-gcc"
    CC_LINKER="clang" # .NET NativeAOT uses clang for cross-compilation usually
else
    echo "❌ Unsupported architecture: $ARCH"
    exit 1
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
cp "$RUST_OUT_DIR/agentcli-exec" "$REPO_ROOT/$OUT_DIR/"
cp "$RUST_OUT_DIR/agent-task-runnerd" "$REPO_ROOT/$OUT_DIR/"
cp "$RUST_OUT_DIR/agent-task-sandbox" "$REPO_ROOT/$OUT_DIR/"

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
cp "$RUST_OUT_DIR/libaudit_shim.so" "$REPO_ROOT/$OUT_DIR/"

popd >/dev/null

# ============================================================================
# .NET Build (LogCollector)
# ============================================================================
echo "Yz Building .NET components ($DOTNET_RID)..."

# Build LogCollector
echo "  - ContainAI.LogCollector"
dotnet publish "$REPO_ROOT/src/ContainAI.LogCollector/ContainAI.LogCollector.csproj" \
    -p:PublishProfile=FolderProfile \
    -r "$DOTNET_RID" \
    -o "$REPO_ROOT/$OUT_DIR/log-collector"

# Move binaries to flat output structure for Dockerfile simplicity
mv "$REPO_ROOT/$OUT_DIR/log-collector/containai-log-collector" "$REPO_ROOT/$OUT_DIR/containai-log-collector"

# Cleanup intermediate folders
rm -rf "$REPO_ROOT/$OUT_DIR/log-collector"

echo "✅ Build complete. Artifacts in $OUT_DIR:"
ls -lh "$REPO_ROOT/$OUT_DIR"
