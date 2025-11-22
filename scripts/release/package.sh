#!/usr/bin/env bash
# Prepares the payload directory and tar/tar.gz artifacts for release upload.
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
LAUNCHER_CHANNEL="${CONTAINAI_LAUNCHER_CHANNEL:-dev}"

print_help() {
    cat <<'EOF'
Usage: package.sh [--version X] [--out DIR] [--skip-sbom] [--sbom FILE] [--sbom-att FILE] [--attestation FILE] [--include-docker]

Outputs dist/<version>/payload/, dist/<version>/containai-payload-<version>.tar, and dist/<version>/containai-payload-<version>.tar.gz.

Options:
  --version X         Release version (default git describe)
  --out DIR           Output directory (default: dist)
  --skip-sbom         Do not include SBOM (dev only)
  --sbom FILE         Pre-generated SBOM to embed
  --sbom-att FILE     Attestation bundle (intoto) for the SBOM file
  --attestation FILE  Attestation bundle (intoto) for payload artifact
  --include-docker    Include docker/ tree in payload
  --payload-dir DIR   Use an existing payload directory instead of copying sources (must contain final payload contents)
  --launcher-channel  Channel for launcher entrypoints (dev|prod|nightly, default: $CONTAINAI_LAUNCHER_CHANNEL or dev)
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
        --launcher-channel) LAUNCHER_CHANNEL="$2"; shift 2 ;;
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

if [[ "$LAUNCHER_CHANNEL" != "dev" ]]; then
    missing_digests=()
    req_vars=(
        IMAGE_DIGEST
        IMAGE_DIGEST_COPILOT
        IMAGE_DIGEST_CODEX
        IMAGE_DIGEST_CLAUDE
        IMAGE_DIGEST_PROXY
        IMAGE_DIGEST_LOG_FORWARDER
    )
    for v in "${req_vars[@]}"; do
        val="${!v:-${CONTAINAI_IMAGE_DIGEST:-}}"
        if [[ -z "$val" ]]; then
            missing_digests+=("$v")
        fi
    done
    if [[ ${#missing_digests[@]} -gt 0 ]]; then
        echo "❌ LAUNCHER_CHANNEL=$LAUNCHER_CHANNEL requires image digests for all components (missing: ${missing_digests[*]})." >&2
        exit 1
    fi
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

echo "📦 Building payload v$VERSION"
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
        "$PROJECT_ROOT/install.sh"
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

# Generate channel-specific launcher entrypoints
ENTRYPOINTS_DIR_SRC="$PAYLOAD_DIR/host/launchers/entrypoints"
if [[ -d "$ENTRYPOINTS_DIR_SRC" ]]; then
    if [[ "$LAUNCHER_CHANNEL" = "dev" ]]; then
        ENTRYPOINTS_DIR_OUT="$ENTRYPOINTS_DIR_SRC"
    else
        ENTRYPOINTS_DIR_OUT="$PAYLOAD_DIR/host/launchers/entrypoints-${LAUNCHER_CHANNEL}"
        rm -rf "$ENTRYPOINTS_DIR_OUT"
        cp -a "$ENTRYPOINTS_DIR_SRC"/. "$ENTRYPOINTS_DIR_OUT"/
    fi
    if ! "$PAYLOAD_DIR/host/utils/prepare-entrypoints.sh" --channel "$LAUNCHER_CHANNEL" --source "$ENTRYPOINTS_DIR_OUT" --dest "$ENTRYPOINTS_DIR_OUT"; then
        echo "❌ Failed to prepare launcher entrypoints for channel $LAUNCHER_CHANNEL" >&2
        exit 1
    fi
    if [[ "$ENTRYPOINTS_DIR_OUT" != "$ENTRYPOINTS_DIR_SRC" ]]; then
        rm -rf "$ENTRYPOINTS_DIR_SRC"
        mv "$ENTRYPOINTS_DIR_OUT" "$ENTRYPOINTS_DIR_SRC"
    fi
fi

# SHA256SUMS inside payload for integrity-check (exclude self)
pushd "$PAYLOAD_DIR" >/dev/null
find . -type f ! -name 'SHA256SUMS' -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS
popd >/dev/null

mkdir -p "$DEST_DIR"

# Create a deterministic top-level payload directory for upload-artifact/release upload
PAYLOAD_OUT="$DEST_DIR/payload"
rm -rf "$PAYLOAD_OUT"
cp -a "$PAYLOAD_DIR"/. "$PAYLOAD_OUT/"

# Hash the canonical SHA256SUMS file to produce a single payload digest
pushd "$PAYLOAD_OUT" >/dev/null
PAYLOAD_HASH=$(sha256sum SHA256SUMS | awk '{print $1}')
echo "$PAYLOAD_HASH  SHA256SUMS" > payload.sha256
popd >/dev/null

echo ""
echo "Packaging payload tar and tar.gz..."
TAR_NAME="containai-payload-${VERSION}.tar"
TAR_PATH="$DEST_DIR/$TAR_NAME"
TAR_GZ_PATH="$DEST_DIR/$TAR_NAME.gz"
rm -f "$TAR_PATH" "$TAR_GZ_PATH"
(cd "$PAYLOAD_OUT" && tar -cf "$TAR_PATH" .)
gzip -c "$TAR_PATH" > "$TAR_GZ_PATH"

if [[ -n "$ATTESTATION_FILE" ]]; then
    cp "$ATTESTATION_FILE" "$DEST_DIR/payload.attestation.intoto.jsonl"
fi

echo ""
echo "Payload outputs:"
echo " - $PAYLOAD_OUT"
echo " - $TAR_PATH (for artifact upload; actions will zip it)"
echo " - $TAR_GZ_PATH (for release asset)"
echo "Upload the tar as the artifact; attach the .tar.gz to the release. GitHub will handle attestation on upload."
