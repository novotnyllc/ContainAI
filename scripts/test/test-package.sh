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

PAYLOAD_DIR="$DIST_DIR/$VERSION/payload"
[[ -d "$PAYLOAD_DIR" ]] || { echo "❌ Payload directory missing"; exit 1; }
[[ -f "$PAYLOAD_DIR/host/profiles/seccomp-containai-agent.json" ]] || { echo "❌ seccomp profile missing in payload"; exit 1; }
[[ -f "$PAYLOAD_DIR/install.sh" ]] || { echo "❌ install.sh missing in payload"; exit 1; }

# Simulate release artifact tar.gz
PAYLOAD_TGZ="$DIST_DIR/$VERSION/containai-payload-$VERSION.tar.gz"
tar -czf "$PAYLOAD_TGZ" -C "$PAYLOAD_DIR" .

INSTALL_ROOT="$WORK_DIR/install"
echo "🏗️  Installing to $INSTALL_ROOT"
"$PROJECT_ROOT/host/utils/install-release.sh" \
    --version "$VERSION" \
    --asset-dir "$DIST_DIR/$VERSION" \
    --repo "local/test" \
    --install-root "$INSTALL_ROOT" \
    --allow-nonroot

CURRENT_PATH="$(readlink -f "$INSTALL_ROOT/current")"
[[ -d "$CURRENT_PATH" ]] || { echo "❌ current symlink missing"; exit 1; }
[[ -f "$CURRENT_PATH/install.meta" ]] || { echo "❌ install.meta missing"; exit 1; }

echo "🔍 Verifying install via --verify-only"
"$PROJECT_ROOT/host/utils/install-release.sh" \
    --version "$VERSION" \
    --asset-dir "$DIST_DIR/$VERSION" \
    --repo "local/test" \
    --install-root "$INSTALL_ROOT" \
    --allow-nonroot \
    --verify-only

echo "✅ Packaging/install smoke tests passed"
