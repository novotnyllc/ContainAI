#!/usr/bin/env bash
# Builds the payload directory for a release. No packaging or tar creation.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ARTIFACTS_DIR="$PROJECT_ROOT/artifacts"

VERSION=""
OUT_DIR="$ARTIFACTS_DIR/publish"
PROFILE_ENV_PATH=""

print_help() {
    cat <<'EOF'
Usage: build-payload.sh --version X [--out DIR] [--profile-env PATH]

Builds the payload directory at <out>/<version>/payload. Does not create tarballs. Channel and image digests are read from profile.env (PROFILE and IMAGE_DIGEST_*).

Options:
  --version X         Release version (required)
  --out DIR           Output root directory (default: artifacts/publish)
  --profile-env PATH  profile.env to read (default: <out>/profile.env, falls back to host/profile.env)
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version) VERSION="$2"; shift 2 ;;
        --out) OUT_DIR="$2"; shift 2 ;;
        --profile-env) PROFILE_ENV_PATH="$2"; shift 2 ;;
        -h|--help) print_help; exit 0 ;;
        *) echo "Unknown arg: $1" >&2; print_help >&2; exit 1 ;;
    esac
done

if [[ -z "$VERSION" ]]; then
    echo "❌ --version is required." >&2
    exit 1
fi

# Convert OUT_DIR to absolute path to avoid issues with cd in subshells
OUT_DIR="$(cd "$OUT_DIR" 2>/dev/null && pwd || mkdir -p "$OUT_DIR" && cd "$OUT_DIR" && pwd)"

if [[ "$VERSION" =~ ^(nightly|dev)$ ]]; then
    if command -v git >/dev/null 2>&1 && git -C "$PROJECT_ROOT" rev-parse --short HEAD >/dev/null 2>&1; then
        VERSION="$VERSION-$(git -C "$PROJECT_ROOT" rev-parse --short HEAD)"
    else
        VERSION="$VERSION-$(date -u +%Y%m%d%H%M%S)"
    fi
fi

PROFILE_ENV="${PROFILE_ENV_PATH:-$OUT_DIR/profile.env}"
PROFILE_ENV_FALLBACK="$PROJECT_ROOT/host/profile.env"
if [[ ! -f "$PROFILE_ENV" && -f "$PROFILE_ENV_FALLBACK" ]]; then
    echo "⚠️ profile.env not found at $PROFILE_ENV, falling back to $PROFILE_ENV_FALLBACK" >&2
    PROFILE_ENV="$PROFILE_ENV_FALLBACK"
fi
if [[ ! -f "$PROFILE_ENV" ]]; then
    echo "❌ profile.env not found (tried $PROFILE_ENV and $PROFILE_ENV_FALLBACK). Run write-profile-env.sh first." >&2
    exit 1
fi

set -a
# shellcheck disable=SC1090
source "$PROFILE_ENV"
set +a

LAUNCHER_CHANNEL="${PROFILE:-}"
if [[ -z "$LAUNCHER_CHANNEL" ]]; then
    echo "❌ PROFILE is missing in profile.env; ensure write-profile-env step populated it." >&2
    exit 1
fi

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
    val="${!v:-}"
    if [[ -z "$val" ]]; then
        missing_digests+=("$v")
    fi
done
if [[ ${#missing_digests[@]} -gt 0 ]]; then
    echo "❌ profile.env is missing required digests: ${missing_digests[*]}." >&2
    exit 1
fi

DEST_DIR="$OUT_DIR/$VERSION"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

PAYLOAD_ROOT="payload"
PAYLOAD_DIR_BUILD="$WORK_DIR/$PAYLOAD_ROOT"
mkdir -p "$PAYLOAD_DIR_BUILD"

echo "📦 Building payload v$VERSION"
echo "Output dir: $DEST_DIR"

copy_path() {
    local src="$1" dest="$2"
    if [ -e "$src" ]; then rsync -a --delete --exclude '.git/' "$src" "$dest"; fi
}

include_paths=(
    "$PROJECT_ROOT/host"
    "$PROJECT_ROOT/agent-configs"
    "$PROJECT_ROOT/config.toml"
    "$PROJECT_ROOT/docs"
    "$PROJECT_ROOT/README.md"
    "$PROJECT_ROOT/SECURITY.md"
    "$PROJECT_ROOT/USAGE.md"
    "$PROJECT_ROOT/LICENSE"
    "$PROJECT_ROOT/install.sh"
    "$PROJECT_ROOT/scripts/setup-local-dev.sh"
)

for path in "${include_paths[@]}"; do
    copy_path "$path" "$PAYLOAD_DIR_BUILD/"
done

mkdir -p "$PAYLOAD_DIR_BUILD/tools"
COSIGN_ROOT_SOURCE="$PROJECT_ROOT/host/utils/cosign-root.pem"
if [[ -f "$COSIGN_ROOT_SOURCE" ]]; then
    cp "$COSIGN_ROOT_SOURCE" "$PAYLOAD_DIR_BUILD/tools/cosign-root.pem"
fi

# Generate channel-specific launcher entrypoints
ENTRYPOINTS_DIR_SRC="$PAYLOAD_DIR_BUILD/host/launchers/entrypoints"
if [[ -d "$ENTRYPOINTS_DIR_SRC" ]]; then
    if [[ "$LAUNCHER_CHANNEL" = "dev" ]]; then
        ENTRYPOINTS_DIR_OUT="$ENTRYPOINTS_DIR_SRC"
    else
        ENTRYPOINTS_DIR_OUT="$PAYLOAD_DIR_BUILD/host/launchers/entrypoints-${LAUNCHER_CHANNEL}"
        rm -rf "$ENTRYPOINTS_DIR_OUT"
        cp -a "$ENTRYPOINTS_DIR_SRC"/. "$ENTRYPOINTS_DIR_OUT"/
    fi
    if ! "$PAYLOAD_DIR_BUILD/host/utils/prepare-entrypoints.sh" --channel "$LAUNCHER_CHANNEL" --source "$ENTRYPOINTS_DIR_OUT" --dest "$ENTRYPOINTS_DIR_OUT"; then
        echo "❌ Failed to prepare launcher entrypoints for channel $LAUNCHER_CHANNEL" >&2
        exit 1
    fi
    if [[ "$ENTRYPOINTS_DIR_OUT" != "$ENTRYPOINTS_DIR_SRC" ]]; then
        rm -rf "$ENTRYPOINTS_DIR_SRC"
        mv "$ENTRYPOINTS_DIR_OUT" "$ENTRYPOINTS_DIR_SRC"
    fi
fi

# Generate channel-specific security profiles
# Profiles are generated with embedded channel names so they can be loaded directly
# without runtime modification. This ensures SHA256 validation covers the exact
# profile content that gets loaded.
PROFILES_DIR="$PAYLOAD_DIR_BUILD/host/profiles"
if [[ -d "$PROFILES_DIR" ]]; then
    echo "📦 Generating channel-specific security profiles (channel: $LAUNCHER_CHANNEL)..."
    # Generate into a staging dir, then replace the original
    PROFILES_STAGING="$(mktemp -d)"
    if ! "$PAYLOAD_DIR_BUILD/host/utils/prepare-profiles.sh" \
        --channel "$LAUNCHER_CHANNEL" \
        --source "$PROFILES_DIR" \
        --dest "$PROFILES_STAGING" \
        --manifest "$PROFILES_STAGING/containai-profiles.sha256"; then
        rm -rf "$PROFILES_STAGING"
        echo "❌ Failed to generate security profiles for channel $LAUNCHER_CHANNEL" >&2
        exit 1
    fi
    # Replace profiles dir with generated content
    rm -rf "$PROFILES_DIR"
    mv "$PROFILES_STAGING" "$PROFILES_DIR"
fi

# Ensure dev payloads carry channel metadata so installers can permit relaxed attestation rules.
if [[ "$LAUNCHER_CHANNEL" = "dev" && ! -f "$PAYLOAD_DIR_BUILD/host/profile.env" ]]; then
    cat > "$PAYLOAD_DIR_BUILD/host/profile.env" <<'EOF'
CHANNEL=dev
EOF
fi

# For dev builds, ensure a placeholder SBOM exists so local installs can proceed without GH-generated SBOMs.
if [[ "$LAUNCHER_CHANNEL" = "dev" && ! -f "$PAYLOAD_DIR_BUILD/payload.sbom.json" ]]; then
    echo '{"sbom":"dev placeholder"}' > "$PAYLOAD_DIR_BUILD/payload.sbom.json"
fi

# SHA256SUMS inside payload for integrity-check (exclude self)
pushd "$PAYLOAD_DIR_BUILD" >/dev/null
find . -type f ! -name 'SHA256SUMS' -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS
PAYLOAD_HASH=$(sha256sum SHA256SUMS | awk '{print $1}')
echo "$PAYLOAD_HASH  SHA256SUMS" > payload.sha256
popd >/dev/null

DEST_PAYLOAD="$DEST_DIR/payload"
rm -rf "$DEST_PAYLOAD"
mkdir -p "$(dirname "$DEST_PAYLOAD")"
copy_path "$PAYLOAD_DIR_BUILD/" "$DEST_PAYLOAD/"

echo "✅ Payload ready at $DEST_PAYLOAD"
echo "PAYLOAD_VERSION=$VERSION"
