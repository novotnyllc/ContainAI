#!/usr/bin/env bash
# ContainAI Installer
# Fetches and verifies the payload from GHCR, then installs it.
# Dependencies: curl, tar, openssl

set -euo pipefail

DEFAULT_REPO="ContainAI/ContainAI"
DEFAULT_CHANNEL="prod"
REGISTRY_HOST="${CONTAINAI_REGISTRY:-ghcr.io}"
REPO="${CONTAINAI_REPO:-$DEFAULT_REPO}"
CHANNEL="${CONTAINAI_CHANNEL:-$DEFAULT_CHANNEL}"
VERSION="${CONTAINAI_VERSION:-}"
INSTALL_ROOT="${CONTAINAI_INSTALL_ROOT:-/opt/containai}"
NAMESPACE_OVERRIDE="${CONTAINAI_REGISTRY_NAMESPACE:-}"

# OIDC Issuer and Subject for verification
OIDC_ISSUER="https://token.actions.githubusercontent.com"
# Trust the repo we are installing from
EXPECTED_REPO="$REPO"

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
PAYLOAD_REPO="${NAMESPACE}/containai-payload"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT
SCRIPT_PATH="$(readlink -f "$0")"

die() { echo "❌ $*" >&2; exit 1; }

require_tool() {
    command -v "$1" >/dev/null 2>&1 || die "$1 is required for installation"
}

require_tool curl
require_tool openssl
require_tool tar

# Fetch Docker-Content-Digest header for a manifest ref
oci_manifest_digest_header() {
    local repo="$1" ref="$2"
    local url="https://${REGISTRY_HOST}/v2/${repo}/manifests/${ref}"
    curl -I -fsSL -H "Accept: application/vnd.oci.image.manifest.v1+json, application/vnd.oci.artifact.manifest.v1+json" "$url" \
      | tr -d '\r' | awk '/Docker-Content-Digest:/ {print $2}' | tail -n1
}

# Minimal JSON extraction helpers using sed/grep/cut
# These avoid python/jq dependencies but assume standard OCI/DSSE JSON structure.

get_json_value() {
    local key="$1"
    local file="$2"
    # Extract simple string value for unique key
    # Matches "key" : "value" (handling whitespace) and prints value.
    # Uses sed to find the pattern. Handles minified JSON.
    # Warning: greedy match, best for unique keys.
    sed -n 's/.*"'"$key"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$file"
}

get_manifest_digest() {
    local file="$1"
    local media_type="$2"
    # Split layers by "},{" to handle minified arrays
    # Find line with media_type
    # Extract digest
    sed 's/},{/}\n{/g' "$file" | grep "$media_type" | sed -n 's/.*"digest"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1
}

get_subject_digest() {
    local file="$1"
    # Find first "sha256":"..." occurrence
    sed 's/"sha256"[[:space:]]*:[[:space:]]*"/\nsha256:/g' "$file" | grep '^sha256:' | head -n1 | cut -d'"' -f1 | cut -d: -f2
}

# Fulcio Root CA
FULCIO_ROOT_CERT=$(cat <<'EOF'
-----BEGIN CERTIFICATE-----
MIIB9zCCAXygAwIBAgIUALZNAPFdxHPwjeDloDwyYChAO/4wCgYIKoZIzj0EAwMw
KjEVMBMGA1UEChMMc2lnc3RvcmUuZGV2MREwDwYDVQQDEwhzaWdzdG9yZTAeFw0y
MTEwMDcxMzU2NTlaFw0zMTEwMDUxMzU2NThaMCoxFTATBgNVBAoTDHNpZ3N0b3Jl
LmRldjERMA8GA1UEAxMIc2lnc3RvcmUwdjAQBgcqhkjOPQIBBgUrgQQAIgNiAAT7
XeFT4rb3PQGwS4IajtLk3/OlnpgangaBclYpsYBr5i+4ynB07ceb3LP0OIOZdxex
X69c5iVuyJRQ+Hz05yi+UF3uBWAlHpiS5sh0+H2GHE7SXrk1EC5m1Tr19L9gg92j
YzBhMA4GA1UdDwEB/wQEAwIBBjAPBgNVHRMBAf8EBTADAQH/MB0GA1UdDgQWBBRY
wB5fkUWlZql6zJChkyLQKsXF+jAfBgNVHSMEGDAWgBRYwB5fkUWlZql6zJChkyLQ
KsXF+jAKBggqhkjOPQQDAwNpADBmAjEAj1nHeXZp+13NWBNa+EDsDP8G1WWg1tCM
WP/WHPqpaVo0jhsweNFZgSs0eE7wYI4qAjEA2WB9ot98sIkoF3vZYdd3/VtWB5b9
TNMea7Ix/stJ5TfcLLeABLE4BNJOsQ4vnBHJ
-----END CERTIFICATE-----
EOF
)
echo "$FULCIO_ROOT_CERT" > "$WORKDIR/fulcio_root.pem"

oci_fetch_manifest() {
    local repo="$1" ref="$2" dest="$3"
    local url="https://${REGISTRY_HOST}/v2/${repo}/manifests/${ref}"
    local code
    code=$(curl -fsSL -w "%{http_code}" -H "Accept: application/vnd.oci.image.manifest.v1+json, application/vnd.oci.artifact.manifest.v1+json" \
        "$url" -o "$dest")
    if [[ "$code" != "200" ]]; then
        echo "Error fetching manifest from $url (HTTP $code)" >&2
        return 1
    fi
}

oci_fetch_blob() {
    local repo="$1" digest="$2" dest="$3"
    local url="https://${REGISTRY_HOST}/v2/${repo}/blobs/${digest}"
    local code
    code=$(curl -fsSL -w "%{http_code}" "$url" -o "$dest")
    if [[ "$code" != "200" ]]; then
        echo "Error fetching blob from $url (HTTP $code)" >&2
        return 1
    fi
}

# Little-endian 8-byte integer writer
write_le8() {
    local len=$1
    for i in {0..7}; do
        printf "\\x$(printf "%02x" $(( (len >> (i * 8)) & 0xff )))"
    done
}

verify_dsse() {
    local attestation_file="$1"
    local expected_subject_digest="$2"

    echo "🔐 Verifying attestation..."

    # Extract DSSE components
    local payload_type
    payload_type=$(get_json_value "payloadType" "$attestation_file")
    local payload_b64
    payload_b64=$(get_json_value "payload" "$attestation_file")
    
    # Decode payload (in-toto statement)
    echo "$payload_b64" | base64 -d > "$WORKDIR/intoto.json"

    # Verify subject digest
    local subject_digest
    subject_digest=$(get_subject_digest "$WORKDIR/intoto.json")
    # Strip sha256: prefix from expected digest if present
    local expected_hex="${expected_subject_digest#sha256:}"
    if [[ "$subject_digest" != "$expected_hex" ]]; then
        die "Subject digest mismatch! Expected: $expected_hex, Found: $subject_digest"
    fi

    # Construct PAE
    local type_len=${#payload_type}
    local body_len
    body_len=$(wc -c < "$WORKDIR/intoto.json")
    
    {
        printf "DSSEv1 "
        write_le8 "$type_len"
        printf "%s " "$payload_type"
        write_le8 "$body_len"
        cat "$WORKDIR/intoto.json"
    } > "$WORKDIR/pae.bin"

    # Verify signatures
    # We iterate over signatures by splitting the JSON array
    local verified=false
    local i=0
    
    # Create a temporary file with one signature object per line
    sed 's/},{/}\n{/g' "$attestation_file" | grep '"sig"' > "$WORKDIR/signatures.jsonl"
    
    while read -r sig_line; do
        # Extract signature and certificate from the line
        local sig_b64
        sig_b64=$(echo "$sig_line" | sed -n 's/.*"sig"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
        local cert_b64
        cert_b64=$(echo "$sig_line" | sed -n 's/.*"cert"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
        
        echo "$sig_b64" | base64 -d > "$WORKDIR/sig.bin"
        echo "$cert_b64" | base64 -d > "$WORKDIR/cert.pem"
        
        # Verify certificate chain
        local cert_count
        cert_count=$(grep -c "BEGIN CERTIFICATE" "$WORKDIR/cert.pem")
        
        if [[ "$cert_count" -gt 1 ]]; then
            awk 'BEGIN {c=0;} /BEGIN CERTIFICATE/ {c++} { print > "cert_" c ".pem" }' "$WORKDIR/cert.pem"
            mv cert_1.pem "$WORKDIR/leaf.pem"
            if [[ -f "cert_2.pem" ]]; then
                mv cert_2.pem "$WORKDIR/intermediate.pem"
                if ! openssl verify -CAfile "$WORKDIR/fulcio_root.pem" -untrusted "$WORKDIR/intermediate.pem" "$WORKDIR/leaf.pem" >/dev/null 2>&1; then
                    continue
                fi
            else
                 if ! openssl verify -CAfile "$WORKDIR/fulcio_root.pem" "$WORKDIR/leaf.pem" >/dev/null 2>&1; then
                    continue
                fi
            fi
        else
            cp "$WORKDIR/cert.pem" "$WORKDIR/leaf.pem"
             if ! openssl verify -CAfile "$WORKDIR/fulcio_root.pem" "$WORKDIR/leaf.pem" >/dev/null 2>&1; then
                continue
            fi
        fi

        # Verify OIDC claims in leaf cert
        # 1.3.6.1.4.1.57264.1.1 = Issuer
        # 1.3.6.1.4.1.57264.1.5 = Repository
        
        local cert_text
        cert_text=$(openssl x509 -in "$WORKDIR/leaf.pem" -text -noout)
        
        # Extract Issuer (expecting next line after OID)
        local issuer
        issuer=$(echo "$cert_text" | grep -A1 "1.3.6.1.4.1.57264.1.1" | tail -n1 | sed 's/^[[:space:]]*//')
        
        if [[ "$issuer" != "$OIDC_ISSUER" ]]; then
            echo "⚠️  Issuer mismatch in cert $i: expected '$OIDC_ISSUER', got '$issuer'"
            continue
        fi
        
        # Extract Repository
        local repo
        repo=$(echo "$cert_text" | grep -A1 "1.3.6.1.4.1.57264.1.5" | tail -n1 | sed 's/^[[:space:]]*//')
        
        if [[ "$repo" != "$EXPECTED_REPO" ]]; then
             echo "⚠️  Repository mismatch in cert $i: expected '$EXPECTED_REPO', got '$repo'"
             continue
        fi

        # Verify signature over PAE
        openssl x509 -in "$WORKDIR/leaf.pem" -pubkey -noout > "$WORKDIR/pubkey.pem"
        
        if openssl dgst -sha256 -verify "$WORKDIR/pubkey.pem" -signature "$WORKDIR/sig.bin" "$WORKDIR/pae.bin" >/dev/null 2>&1; then
            verified=true
            break
        fi
        i=$((i+1))
    done < "$WORKDIR/signatures.jsonl"

    if [[ "$verified" != "true" ]]; then
        die "Failed to verify any signature in the attestation"
    fi
}

if [[ -z "$VERSION" ]]; then
    TAG="$CHANNEL"
    if [[ "$CHANNEL" == "prod" ]]; then
        TAG="latest"
    fi
else
    TAG="$VERSION"
fi

# Self-verify installer from GHCR unless already running the verified copy
if [[ "$SCRIPT_PATH" != */install-verified.sh ]]; then
    INSTALLER_REPO="${NAMESPACE}/containai-installer"
    echo "⬇️  Fetching installer manifest for ${TAG}..."
    INST_MANIFEST="$WORKDIR/installer-manifest.json"
    oci_fetch_manifest "$INSTALLER_REPO" "$TAG" "$INST_MANIFEST"
    INST_MANIFEST_DIGEST=$(oci_manifest_digest_header "$INSTALLER_REPO" "$TAG")
    [[ -n "$INST_MANIFEST_DIGEST" ]] || die "Could not resolve installer manifest digest for ref $TAG"
    echo "ℹ️  Installer manifest digest: $INST_MANIFEST_DIGEST"

    INST_LAYER=$(sed 's/},{/}\n{/g' "$INST_MANIFEST" | grep "application/vnd.containai.installer.v1+sh" | sed -n 's/.*"digest"[[:space:]]*:[[:space:]]*"\([^\" ]*\)".*/\1/p' | head -n1)
    [[ -n "$INST_LAYER" ]] || die "Installer layer not found in manifest"
    INST_TGZ="$WORKDIR/install.sh.gz"
    oci_fetch_blob "$INSTALLER_REPO" "$INST_LAYER" "$INST_TGZ"
    INST_HEX="${INST_LAYER/sha256:/}"
    INST_ACTUAL_HEX=$(openssl dgst -sha256 "$INST_TGZ" | awk '{print $2}')
    [[ "$INST_HEX" == "$INST_ACTUAL_HEX" ]] || die "Installer blob digest mismatch (expected $INST_HEX got $INST_ACTUAL_HEX)"

    # Attestation: bundled intoto preferred, fallback to referrers
    INST_ATTEST=$(sed 's/},{/}\n{/g' "$INST_MANIFEST" | grep "application/vnd.in-toto+json" | sed -n 's/.*"digest"[[:space:]]*:[[:space:]]*"\([^\" ]*\)".*/\1/p' | head -n1)
    [[ -n "$INST_ATTEST" ]] || die "Installer attestation layer missing in manifest"
    INST_ATTEST_FILE="$WORKDIR/install.att"
    oci_fetch_blob "$INSTALLER_REPO" "$INST_ATTEST" "$INST_ATTEST_FILE"
    verify_dsse "$INST_ATTEST_FILE" "$INST_MANIFEST_DIGEST"

    # Unpack verified installer and re-exec
    gunzip -c "$INST_TGZ" > "$WORKDIR/install-verified.sh"
    chmod +x "$WORKDIR/install-verified.sh"
    exec "$WORKDIR/install-verified.sh" "$@"
fi

echo "⬇️  Fetching payload manifest for ${TAG}..."
MANIFEST="$WORKDIR/payload-manifest.json"
oci_fetch_manifest "$PAYLOAD_REPO" "$TAG" "$MANIFEST"

# Manifest digest from registry header (attested subject)
MANIFEST_DIGEST=$(oci_manifest_digest_header "$PAYLOAD_REPO" "$TAG")
if [[ -z "$MANIFEST_DIGEST" ]]; then
    die "Could not resolve manifest digest for payload ref $TAG"
fi
echo "ℹ️  Manifest digest: $MANIFEST_DIGEST"

# Find payload layer
PAYLOAD_DIGEST=$(get_manifest_digest "$MANIFEST" "application/vnd.containai.payload.layer.v1+gzip")
if [[ -z "$PAYLOAD_DIGEST" ]]; then
    die "Could not find payload layer in manifest"
fi

echo "⬇️  Fetching payload..."
PAYLOAD_TAR="$WORKDIR/payload.tar.gz"
oci_fetch_blob "$PAYLOAD_REPO" "$PAYLOAD_DIGEST" "$PAYLOAD_TAR"

# Calculate digest
ACTUAL_DIGEST=$(openssl dgst -sha256 "$PAYLOAD_TAR" | awk '{print $2}')

# Verify Payload Integrity (Blob vs Manifest)
if [[ "sha256:$ACTUAL_DIGEST" != "$PAYLOAD_DIGEST" ]]; then
    die "Payload digest mismatch! Manifest says: $PAYLOAD_DIGEST, Found: sha256:$ACTUAL_DIGEST"
fi
echo "✅ Payload integrity verified"

echo "⬇️  Fetching attestation..."

# Helper to find attestation manifest digest
find_attestation_manifest() {
    # Returns bundled attestation digest; no fallback.
    local manifest_json="$1"
    local bundled
    bundled=$(sed 's/},{/}\n{/g' "$manifest_json" | grep "application/vnd.in-toto+json" | sed -n 's/.*"digest"[[:space:]]*:[[:space:]]*"\([^" ]*\)".*/\1/p' | head -n1)
    [[ -n "$bundled" ]] || return 1
    echo "$bundled"
    return 0
}

ATTESTATION_MANIFEST="$WORKDIR/attestation-manifest.json"
# Use MANIFEST_DIGEST to find attestation (bundled preferred)
ATT_MANIFEST_DIGEST=$(find_attestation_manifest "$MANIFEST" "$PAYLOAD_REPO" "$MANIFEST_DIGEST") || die "Could not find attestation for payload"

ATTESTATION_FILE="$WORKDIR/attestation.json"
oci_fetch_blob "$PAYLOAD_REPO" "$ATT_MANIFEST_DIGEST" "$ATTESTATION_FILE"

# Verify Attestation (Subject vs Manifest)
verify_dsse "$ATTESTATION_FILE" "$MANIFEST_DIGEST"

# Ensure payload blob matches manifest entry
EXPECT_HEX="${PAYLOAD_DIGEST/sha256:/}"
ACTUAL_HEX="$ACTUAL_DIGEST"
[[ "$EXPECT_HEX" == "$ACTUAL_HEX" ]] || die "Payload digest mismatch (expected $EXPECT_HEX got $ACTUAL_HEX)"

echo "📦 Extracting payload..."
PAYLOAD_DIR="$WORKDIR/payload"
mkdir -p "$PAYLOAD_DIR"
tar -xzf "$PAYLOAD_TAR" -C "$PAYLOAD_DIR"

# Prepare assets for install-release.sh
ASSET_NAME="containai-${VERSION}.tar.gz"
cp "$PAYLOAD_TAR" "$PAYLOAD_DIR/$ASSET_NAME"
cp "$ATTESTATION_FILE" "$PAYLOAD_DIR/$ASSET_NAME.intoto.jsonl"

INSTALLER_SCRIPT="$PAYLOAD_DIR/host/utils/install-release.sh"
if [[ ! -x "$INSTALLER_SCRIPT" ]]; then
    die "Installer not found inside payload: $INSTALLER_SCRIPT"
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

echo "▶ Running internal installer..."
export CONTAINAI_TRUST_ANCHOR="$WORKDIR/fulcio_root.pem"
"${SUDO_CMD[@]}" "$INSTALLER_SCRIPT" --version "$VERSION" --asset-dir "$PAYLOAD_DIR" --install-root "$INSTALL_ROOT" --repo "$REPO"

echo "✅ ContainAI installed successfully"
