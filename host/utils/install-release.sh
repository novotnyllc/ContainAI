#!/usr/bin/env bash
# Installs the ContainAI release transport tarball from GitHub Releases or a local asset dir.
# Artifact layout:
#   Transport tar.gz: host/, agent-configs/, config.toml, docs, payload.sbom.json, payload.sbom.json.intoto.jsonl, SHA256SUMS, payload.sha256, tools/cosign-root.pem
# Steps:
#   - Download transport tar.gz (or use --asset-dir) and extract payload/
#   - Verify SHA256SUMS over extracted files
#   - Run integrity-check, then flip current/previous symlinks
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=host/utils/common-functions.sh
source "$SCRIPT_DIR/common-functions.sh"
# shellcheck source=host/utils/security-enforce.sh
source "$SCRIPT_DIR/security-enforce.sh"

INSTALLER_SELF_SHA256="__INSTALLER_SELF_SHA256__"
SELF_HASH_REDACTION='INSTALLER_SELF_SHA256="__REDACTED__"'
COSIGN_ROOT_EXPECTED_SHA256="__COSIGN_ROOT_SHA256__"
COSIGN_ROOT_URL="__COSIGN_ROOT_URL__"
TRUST_ANCHOR_PATH=""

VERSION=""
REPO="${GITHUB_REPOSITORY:-}"
INSTALL_ROOT="/opt/containai"
ASSET_DIR=""
VERIFY_ONLY=0
PAYLOAD_ASSET_NAME=""
TRANSPORT_ASSET_PATH=""
TRANSPORT_ATTEST_PATH=""
CHANNEL="prod"

print_help() {
    cat <<'EOF'
Usage: install-release.sh --version TAG [--repo OWNER/REPO] [--asset-dir PATH] [--install-root PATH] [--verify-only]

Behavior:
  - Downloads the versioned payload artifact (tar.gz) from GitHub Releases (or uses --asset-dir)
  - Verifies payload.sha256 against SHA256SUMS
  - Extracts into <install-root>/releases/<version> and flips current/previous symlinks

Options:
  --version TAG      Release tag to install
  --repo OWNER/REPO  GitHub repo (default: GITHUB_REPOSITORY env)
  --asset-dir PATH   Use local assets (tarball/SHA256SUMS/sbom/attestation) instead of downloading (testing)
  --install-root P   Install prefix (default: /opt/containai)
  --verify-only      Only verify current install (no download/extract)
EOF
}

die() { echo "❌ $*" >&2; exit 1; }

verify_self_integrity() {
    if [[ "$INSTALLER_SELF_SHA256" == "__INSTALLER_SELF_SHA256__" ]]; then
        die "Installer self-hash not injected; repackage artifacts."
    fi
    local computed
    computed=$(sed "s/^INSTALLER_SELF_SHA256=.*/$SELF_HASH_REDACTION/" "$0" | sha256sum | awk '{print $1}')
    if [[ "$computed" != "$INSTALLER_SELF_SHA256" ]]; then
        die "Installer integrity check failed; expected $INSTALLER_SELF_SHA256 got $computed"
    fi
}

fetch_trust_anchor() {
    if [[ "$COSIGN_ROOT_URL" == "__COSIGN_ROOT_URL__" ]]; then
        die "cosign root URL not injected; repackage artifacts."
    fi
    if [[ "$COSIGN_ROOT_EXPECTED_SHA256" == "__COSIGN_ROOT_SHA256__" ]]; then
        die "cosign root hash not injected; repackage artifacts."
    fi
    local dest
    dest="$(mktemp "$EXTRACT_DIR/cosign-root.XXXXXX.pem")"
    echo "⬇️  Fetching cosign root from pinned URL"
    if ! curl -fL -o "$dest" "$COSIGN_ROOT_URL"; then
        die "Failed to download cosign root from $COSIGN_ROOT_URL"
    fi
    local cosign_hash
    cosign_hash=$(sha256sum "$dest" | awk '{print $1}')
    if [[ "$cosign_hash" != "$COSIGN_ROOT_EXPECTED_SHA256" ]]; then
        die "cosign-root.pem hash mismatch; expected $COSIGN_ROOT_EXPECTED_SHA256 got $cosign_hash"
    fi
    TRUST_ANCHOR_PATH="$dest"
}

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
PAYLOAD_ASSET_NAME="${CONTAINAI_PAYLOAD_ASSET:-containai-${VERSION}.tar.gz}"

verify_self_integrity

if [[ $(id -u) -ne 0 ]]; then
    die "System installs must run as root"
fi

install_parent="$(cd "$(dirname "$INSTALL_ROOT")" && pwd)"
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
    if [[ ! -f "$PAYLOAD_SHA_PATH" ]]; then
        echo "⚠️  payload.sha256 missing; continuing with SHA256SUMS only" >&2
    fi
    SBOM_PATH="$PAYLOAD_DIR/payload.sbom.json"
    SBOM_ATTEST_PATH="$PAYLOAD_DIR/payload.sbom.json.intoto.jsonl"
    [[ -f "$SBOM_PATH" ]] || die "payload.sbom.json missing in payload assets"
}

extract_tarball() {
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
        elif find "$ASSET_DIR" -type f -name "SHA256SUMS" | grep -q .; then
            TRANSPORT_ASSET_PATH="$ASSET_DIR/$PAYLOAD_ASSET_NAME"
            find_payload_dir "$ASSET_DIR"
            return
        fi
    fi

    if [[ -z "$asset_zip" ]]; then
        asset_zip="$EXTRACT_DIR/$PAYLOAD_ASSET_NAME"
        echo "⬇️  Fetching $PAYLOAD_ASSET_NAME from $REPO@$VERSION"
        curl -fL -o "$asset_zip" "https://github.com/${REPO}/releases/download/${VERSION}/${PAYLOAD_ASSET_NAME}"
    fi
    TRANSPORT_ASSET_PATH="$asset_zip"
    TRANSPORT_ATTEST_PATH="${asset_zip}.intoto.jsonl"
    if [[ ! -f "$TRANSPORT_ATTEST_PATH" && -z "$ASSET_DIR" ]]; then
        curl -fL -o "$TRANSPORT_ATTEST_PATH" "https://github.com/${REPO}/releases/download/${VERSION}/${PAYLOAD_ASSET_NAME}.intoto.jsonl" 2>/dev/null || true
    fi

    extract_tarball "$asset_zip" "$EXTRACT_DIR/payload"
    find_payload_dir "$EXTRACT_DIR/payload"
}

detect_channel() {
    local profile="$PAYLOAD_DIR/host/profile.env"
    local channel_val="prod"
    if [[ -f "$profile" ]]; then
        # shellcheck disable=SC1090
        source "$profile"
        if [[ -n "${PROFILE:-}" ]]; then
            channel_val="$PROFILE"
        elif [[ -n "${CHANNEL:-}" ]]; then
            channel_val="$CHANNEL"
        fi
    fi
    case "$channel_val" in
        dev|nightly|prod) ;;
        *) channel_val="prod" ;;
    esac
    CHANNEL="$channel_val"
    echo "ℹ️  Detected channel: $CHANNEL"
}

fetch_trust_anchor() {
    if [[ "$COSIGN_ROOT_URL" == "__COSIGN_ROOT_URL__" ]]; then
        die "cosign root URL not injected; repackage artifacts."
    fi
    if [[ "$COSIGN_ROOT_EXPECTED_SHA256" == "__COSIGN_ROOT_SHA256__" ]]; then
        die "cosign root hash not injected; repackage artifacts."
    fi
    local dest
    dest="$(mktemp "$EXTRACT_DIR/cosign-root.XXXXXX.pem")"
    echo "⬇️  Fetching cosign root from pinned URL"
    if ! curl -fL -o "$dest" "$COSIGN_ROOT_URL"; then
        die "Failed to download cosign root from $COSIGN_ROOT_URL"
    fi
    local cosign_hash
    cosign_hash=$(sha256sum "$dest" | awk '{print $1}')
    if [[ "$cosign_hash" != "$COSIGN_ROOT_EXPECTED_SHA256" ]]; then
        die "cosign-root.pem hash mismatch; expected $COSIGN_ROOT_EXPECTED_SHA256 got $cosign_hash"
    fi
    TRUST_ANCHOR_PATH="$dest"
}

verify_payload_hash() {
    if [[ -f "$PAYLOAD_SHA_PATH" ]]; then
        local expected
        expected=$(awk '/SHA256SUMS/ {print $1}' "$PAYLOAD_SHA_PATH" || true)
        [[ -n "$expected" ]] || die "Expected hash for SHA256SUMS not found in payload.sha256"
        local actual
        actual=$(sha256sum "$SHA256SUMS_PATH" | awk '{print $1}')
        if [[ "$actual" != "$expected" ]]; then
            die "Payload hash mismatch; expected $expected got $actual"
        fi
        echo "✅ SHA256 verified for payload contents"
    fi
    local sbom_sum
    sbom_sum=$(awk '$NF=="./payload.sbom.json" || $NF=="payload.sbom.json" {print $1}' "$SHA256SUMS_PATH" || true)
    if [[ -n "$sbom_sum" ]]; then
        local sbom_actual
        sbom_actual=$(sha256sum "$SBOM_PATH" | awk '{print $1}')
        if [[ "$sbom_actual" != "$sbom_sum" ]]; then
            die "SBOM hash mismatch; expected $sbom_sum got $sbom_actual"
        fi
        echo "✅ SBOM verified against SHA256SUMS"
    else
        echo "⚠️  SBOM entry not present in SHA256SUMS; skipping SBOM hash verification" >&2
    fi
}

verify_dsse_attestation() {
    local expected_sha="$1" att="$2" cosign_root="$3" label="$4" expected_name_suffix="$5"
    if [[ "$CHANNEL" = "dev" ]]; then
        if [[ -z "$att" || ! -f "$att" ]]; then
            echo "⚠️  $label attestation missing; dev channel detected, skipping" >&2
        else
            echo "⚠️  Dev channel detected; skipping $label attestation verification" >&2
        fi
        return 0
    fi
    if [[ -z "$att" || ! -f "$att" ]]; then
        die "$label attestation missing at ${att:-<none>} (required for non-dev)"
    fi
    [[ -f "$cosign_root" ]] || die "cosign root not found at $cosign_root"

    local line payload_b64 payload_type sig_b64 leaf_b64
    line=$(head -n1 "$att" | tr -d '\n')
    payload_b64=$(printf '%s' "$line" | sed -n 's/.*"payload":"\([^"]*\)".*/\1/p')
    payload_type=$(printf '%s' "$line" | sed -n 's/.*"payloadType":"\([^"]*\)".*/\1/p')
    sig_b64=$(printf '%s' "$line" | sed -n 's/.*"sig":"\([^"]*\)".*/\1/p')
    leaf_b64=$(printf '%s' "$line" | sed -n 's/.*"rawBytes":"\([^"]*\)".*/\1/p')
    [[ -n "$payload_b64" && -n "$payload_type" && -n "$sig_b64" && -n "$leaf_b64" ]] || die "$label attestation missing required fields"

    local work payload_bin sig_bin leaf_der leaf_pem pub_pem pae_bin
    work=$(mktemp -d)
    payload_bin="$work/payload.bin"
    sig_bin="$work/sig.bin"
    leaf_der="$work/leaf.der"
    leaf_pem="$work/leaf.pem"
    pub_pem="$work/pub.pem"
    pae_bin="$work/pae.bin"

    printf '%s' "$payload_b64" | base64 -d > "$payload_bin" || die "Failed to decode payload"
    printf '%s' "$sig_b64" | base64 -d > "$sig_bin" || die "Failed to decode signature"
    printf '%s' "$leaf_b64" | base64 -d > "$leaf_der" || die "Failed to decode leaf cert"
    openssl x509 -inform der -in "$leaf_der" -out "$leaf_pem" >/dev/null 2>&1 || die "Failed to convert leaf cert"

    openssl verify -CAfile "$cosign_root" "$leaf_pem" >/dev/null 2>&1 || die "Certificate chain verification failed"
    openssl x509 -in "$leaf_pem" -pubkey -noout > "$pub_pem" 2>/dev/null || die "Failed to extract pubkey"

    local pt_len payload_len
    pt_len=${#payload_type}
    payload_len=$(wc -c < "$payload_bin" | tr -d ' ')
    # Build DSSE PAE: literal 'DSSEv1 ' + len(payloadType) + ' ' + payloadType + ' ' + len(payload) + ' ' + payload bytes
    {
        printf 'DSSEv1 %s %s %s ' "$pt_len" "$payload_type" "$payload_len"
        cat "$payload_bin"
    } > "$pae_bin"

    openssl dgst -sha256 -verify "$pub_pem" -signature "$sig_bin" "$pae_bin" >/dev/null 2>&1 || die "Signature verification failed"

    local payload_json subject_sha subject_name
    payload_json=$(tr -d '\n' < "$payload_bin")
    subject_sha=$(printf '%s' "$payload_json" | sed -n 's/.*"sha256":"\([^"]*\)".*/\1/p')
    subject_name=$(printf '%s' "$payload_json" | sed -n 's/.*"name":"\([^"]*\)".*/\1/p')
    [[ -n "$subject_sha" ]] || die "$label attestation missing subject sha"
    if [[ "$subject_sha" != "$expected_sha" ]]; then
        die "$label attestation sha mismatch: att=$subject_sha expected=$expected_sha"
    fi
    if [[ -n "$expected_name_suffix" && "${subject_name##*$expected_name_suffix}" = "$subject_name" ]]; then
        die "$label attestation subject name mismatch: got $subject_name expected suffix $expected_name_suffix"
    fi
    echo "✅ $label attestation: signature and subject digest verified"
    rm -rf "$work"
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
detect_channel
fetch_trust_anchor
RELEASE_ROOT="$INSTALL_ROOT/releases/$VERSION"
mkdir -p "$INSTALL_ROOT/releases"
if [[ -n "$TRANSPORT_ASSET_PATH" && -f "$TRANSPORT_ASSET_PATH" ]]; then
    transport_hash=$(sha256sum "$TRANSPORT_ASSET_PATH" | awk '{print $1}')
    verify_dsse_attestation "$transport_hash" "$TRANSPORT_ATTEST_PATH" "$TRUST_ANCHOR_PATH" "Transport" ""
else
    if [[ "$CHANNEL" = "dev" ]]; then
        echo "⚠️  Transport tarball not available; dev channel detected, skipping attestation verification" >&2
    else
        die "Transport tarball not available for attestation verification"
    fi
fi
verify_payload_hash
sbom_hash=$(sha256sum "$SBOM_PATH" | awk '{print $1}')
    verify_dsse_attestation "$sbom_hash" "$SBOM_ATTEST_PATH" "$TRUST_ANCHOR_PATH" "SBOM" "payload.sbom.json"

    echo "📦 Installing ContainAI $VERSION to $RELEASE_ROOT"
rm -rf "$RELEASE_ROOT"
mkdir -p "$RELEASE_ROOT"
rsync -a "$PAYLOAD_DIR"/ "$RELEASE_ROOT"/

# Write profile manifest for runtime freshness checks
enforce_security_profiles_strict "$RELEASE_ROOT"

if ! "$SCRIPT_DIR/integrity-check.sh" --mode prod --root "$RELEASE_ROOT" --sums "$RELEASE_ROOT/SHA256SUMS"; then
    die "Integrity validation failed after extraction"
fi

if [[ -f "$SBOM_ATTEST_PATH" ]]; then
    echo "ℹ️  SBOM attestation detected: $SBOM_ATTEST_PATH"
else
    if [[ "$CHANNEL" = "dev" ]]; then
        echo "⚠️  SBOM attestation not provided; dev channel detected, continuing" >&2
    else
        die "SBOM attestation not provided; payload verification requires payload.sbom.json.intoto.jsonl"
    fi
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
