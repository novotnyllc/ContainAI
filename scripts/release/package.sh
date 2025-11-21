#!/usr/bin/env bash
# Builds a self-contained bundle:
#   containai-<version>.tar.gz containing:
#     - payload.tar.gz (host tree + tools)
#     - payload.sha256 (hash of payload.tar.gz)
#     - attestation.intoto.jsonl (from CI attestation action)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

VERSION=""
OUT_DIR="$PROJECT_ROOT/dist"
SKIP_SBOM=0
SBOM_SOURCE=""
SBOM_ATTEST=""
ATTESTATION_FILE=""
INCLUDE_DOCKER=0
PAYLOAD_DIR_OVERRIDE=""

print_help() {
    cat <<'EOF'
Usage: package.sh [--version X] [--out DIR] [--skip-sbom] [--sbom FILE] [--sbom-att FILE] [--attestation FILE] [--include-docker]

Outputs dist/<version>/containai-<version>.tar.gz containing payload + attestations.

Options:
  --version X         Release version (default git describe)
  --out DIR           Output directory (default: dist)
  --skip-sbom         Do not include SBOM (dev only)
  --sbom FILE         Pre-generated SBOM to embed
  --sbom-att FILE     Attestation bundle (intoto) for the SBOM file
  --attestation FILE  Attestation bundle (intoto) for payload.tar.gz
  --include-docker    Include docker/ tree in payload
  --payload-dir DIR   Use an existing payload directory instead of copying sources (must contain final payload contents)
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version) VERSION="$2"; shift 2 ;;
        --out) OUT_DIR="$2"; shift 2 ;;
        --skip-sbom) SKIP_SBOM=1; shift ;;
        --sbom) SBOM_SOURCE="$2"; shift 2 ;;
        --sbom-att) SBOM_ATTEST="$2"; shift 2 ;;
        --attestation) ATTESTATION_FILE="$2"; shift 2 ;;
        --include-docker) INCLUDE_DOCKER=1; shift ;;
        --payload-dir) PAYLOAD_DIR_OVERRIDE="$2"; shift 2 ;;
        -h|--help) print_help; exit 0 ;;
        *) echo "Unknown arg: $1" >&2; print_help >&2; exit 1 ;;
    esac
done

if [[ -z "$VERSION" ]]; then
    if command -v git >/dev/null 2>&1 && git -C "$PROJECT_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        VERSION="$(git -C "$PROJECT_ROOT" describe --tags --always --dirty 2>/dev/null || true)"
    fi
    VERSION="${VERSION:-0.0.0-dev}"
fi

DEST_DIR="$OUT_DIR/$VERSION"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

PAYLOAD_ROOT="payload"
if [[ -n "$PAYLOAD_DIR_OVERRIDE" ]]; then
    PAYLOAD_DIR="$PAYLOAD_DIR_OVERRIDE"
    mkdir -p "$PAYLOAD_DIR"
else
    PAYLOAD_DIR="$WORK_DIR/$PAYLOAD_ROOT"
    mkdir -p "$PAYLOAD_DIR"
fi

echo "📦 Building bundle v$VERSION"
echo "Output dir: $DEST_DIR"

copy_path() {
    local src="$1" dest="$2"
    if [ -e "$src" ]; then rsync -a --delete --exclude '.git/' "$src" "$dest"; fi
}

if [[ -z "$PAYLOAD_DIR_OVERRIDE" ]]; then
    include_paths=(
        "$PROJECT_ROOT/host"
        "$PROJECT_ROOT/agent-configs"
        "$PROJECT_ROOT/config.toml"
        "$PROJECT_ROOT/README.md"
        "$PROJECT_ROOT/SECURITY.md"
        "$PROJECT_ROOT/USAGE.md"
        "$PROJECT_ROOT/LICENSE"
    )
    [[ $INCLUDE_DOCKER -eq 1 ]] && include_paths+=("$PROJECT_ROOT/docker")

    for path in "${include_paths[@]}"; do
        copy_path "$path" "$PAYLOAD_DIR/"
    done
fi

SBOM_PATH="$PAYLOAD_DIR/payload.sbom.json"
if [[ -n "$SBOM_SOURCE" ]]; then
    cp "$SBOM_SOURCE" "$SBOM_PATH"
elif [[ $SKIP_SBOM -eq 1 ]]; then
    echo '{"sbom":"skipped"}' > "$SBOM_PATH"
else
    echo "❌ SBOM source not provided. Pass --sbom FILE or --skip-sbom." >&2
    exit 1
fi
if [[ -n "$SBOM_ATTEST" ]]; then
    cp "$SBOM_ATTEST" "$PAYLOAD_DIR/payload.sbom.json.intoto.jsonl"
fi

mkdir -p "$PAYLOAD_DIR/tools"
COSIGN_ROOT_SOURCE="$PROJECT_ROOT/host/utils/cosign-root.pem"
if [[ -f "$COSIGN_ROOT_SOURCE" ]]; then
    cp "$COSIGN_ROOT_SOURCE" "$PAYLOAD_DIR/tools/cosign-root.pem"
fi

# SHA256SUMS inside payload for integrity-check (exclude self)
pushd "$PAYLOAD_DIR" >/dev/null
find . -type f ! -name 'SHA256SUMS' -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS
popd >/dev/null

mkdir -p "$DEST_DIR"
pushd "$WORK_DIR" >/dev/null
tar -czf "$DEST_DIR/payload.tar.gz" "$PAYLOAD_ROOT"
popd >/dev/null

PAYLOAD_HASH=$(sha256sum "$DEST_DIR/payload.tar.gz" | awk '{print $1}')
echo "$PAYLOAD_HASH  payload.tar.gz" > "$DEST_DIR/payload.sha256"

mkdir -p "$WORK_DIR/bundle"
cp "$DEST_DIR/payload.tar.gz" "$WORK_DIR/bundle/"
cp "$DEST_DIR/payload.sha256" "$WORK_DIR/bundle/"
if [[ -n "$ATTESTATION_FILE" ]]; then
    cp "$ATTESTATION_FILE" "$WORK_DIR/bundle/attestation.intoto.jsonl"
else
    echo '{"attestation":"placeholder"}' > "$WORK_DIR/bundle/attestation.intoto.jsonl"
fi
if [[ -f "$PAYLOAD_DIR/tools/cosign-root.pem" ]]; then
    cp "$PAYLOAD_DIR/tools/cosign-root.pem" "$WORK_DIR/bundle/cosign-root.pem"
fi

BUNDLE_NAME="containai-$VERSION.tar.gz"
tar -czf "$DEST_DIR/$BUNDLE_NAME" -C "$WORK_DIR/bundle" .

echo ""
echo "Bundle created: $DEST_DIR/$BUNDLE_NAME"
echo "Contains: payload.tar.gz, payload.sha256, attestation.intoto.jsonl (if provided)"
