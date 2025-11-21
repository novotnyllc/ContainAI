#!/usr/bin/env bash
# Lightweight tests for packaging and prod install workflows (no Docker required).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

BIN_DIR="$WORK_DIR/bin"
mkdir -p "$BIN_DIR"
export PATH="$BIN_DIR:$PATH"

SBOM_FILE="$WORK_DIR/payload.sbom.json"
echo '{"bomFormat":"CycloneDX","dependencies":[]}' > "$SBOM_FILE"
SBOM_ATTEST="$WORK_DIR/payload.sbom.json.intoto.jsonl"
echo '{"attestation":"placeholder"}' > "$SBOM_ATTEST"

VERSION="test-$(date +%s)"
DIST_DIR="$WORK_DIR/dist"

echo "🔨 Running package.sh..."
if ! "$PROJECT_ROOT/scripts/release/package.sh" --version "$VERSION" --out "$DIST_DIR" --sbom "$SBOM_FILE" --sbom-att "$SBOM_ATTEST"; then
    echo "❌ package.sh failed" >&2
    exit 1
fi

BUNDLE="$DIST_DIR/$VERSION/containai-$VERSION.tar.gz"
BUNDLE_ATTEST="$DIST_DIR/$VERSION/containai-$VERSION.tar.gz.intoto.jsonl"
[[ -f "$BUNDLE" ]] || { echo "❌ Bundle missing"; exit 1; }
echo '{"attestation":"placeholder"}' > "$BUNDLE_ATTEST"

INSTALL_ROOT="$WORK_DIR/install"
echo "🏗️  Installing to $INSTALL_ROOT"
"$PROJECT_ROOT/host/utils/install-package.sh" \
    --version "$VERSION" \
    --asset-dir "$DIST_DIR/$VERSION" \
    --repo "local/test" \
    --install-root "$INSTALL_ROOT" \
    --allow-nonroot

CURRENT_PATH="$(readlink -f "$INSTALL_ROOT/current")"
[[ -d "$CURRENT_PATH" ]] || { echo "❌ current symlink missing"; exit 1; }
[[ -f "$CURRENT_PATH/install.meta" ]] || { echo "❌ install.meta missing"; exit 1; }

echo "🔍 Verifying install via --verify-only"
"$PROJECT_ROOT/host/utils/install-package.sh" \
    --version "$VERSION" \
    --asset-dir "$DIST_DIR/$VERSION" \
    --repo "local/test" \
    --install-root "$INSTALL_ROOT" \
    --allow-nonroot \
    --verify-only

echo "✅ Packaging/install smoke tests passed"
