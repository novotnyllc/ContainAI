#!/usr/bin/env bash
# Installs the ContainAI release payload (tar.gz) from GitHub Releases or a local asset dir.
# Artifact layout (tar contents):
#   host/, agent-configs/, config.toml, sbom.json, tools/cosign-root.pem, SHA256SUMS, payload.sha256
# Steps:
#   - Download artifact (tar.gz) or use --asset-dir
#   - Verify payload.sha256 against SHA256SUMS
#   - Run integrity-check, then flip current/previous symlinks
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=host/utils/common-functions.sh
source "$SCRIPT_DIR/common-functions.sh"
# shellcheck source=host/utils/security-enforce.sh
source "$SCRIPT_DIR/security-enforce.sh"

VERSION=""
REPO="${GITHUB_REPOSITORY:-}"
INSTALL_ROOT="/opt/containai"
ASSET_DIR=""
ALLOW_NONROOT=0
VERIFY_ONLY=0
PAYLOAD_ASSET_NAME=""

print_help() {
    cat <<'EOF'
Usage: install-release.sh --version TAG [--repo OWNER/REPO] [--asset-dir PATH] [--install-root PATH] [--allow-nonroot] [--verify-only]

Behavior:
  - Downloads the versioned payload artifact (tar.gz) from GitHub Releases (or uses --asset-dir)
  - Verifies payload.sha256 against SHA256SUMS
  - Extracts into <install-root>/releases/<version> and flips current/previous symlinks

Options:
  --version TAG      Release tag to install
  --repo OWNER/REPO  GitHub repo (default: GITHUB_REPOSITORY env)
  --asset-dir PATH   Use local assets (tarball/SHA256SUMS/sbom/attestation) instead of downloading (testing)
  --install-root P   Install prefix (default: /opt/containai)
  --allow-nonroot    Permit non-root installs (testing only)
  --verify-only      Only verify current install (no download/extract)
EOF
}

die() { echo "❌ $*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)
            VERSION="$2"; shift 2 ;;
        --repo)
            REPO="$2"; shift 2 ;;
        --asset-dir)
            ASSET_DIR="$2"; shift 2 ;;
        --install-root)
            INSTALL_ROOT="$2"; shift 2 ;;
        --allow-nonroot)
            ALLOW_NONROOT=1; shift ;;
        --verify-only)
            VERIFY_ONLY=1; shift ;;
        -h|--help)
            print_help; exit 0 ;;
        *)
            die "Unknown argument: $1"
            ;;
    esac
done

[[ -n "$VERSION" ]] || die "--version is required"
[[ -n "$REPO" ]] || die "--repo or GITHUB_REPOSITORY env is required"
PAYLOAD_ASSET_NAME="${CONTAINAI_PAYLOAD_ASSET:-containai-payload-${VERSION}.tar.gz}"

if [[ $ALLOW_NONROOT -eq 0 ]] && [[ $(id -u) -ne 0 ]]; then
    die "System installs must run as root (use --allow-nonroot only for tests)"
fi

install_parent="$(cd "$(dirname "$INSTALL_ROOT")" && pwd)"
if [[ $ALLOW_NONROOT -eq 0 ]]; then
    if [[ ! -d "$install_parent" ]]; then
        mkdir -p "$install_parent"
    fi
    if [[ "$install_parent" =~ ^"$HOME" ]]; then
        die "Install root cannot live under the current user's home directory"
    fi
    owner=$(stat -c "%U" "$install_parent" 2>/dev/null || echo "unknown")
    if [[ "$owner" != "root" ]]; then
        die "Install root parent must be owned by root (found owner: $owner)"
    fi
else
    mkdir -p "$install_parent"
fi

RELEASE_ROOT="$INSTALL_ROOT/releases/$VERSION"
mkdir -p "$INSTALL_ROOT/releases"

EXTRACT_DIR="$(mktemp -d)"
PAYLOAD_DIR=""
PAYLOAD_SHA_PATH=""
SHA256SUMS_PATH=""

find_payload_dir() {
    local base="$1"
    local sha_file
    sha_file=$(find "$base" -type f -name "SHA256SUMS" -print -quit 2>/dev/null || true)
    if [[ -z "$sha_file" ]]; then
        die "SHA256SUMS not found in payload assets"
    fi
    PAYLOAD_DIR="$(cd "$(dirname "$sha_file")" && pwd)"
    PAYLOAD_SHA_PATH="$PAYLOAD_DIR/payload.sha256"
    SHA256SUMS_PATH="$sha_file"
    [[ -f "$PAYLOAD_SHA_PATH" ]] || die "payload.sha256 missing alongside SHA256SUMS"
}

extract_payload_asset() {
    local asset_path="$1"
    local dest="$2"
    mkdir -p "$dest"
    tar -xzf "$asset_path" -C "$dest"
}

locate_or_fetch_payload() {
    local asset_zip=""
    if [[ -n "$ASSET_DIR" ]]; then
        if [[ -f "$ASSET_DIR/$PAYLOAD_ASSET_NAME" ]]; then
            asset_zip="$ASSET_DIR/$PAYLOAD_ASSET_NAME"
        else
            # asset dir may already contain extracted payload
            if find "$ASSET_DIR" -type f -name "SHA256SUMS" | grep -q .; then
                find_payload_dir "$ASSET_DIR"
                return
            fi
        fi
    fi

    if [[ -z "$asset_zip" ]]; then
        asset_zip="$EXTRACT_DIR/$PAYLOAD_ASSET_NAME"
        local token="${GITHUB_TOKEN:-}"
        local headers=()
        if [[ -n "$token" ]]; then
            headers+=("-H" "Authorization: Bearer $token")
        fi
        echo "⬇️  Fetching $PAYLOAD_ASSET_NAME from $REPO@$VERSION"
        curl -fL "${headers[@]}" -o "$asset_zip" "https://github.com/${REPO}/releases/download/${VERSION}/${PAYLOAD_ASSET_NAME}"
    fi

    extract_payload_asset "$asset_zip" "$EXTRACT_DIR/payload"
    find_payload_dir "$EXTRACT_DIR/payload"
}

verify_payload_hash() {
    local expected
    expected=$(awk '/SHA256SUMS/ {print $1}' "$PAYLOAD_SHA_PATH" || true)
    [[ -n "$expected" ]] || die "Expected hash for SHA256SUMS not found in payload.sha256"
    local actual
    actual=$(sha256sum "$SHA256SUMS_PATH" | awk '{print $1}')
    if [[ "$actual" != "$expected" ]]; then
        die "Payload hash mismatch; expected $expected got $actual"
    fi
    echo "✅ SHA256 verified for payload contents"
}

swap_symlinks() {
    local current_link="$INSTALL_ROOT/current"
    local previous_link="$INSTALL_ROOT/previous"
    local new_target="$1"
    if [[ -L "$current_link" ]]; then
        local current_target
        current_target="$(readlink -f "$current_link")"
        [[ -n "$current_target" ]] && ln -sfn "$current_target" "$previous_link"
    fi
    ln -sfn "$new_target" "$current_link"
}

if [[ $VERIFY_ONLY -eq 1 ]]; then
    echo "🔍 Verifying existing install at $INSTALL_ROOT/current"
    if [[ ! -L "$INSTALL_ROOT/current" ]]; then
        die "No current symlink found under $INSTALL_ROOT"
    fi
    current_target="$(readlink -f "$INSTALL_ROOT/current")"
    [[ -d "$current_target" ]] || die "Current symlink target missing: $current_target"
    if ! "$SCRIPT_DIR/integrity-check.sh" --mode prod --root "$current_target" --sums "$current_target/SHA256SUMS"; then
        die "Integrity check failed for $current_target"
    fi
    echo "✅ Existing install verified."
    exit 0
fi

locate_or_fetch_payload
verify_payload_hash

echo "📦 Installing ContainAI $VERSION to $RELEASE_ROOT"
rm -rf "$RELEASE_ROOT"
mkdir -p "$RELEASE_ROOT"
rsync -a "$PAYLOAD_DIR"/ "$RELEASE_ROOT"/

# Write profile manifest for runtime freshness checks
enforce_security_profiles_strict "$RELEASE_ROOT"

if ! "$SCRIPT_DIR/integrity-check.sh" --mode prod --root "$RELEASE_ROOT" --sums "$RELEASE_ROOT/SHA256SUMS"; then
    die "Integrity validation failed after extraction"
fi

swap_symlinks "$RELEASE_ROOT"

cat > "$RELEASE_ROOT/install.meta" <<EOF
version=$VERSION
installed_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
payload_asset=$PAYLOAD_ASSET_NAME
repo=$REPO
EOF

log_security_event "package-install" "$(printf '{"version":"%s","root":"%s"}' "$(json_escape_string "$VERSION")" "$(json_escape_string "$RELEASE_ROOT")")" >/dev/null 2>&1 || true

echo "✅ Install complete. Current -> $RELEASE_ROOT"
echo "Previous release preserved at $INSTALL_ROOT/previous (if existed)."
