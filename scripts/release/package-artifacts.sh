#!/usr/bin/env bash
# Packages an existing payload directory into tarball artifacts.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ARTIFACTS_DIR="$PROJECT_ROOT/artifacts"

VERSION=""
OUT_DIR="$ARTIFACTS_DIR/publish"
PAYLOAD_DIR=""
LAUNCHER_CHANNEL_OVERRIDE=""
PROFILE_ENV_PATH=""

print_help() {
    cat <<'EOF'
Usage: package-artifacts.sh --version X [--out DIR] [--payload-dir DIR] [--profile-env PATH]

Packages an existing payload directory into payload.tar.gz and containai-<version>.tar.gz.
Channel and image metadata are read from profile.env. The payload directory must already contain SBOMs, SHA256SUMS, and (for non-dev) attestations.

Options:
  --version X         Release version (required)
  --out DIR           Output directory (default: artifacts/publish)
  --payload-dir DIR   Payload directory to package (default: <out>/<version>/payload)
  --profile-env PATH  profile.env to read (default: <out>/profile.env, falls back to host/profile.env)
  --launcher-channel  Override launcher channel (defaults to PROFILE in profile.env)
  --repo              Repository (owner/name) for cosign root URL (default: ContainAI/ContainAI)
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version) VERSION="$2"; shift 2 ;;
        --out) OUT_DIR="$2"; shift 2 ;;
        --payload-dir) PAYLOAD_DIR="$2"; shift 2 ;;
        --profile-env) PROFILE_ENV_PATH="$2"; shift 2 ;;
        --launcher-channel) LAUNCHER_CHANNEL_OVERRIDE="$2"; shift 2 ;;
        --repo) REPO_OVERRIDE="$2"; shift 2 ;;
        -h|--help) print_help; exit 0 ;;
        *) echo "Unknown arg: $1" >&2; print_help >&2; exit 1 ;;
    esac
done

if [[ -z "$VERSION" ]]; then
    echo "❌ --version is required." >&2
    exit 1
fi

# Convert OUT_DIR to absolute path to avoid issues with cd in subshells
# Create directory if it doesn't exist
mkdir -p "$OUT_DIR"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"

if [[ "$VERSION" =~ ^(nightly|dev)$ ]]; then
    if command -v git >/dev/null 2>&1 && git -C "$PROJECT_ROOT" rev-parse --short HEAD >/dev/null 2>&1; then
        VERSION="$VERSION-$(git -C "$PROJECT_ROOT" rev-parse --short HEAD)"
    else
        VERSION="$VERSION-$(date -u +%Y%m%d%H%M%S)"
    fi
fi

PROFILE_ENV="${PROFILE_ENV_PATH:-$OUT_DIR/profile.env}"
[[ -f "$PROFILE_ENV" ]] || { echo "❌ profile.env not found at $PROFILE_ENV. Run write-profile-env.sh first." >&2; exit 1; }

set -a
# shellcheck disable=SC1090
source "$PROFILE_ENV"
set +a

LAUNCHER_CHANNEL="${PROFILE:-}"
if [[ -n "$LAUNCHER_CHANNEL_OVERRIDE" ]]; then
    LAUNCHER_CHANNEL="$LAUNCHER_CHANNEL_OVERRIDE"
fi
if [[ -z "$LAUNCHER_CHANNEL" ]]; then
    echo "❌ PROFILE is missing in profile.env; ensure write-profile-env step populated it." >&2
    exit 1
fi

for cmd in rsync tar sha256sum awk perl; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "❌ $cmd is required for artifact packaging but not found." >&2
        exit 1
    fi
done

redacted_shell_hash() {
    local script="$1"
    sed 's/^INSTALLER_SELF_SHA256=.*/INSTALLER_SELF_SHA256="__REDACTED__"/' "$script" | sha256sum | awk '{print $1}'
}

redacted_ps_hash() {
    local script="$1"
    perl -0777 -pe 's/InstallerSelfSha256="[^"]*"/InstallerSelfSha256="__REDACTED__"/g' "$script" | sha256sum | awk '{print $1}'
}

template_installers() {
    local payload_root="$1"
    local shell_installer="$payload_root/host/utils/install-release.sh"
    local ps_installer="$payload_root/host/utils/install-release.ps1"
    local cosign_root="$payload_root/tools/cosign-root.pem"

    [[ -f "$shell_installer" ]] || { echo "❌ install-release.sh missing in payload" >&2; exit 1; }

    [[ -f "$cosign_root" ]] || { echo "❌ cosign-root.pem missing in payload" >&2; exit 1; }
    local git_commit
    git_commit="${GIT_COMMIT:-}"
    if [[ -z "$git_commit" ]]; then
        git_commit=$(git -C "$PROJECT_ROOT" rev-parse HEAD 2>/dev/null || true)
    fi
    if [[ -z "$git_commit" ]]; then
        echo "❌ Unable to determine git commit for cosign root URL" >&2
        exit 1
    fi
    local repo_slug="${REPO_OVERRIDE:-ContainAI/ContainAI}"
    local cosign_url="https://raw.githubusercontent.com/${repo_slug}/${git_commit}/host/utils/cosign-root.pem"
    local cosign_hash
    cosign_hash=$(sha256sum "$cosign_root" | awk '{print $1}')
    perl -0777 -pi -e "s/__COSIGN_ROOT_SHA256__/$cosign_hash/" "$shell_installer"
    # Check that the variable assignment was replaced (not the literal comparison in runtime check)
    if grep -qE '^COSIGN_ROOT_EXPECTED_SHA256="__COSIGN_ROOT_SHA256__"' "$shell_installer"; then
        echo "❌ cosign root hash placeholder not replaced in installer" >&2
        exit 1
    fi
    perl -0777 -pi -e "s#__COSIGN_ROOT_URL__#$cosign_url#" "$shell_installer"
    # Check that the variable assignment was replaced
    if grep -qE '^COSIGN_ROOT_URL="__COSIGN_ROOT_URL__"' "$shell_installer"; then
        echo "❌ cosign root URL placeholder not replaced in installer" >&2
        exit 1
    fi

    local shell_hash
    shell_hash=$(redacted_shell_hash "$shell_installer")
    perl -0777 -pi -e "s/INSTALLER_SELF_SHA256=\"[^\"]*\"/INSTALLER_SELF_SHA256=\"$shell_hash\"/" "$shell_installer"
    # Check that the variable assignment was replaced (not the literal comparison in runtime check)
    if grep -qE '^INSTALLER_SELF_SHA256="__INSTALLER_SELF_SHA256__"' "$shell_installer"; then
        echo "❌ Installer self-hash placeholder not replaced" >&2
        exit 1
    fi

    if [[ -f "$ps_installer" ]]; then
        local ps_hash
        ps_hash=$(redacted_ps_hash "$ps_installer")
        perl -0777 -pi -e "s/InstallerSelfSha256=\"[^\"]*\"/InstallerSelfSha256=\"$ps_hash\"/" "$ps_installer"
        if grep -q "__INSTALLER_SELF_SHA256__" "$ps_installer"; then
            echo "❌ PowerShell installer self-hash placeholder not replaced" >&2
            exit 1
        fi
    fi
}

DEST_DIR="$OUT_DIR/$VERSION"
PAYLOAD_DIR="${PAYLOAD_DIR:-$DEST_DIR/payload}"

if [[ ! -d "$PAYLOAD_DIR" ]]; then
    echo "❌ Payload directory not found: $PAYLOAD_DIR" >&2
    exit 1
fi

# Canonicalize PAYLOAD_DIR to absolute path for consistent comparison with PAYLOAD_OUT
PAYLOAD_DIR="$(cd "$PAYLOAD_DIR" && pwd)"

if [[ ! -f "$PAYLOAD_DIR/SHA256SUMS" ]]; then
    echo "❌ Payload directory is missing SHA256SUMS (run build-payload.sh first)." >&2
    exit 1
fi

if [[ "$LAUNCHER_CHANNEL" != "dev" && ! -f "$PAYLOAD_DIR/payload.sbom.json" ]]; then
    echo "❌ Non-dev payload must include payload.sbom.json." >&2
    exit 1
fi

if [[ "$LAUNCHER_CHANNEL" != "dev" && ! -f "$PAYLOAD_DIR/payload.sbom.json.intoto.jsonl" ]]; then
    echo "❌ Non-dev payload must include payload.sbom.json.intoto.jsonl attestation." >&2
    echo "👉 Re-run the GitHub attestation step to materialize the SBOM DSSE bundle into the payload directory." >&2
    exit 1
fi

mkdir -p "$DEST_DIR"

PAYLOAD_OUT="$DEST_DIR/payload"
if [[ "$PAYLOAD_DIR" = "$PAYLOAD_OUT" ]]; then
    # Reuse existing payload directory in-place.
    :
else
    rm -rf "$PAYLOAD_OUT"
    rsync -a --delete "$PAYLOAD_DIR"/ "$PAYLOAD_OUT"/
fi

template_installers "$PAYLOAD_OUT"

echo "📦 Packaging payload from $PAYLOAD_OUT"
PAYLOAD_TAR_GZ_PATH="$DEST_DIR/payload.tar.gz"
rm -f "$PAYLOAD_TAR_GZ_PATH"
(cd "$PAYLOAD_OUT" && tar -czf "$PAYLOAD_TAR_GZ_PATH" .)

TRANSPORT_GZ_PATH="$DEST_DIR/containai-${VERSION}.tar.gz"
cp "$PAYLOAD_TAR_GZ_PATH" "$TRANSPORT_GZ_PATH"

cat > "$DEST_DIR/VERIFY.txt" <<'EOF'
Verification (offline):
1) Extract: tar -xzf containai-<version>.tar.gz
2) Inside extracted payload/, verify contents: sha256sum -c SHA256SUMS
3) Verify SBOM hash matches SHA256SUMS entry
EOF

echo ""
echo "Payload outputs:"
echo " - $PAYLOAD_OUT"
echo " - $TRANSPORT_GZ_PATH (release/OCI asset)"
