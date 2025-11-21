#!/usr/bin/env bash
# Bootstrap installer for ContainAI releases.
# Usage (latest):   curl -fsSL https://raw.githubusercontent.com/ContainAI/ContainAI/main/install.sh | bash
# Usage (pinned):   curl -fsSL https://raw.githubusercontent.com/ContainAI/ContainAI/main/install.sh | bash -s -- --version vX.Y.Z

set -euo pipefail

DEFAULT_REPO="ContainAI/ContainAI"
REPO="${CONTAINAI_REPO:-$DEFAULT_REPO}"
VERSION="${CONTAINAI_VERSION:-}"
INSTALL_ROOT="${CONTAINAI_INSTALL_ROOT:-/opt/containai}"
TOKEN="${GITHUB_TOKEN:-}"

usage() {
    cat <<'EOF'
ContainAI installer

Options:
  --version TAG           Release tag to install (defaults to latest)
  --install-root PATH     Install prefix (default: /opt/containai)
  --repo OWNER/REPO       Override repo (default: ContainAI/ContainAI)
  -h, --help              Show this help

Environment overrides: CONTAINAI_VERSION, CONTAINAI_INSTALL_ROOT, CONTAINAI_REPO, GITHUB_TOKEN
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version) VERSION="$2"; shift 2 ;;
        --install-root) INSTALL_ROOT="$2"; shift 2 ;;
        --repo) REPO="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
    esac
done

fetch_latest_tag() {
    python3 - <<PY
import json, os, sys, urllib.request
repo = os.environ.get("REPO")
token = os.environ.get("TOKEN")
req = urllib.request.Request(f"https://api.github.com/repos/{repo}/releases/latest")
if token:
    req.add_header("Authorization", f"Bearer {token}")
with urllib.request.urlopen(req, timeout=10) as resp:
    data = json.load(resp)
    print(data.get("tag_name",""))
PY
}

if [[ -z "$VERSION" ]]; then
    VERSION="$(REPO="$REPO" TOKEN="$TOKEN" fetch_latest_tag || true)"
    if [[ -z "$VERSION" ]]; then
        echo "❌ Unable to determine latest release. Pass --version vX.Y.Z." >&2
        exit 1
    fi
fi

ASSET_NAME="containai-payload-${VERSION}.tar.gz"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

echo "⬇️  Downloading ContainAI $VERSION from $REPO..."
HDRS=()
if [[ -n "$TOKEN" ]]; then
    HDRS+=("-H" "Authorization: Bearer $TOKEN")
fi
ASSET_PATH="$WORKDIR/$ASSET_NAME"
if ! curl -fL "${HDRS[@]}" -o "$ASSET_PATH" "https://github.com/$REPO/releases/download/$VERSION/$ASSET_NAME"; then
    echo "❌ Failed to download asset $ASSET_NAME from $REPO" >&2
    exit 1
fi

PAYLOAD_DIR="$WORKDIR/payload"
mkdir -p "$PAYLOAD_DIR"
tar -xzf "$ASSET_PATH" -C "$PAYLOAD_DIR"

INSTALLER="$PAYLOAD_DIR/host/utils/install-release.sh"
if [[ ! -x "$INSTALLER" ]]; then
    echo "❌ Installer not found inside payload: $INSTALLER" >&2
    exit 1
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
        echo "❌ sudo not available; rerun as root." >&2
        exit 1
    fi
fi

echo "▶ Running installer..."
"${SUDO_CMD[@]}" "$INSTALLER" --version "$VERSION" --asset-dir "$PAYLOAD_DIR" --install-root "$INSTALL_ROOT"

echo "✅ ContainAI $VERSION installed to $INSTALL_ROOT"
