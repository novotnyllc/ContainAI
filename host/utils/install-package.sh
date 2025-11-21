#!/usr/bin/env bash
# Installs a Coding Agents bundle from GitHub Releases (or local asset dir).
# Bundle layout:
#   coding-agents-<version>.tar.gz containing payload.tar.gz, payload.sha256,
#   attestation.intoto.jsonl, cosign-root.pem.
# Payload layout:
#   host/, agent-configs/, config.toml, sbom.json, tools/cosign-root.pem, SHA256SUMS.
# Steps:
#   - Download bundle (or use --asset-dir)
#   - Verify payload.sha256 vs payload.tar.gz
#   - Validate attestation with system openssl against Fulcio root
#   - Extract payload, check SHA256SUMS via integrity-check, blue/green swap.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=host/utils/common-functions.sh
source "$SCRIPT_DIR/common-functions.sh"

VERSION=""
REPO="${GITHUB_REPOSITORY:-}"
INSTALL_ROOT="/opt/coding-agents"
ASSET_DIR=""
ALLOW_NONROOT=0
VERIFY_ONLY=0

print_help() {
    cat <<'EOF'
Usage: install-package.sh --version TAG [--repo OWNER/REPO] [--asset-dir PATH] [--install-root PATH] [--allow-nonroot] [--verify-only]

Behavior:
  - Downloads release assets (tarball, SHA256SUMS, sbom.json, attestation.intoto.jsonl) from GitHub Releases
  - Verifies SHA256, attempts GitHub attestation verification, runs integrity-check (prod)
  - Extracts into <install-root>/releases/<version> and flips current/previous symlinks

Options:
  --version TAG      Release tag to install
  --repo OWNER/REPO  GitHub repo (default: GITHUB_REPOSITORY env)
  --asset-dir PATH   Use local assets (tarball/SHA256SUMS/sbom/attestation) instead of downloading (testing)
  --install-root P   Install prefix (default: /opt/coding-agents)
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

if [[ -n "$ASSET_DIR" ]]; then
    BUNDLE_DIR="$ASSET_DIR"
else
    BUNDLE_DIR="$(mktemp -d)"
    trap 'rm -rf "$BUNDLE_DIR"' EXIT
fi
BUNDLE_PATH="$BUNDLE_DIR/coding-agents-${VERSION}.tar.gz"
BUNDLE_ATTEST_PATH="$BUNDLE_DIR/coding-agents-${VERSION}.tar.gz.intoto.jsonl"
EXTRACT_DIR="$(mktemp -d)"
PAYLOAD_PATH="$EXTRACT_DIR/payload.tar.gz"
PAYLOAD_SHA_PATH="$EXTRACT_DIR/payload.sha256"
ATTESTATION_PATH="$EXTRACT_DIR/attestation.intoto.jsonl"
COSIGN_ROOT="${SCRIPT_DIR}/cosign-root.pem"

require_gh() {
    command -v gh >/dev/null 2>&1 || die "gh CLI required (install from https://cli.github.com/)"
}

fetch_asset() {
    local name="$1"
    local dest="$2"
    local token="${GITHUB_TOKEN:-}"
    local url="https://github.com/${REPO}/releases/download/${VERSION}/${name}"
    local headers=()
    if [[ -n "$token" ]]; then
        headers+=("-H" "Authorization: Bearer $token")
    fi
    echo "⬇️  Fetching $name"
    curl -fL "${headers[@]}" -o "$dest" "$url"
}

download_release_assets() {
    if [[ -n "$ASSET_DIR" ]]; then
        [[ -f "$BUNDLE_PATH" ]] || die "Bundle not found in $ASSET_DIR"
        [[ -f "$BUNDLE_ATTEST_PATH" ]] || echo "⚠️  Attestation asset missing in $ASSET_DIR (dev mode?)"
        return
    fi
    fetch_asset "coding-agents-${VERSION}.tar.gz" "$BUNDLE_PATH"
    fetch_asset "bundle-provenance.intoto.jsonl" "$BUNDLE_ATTEST_PATH"
    [[ -f "$BUNDLE_PATH" ]] || die "Bundle not found in release"
    [[ -f "$BUNDLE_ATTEST_PATH" ]] || die "Attestation not found in release assets"
}

extract_bundle() {
    tar -xzf "$BUNDLE_PATH" -C "$EXTRACT_DIR"
    [[ -f "$PAYLOAD_PATH" ]] || die "Payload tarball missing inside bundle"
    [[ -f "$PAYLOAD_SHA_PATH" ]] || die "payload.sha256 missing inside bundle"
    [[ -f "$ATTESTATION_PATH" ]] || die "Attestation missing inside bundle"
}

verify_payload_hash() {
    local expected
    expected=$(awk '/payload\.tar\.gz/ {print $1}' "$PAYLOAD_SHA_PATH" || true)
    [[ -n "$expected" ]] || die "Expected hash for payload.tar.gz not found in payload.sha256"
    local actual
    actual=$(sha256sum "$PAYLOAD_PATH" | awk '{print $1}')
    if [[ "$actual" != "$expected" ]]; then
        die "Payload hash mismatch; expected $expected got $actual"
    fi
    echo "✅ SHA256 verified for payload.tar.gz"
}

verify_attestation() {
    [[ -f "$BUNDLE_ATTEST_PATH" ]] || die "Attestation file missing; cannot verify provenance"
    command -v openssl >/dev/null 2>&1 || die "openssl required for attestation verification"

    extract_field() {
        local key="$1" file="$2"
        grep -o "\"${key}\":[^\"]*\"[^\"]*\"" "$file" | head -1 | sed "s/.*\"${key}\":\"//; s/\"$//"
    }

    if grep -q '"attestation":"placeholder"' "$BUNDLE_ATTEST_PATH"; then
        echo "⚠️  Placeholder attestation detected (dev build); skipping attestation verification"
        return
    fi

    att_payload=$(extract_field "payload" "$BUNDLE_ATTEST_PATH")
    att_sig=$(extract_field "sig" "$BUNDLE_ATTEST_PATH")
    att_cert=$(extract_field "cert" "$BUNDLE_ATTEST_PATH" | sed 's#\\/#/#g')
    [[ -n "$att_payload" && -n "$att_sig" && -n "$att_cert" ]] || die "Attestation missing payload/sig/cert"

    local cert_path="$EXTRACT_DIR/cert.pem"
    printf '%b' "${att_cert//\\r\\n/\\n}" | sed 's/\\n/\n/g' > "$cert_path"
    openssl verify -CAfile "$COSIGN_ROOT" "$cert_path" >/dev/null 2>&1 || die "Certificate chain validation failed"

    local payload_bin="$EXTRACT_DIR/payload.bin"
    printf '%s' "$att_payload" | base64 -d > "$payload_bin" || die "Unable to decode attestation payload"

    expected_sha=$(grep -o '"sha256":"[^"]*' "$payload_bin" | head -1 | sed 's/.*"sha256":"//')
    [[ -n "$expected_sha" ]] || die "No digest in attestation payload"
    actual_sha=$(sha256sum "$BUNDLE_PATH" | awk '{print $1}')
    [[ "$expected_sha" == "$actual_sha" ]] || die "Attested digest mismatch (expected $expected_sha got $actual_sha)"

    local sig_bin="$EXTRACT_DIR/payload.sig"
    printf '%s' "$att_sig" | base64 -d > "$sig_bin" || die "Unable to decode signature"
    openssl dgst -sha256 -verify <(openssl x509 -in "$cert_path" -pubkey -noout) -signature "$sig_bin" "$payload_bin" >/dev/null 2>&1 || die "Signature verification failed"

    if ! openssl x509 -in "$cert_path" -noout -text 2>/dev/null | grep -q "URI:https://token.actions.githubusercontent.com"; then
        die "OIDC issuer not trusted in certificate"
    fi
    echo "✅ Attestation verified via system openssl"
}

copy_release_metadata() {
    local target_dir="$1"
    cp "$PAYLOAD_PATH" "$target_dir/$(basename "$PAYLOAD_PATH")"
    if [[ -f "$EXTRACT_DIR/cosign-root.pem" ]]; then
        cp "$EXTRACT_DIR/cosign-root.pem" "$target_dir/cosign-root.pem"
    elif [[ -f "$COSIGN_ROOT" ]]; then
        cp "$COSIGN_ROOT" "$target_dir/cosign-root.pem"
    fi
    if [[ -f "$ATTESTATION_PATH" ]]; then
        cp "$ATTESTATION_PATH" "$target_dir/attestation.intoto.jsonl"
    fi
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

download_release_assets
extract_bundle
verify_payload_hash
verify_attestation

echo "📦 Installing Coding Agents $VERSION to $RELEASE_ROOT"
rm -rf "$RELEASE_ROOT"
mkdir -p "$RELEASE_ROOT"

tar -xzf "$PAYLOAD_PATH" -C "$RELEASE_ROOT" --strip-components=1
copy_release_metadata "$RELEASE_ROOT"

if ! "$SCRIPT_DIR/integrity-check.sh" --mode prod --root "$RELEASE_ROOT" --sums "$RELEASE_ROOT/SHA256SUMS"; then
    die "Integrity validation failed after extraction"
fi

swap_symlinks "$RELEASE_ROOT"

cat > "$RELEASE_ROOT/install.meta" <<EOF
version=$VERSION
installed_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
payload=$(basename "$PAYLOAD_PATH")
bundle=$(basename "$BUNDLE_PATH")
repo=$REPO
EOF

log_security_event "package-install" "$(printf '{"version":"%s","root":"%s"}' "$(json_escape_string "$VERSION")" "$(json_escape_string "$RELEASE_ROOT")")" >/dev/null 2>&1 || true

echo "✅ Install complete. Current -> $RELEASE_ROOT"
echo "Previous release preserved at $INSTALL_ROOT/previous (if existed)."
