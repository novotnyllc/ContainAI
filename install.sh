#!/usr/bin/env bash
# Bootstrap installer for ContainAI releases using public GHCR metadata/payload artifacts.
# Usage (channel): curl -fsSL https://raw.githubusercontent.com/ContainAI/ContainAI/main/install.sh | bash
# Usage (pinned):  curl -fsSL https://raw.githubusercontent.com/ContainAI/ContainAI/main/install.sh | bash -s -- --version vX.Y.Z

set -euo pipefail

DEFAULT_REPO="ContainAI/ContainAI"
DEFAULT_CHANNEL="dev"
REGISTRY_HOST="${CONTAINAI_REGISTRY:-ghcr.io}"
REPO="${CONTAINAI_REPO:-$DEFAULT_REPO}"
CHANNEL="${CONTAINAI_CHANNEL:-$DEFAULT_CHANNEL}"
VERSION="${CONTAINAI_VERSION:-}"
INSTALL_ROOT="${CONTAINAI_INSTALL_ROOT:-/opt/containai}"
NAMESPACE_OVERRIDE="${CONTAINAI_REGISTRY_NAMESPACE:-}"

usage() {
    cat <<'EOF'
ContainAI installer

Options:
  --channel NAME         Channel to install (dev|nightly|prod, default: dev)
  --version TAG          Release tag to install (overrides channel/metadata)
  --install-root PATH    Install prefix (default: /opt/containai)
  --repo OWNER/REPO      Override repo (default: ContainAI/ContainAI)
  --registry-namespace N Override GHCR namespace/owner (default derived from repo owner)
  -h, --help             Show this help

Environment overrides: CONTAINAI_CHANNEL, CONTAINAI_VERSION, CONTAINAI_INSTALL_ROOT, CONTAINAI_REPO,
CONTAINAI_REGISTRY, CONTAINAI_REGISTRY_NAMESPACE
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --channel) CHANNEL="$2"; shift 2 ;;
        --version) VERSION="$2"; shift 2 ;;
        --install-root) INSTALL_ROOT="$2"; shift 2 ;;
        --repo) REPO="$2"; shift 2 ;;
        --registry-namespace) NAMESPACE_OVERRIDE="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
    esac
done

REPO_OWNER="$(echo "$REPO" | cut -d/ -f1)"
NAMESPACE="${NAMESPACE_OVERRIDE:-$(echo "$REPO_OWNER" | tr '[:upper:]' '[:lower:]')}"
METADATA_REPO="${NAMESPACE}/containai-metadata"
PAYLOAD_REPO="${NAMESPACE}/containai-payload"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

die() { echo "❌ $*" >&2; exit 1; }

require_tool() {
    command -v "$1" >/dev/null 2>&1 || die "$1 is required for installation"
}

oci_fetch_manifest() {
    local repo="$1" ref="$2" dest="$3"
    curl -fsSL -H "Accept: application/vnd.oci.image.manifest.v1+json, application/vnd.oci.artifact.manifest.v1+json" \
        "https://${REGISTRY_HOST}/v2/${repo}/manifests/${ref}" -o "$dest"
}

oci_layer_digest() {
    local manifest_path="$1" preferred="$2" fallback_prefix="${3:-application/}"
    python3 - "$manifest_path" "$preferred" "$fallback_prefix" <<'PY'
import json, sys
path, preferred, prefix = sys.argv[1:]
with open(path, "r", encoding="utf-8") as handle:
    manifest = json.load(handle)
layers = manifest.get("layers") or []
chosen = None
for layer in layers:
    if layer.get("mediaType") == preferred:
        chosen = layer
        break
if chosen is None:
    for layer in layers:
        mt = layer.get("mediaType","")
        if mt.startswith(prefix):
            chosen = layer
            break
if not chosen:
    sys.exit(1)
digest = chosen.get("digest")
if not digest:
    sys.exit(1)
print(digest)
PY
}

oci_fetch_blob() {
    local repo="$1" digest="$2" dest="$3"
    curl -fsSL "https://${REGISTRY_HOST}/v2/${repo}/blobs/${digest}" -o "$dest"
}

verify_digest() {
    local file="$1" expected="$2"
    python3 - "$file" "$expected" <<'PY'
import hashlib, os, sys
file, expected = sys.argv[1:]
expected = expected.split("sha256:",1)[-1]
h = hashlib.sha256()
with open(file, "rb") as handle:
    for chunk in iter(lambda: handle.read(1024 * 1024), b""):
        h.update(chunk)
actual = h.hexdigest()
if actual != expected:
    sys.stderr.write(f"❌ Digest mismatch for {file}: expected sha256:{expected}, got sha256:{actual}\n")
    sys.exit(1)
print(f"✅ Verified {os.path.basename(file)} sha256:{actual}")
PY
}

fetch_metadata() {
    local channel="$1" manifest_path="$WORKDIR/metadata-manifest.json"
    if ! oci_fetch_manifest "$METADATA_REPO" "$channel" "$manifest_path"; then
        # fallback to consolidated tag if available
        if ! oci_fetch_manifest "$METADATA_REPO" "channels" "$manifest_path"; then
            return 1
        fi
    fi
    local layer_digest
    if ! layer_digest=$(oci_layer_digest "$manifest_path" "application/json" "application/"); then
        return 1
    fi
    local metadata_path="$WORKDIR/metadata.json"
    oci_fetch_blob "$METADATA_REPO" "$layer_digest" "$metadata_path"
    METADATA_JSON="$metadata_path"
    return 0
}

parse_metadata_field() {
    local field="$1"
    python3 - "$METADATA_JSON" "$field" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], "r", encoding="utf-8"))
field = sys.argv[2]
val = data
for part in field.split("."):
    if isinstance(val, dict):
        val = val.get(part)
    else:
        val = None
        break
print(val if val is not None else "")
PY
}

require_tool curl
require_tool python3
require_tool tar

METADATA_JSON=""
PAYLOAD_REF=""
PAYLOAD_DIGEST=""

if [[ -z "$VERSION" ]]; then
    if fetch_metadata "$CHANNEL"; then
        VERSION="$(parse_metadata_field "version")"
        PAYLOAD_REF="$(parse_metadata_field "payload.ref")"
        PAYLOAD_DIGEST="$(parse_metadata_field "payload.digest")"
        echo "ℹ️  Resolved channel '${CHANNEL}' to version '${VERSION:-$CHANNEL}'"
    else
        echo "⚠️  Unable to fetch channel metadata; falling back to channel tag '${CHANNEL}'" >&2
        VERSION="$CHANNEL"
    fi
fi

[[ -n "$VERSION" ]] || die "Unable to determine version to install"
ASSET_NAME="containai-payload-${VERSION}.tar.gz"

PAYLOAD_REF="${PAYLOAD_REF:-${REGISTRY_HOST}/${PAYLOAD_REPO}:${VERSION}}"
PAYLOAD_TARGET="${PAYLOAD_DIGEST:-$VERSION}"

echo "⬇️  Fetching payload manifest for ${PAYLOAD_REF} (ref ${PAYLOAD_TARGET})"
PAYLOAD_MANIFEST="$WORKDIR/payload-manifest.json"
oci_fetch_manifest "$PAYLOAD_REPO" "$PAYLOAD_TARGET" "$PAYLOAD_MANIFEST" || die "Failed to fetch payload manifest from GHCR"

PAYLOAD_LAYER_DIGEST=$(oci_layer_digest "$PAYLOAD_MANIFEST" "application/vnd.containai.payload.layer.v1+gzip" "application/") || die "Unable to locate payload layer"
if ! SBOM_LAYER_DIGEST=$(oci_layer_digest "$PAYLOAD_MANIFEST" "application/vnd.cyclonedx+json" "application/"); then
    SBOM_LAYER_DIGEST=""
fi

PAYLOAD_TAR="$WORKDIR/$ASSET_NAME"
echo "⬇️  Downloading payload blob ${PAYLOAD_LAYER_DIGEST}"
oci_fetch_blob "$PAYLOAD_REPO" "$PAYLOAD_LAYER_DIGEST" "$PAYLOAD_TAR"
verify_digest "$PAYLOAD_TAR" "$PAYLOAD_LAYER_DIGEST"

if [[ -n "$SBOM_LAYER_DIGEST" ]]; then
    SBOM_PATH="$WORKDIR/payload.sbom.json"
    echo "⬇️  Downloading payload SBOM ${SBOM_LAYER_DIGEST}"
    oci_fetch_blob "$PAYLOAD_REPO" "$SBOM_LAYER_DIGEST" "$SBOM_PATH"
    verify_digest "$SBOM_PATH" "$SBOM_LAYER_DIGEST"
fi

PAYLOAD_DIR="$WORKDIR/payload"
mkdir -p "$PAYLOAD_DIR"
tar -xzf "$PAYLOAD_TAR" -C "$PAYLOAD_DIR"

INSTALLER="$PAYLOAD_DIR/host/utils/install-release.sh"
if [[ ! -x "$INSTALLER" ]]; then
    die "Installer not found inside payload: $INSTALLER"
fi

SUDO_CMD=()
if [[ $(id -u) -ne 0 ]]; then
    echo "This will install ContainAI $VERSION to $INSTALL_ROOT and load the AppArmor profile. Sudo is required."
    read -r -p "Proceed with sudo? [Y/n]: " reply
    if [[ "$reply" =~ ^[Nn] ]]; then
        echo "Cancelled."
        exit 1
    fi
    if command -v sudo >/dev/null 2>&1; then
        SUDO_CMD=(sudo)
    else
        die "sudo not available; rerun as root."
    fi
fi

echo "▶ Running installer..."
"${SUDO_CMD[@]}" "$INSTALLER" --version "$VERSION" --asset-dir "$PAYLOAD_DIR" --install-root "$INSTALL_ROOT" --repo "$REPO"

echo "✅ ContainAI $VERSION installed to $INSTALL_ROOT"
