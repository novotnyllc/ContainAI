#!/usr/bin/env bash
# Orchestrates payload build and packaging (build-payload.sh + package-artifacts.sh).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ARTIFACTS_DIR="$PROJECT_ROOT/artifacts"
BUILD_SCRIPT="$SCRIPT_DIR/build-payload.sh"
PACKAGE_SCRIPT="$SCRIPT_DIR/package-artifacts.sh"

VERSION=""
OUT_DIR="$ARTIFACTS_DIR/publish"
PAYLOAD_DIR_OVERRIDE=""
PROFILE_ENV_PATH=""

print_help() {
    cat <<'EOF'
Usage: package.sh [--version X] [--out DIR] [--payload-dir DIR] [--profile-env PATH]

Runs build-payload.sh then package-artifacts.sh to produce <out>/<version>/payload and tarballs.

Options:
  --version X         Release version (default git describe)
  --out DIR           Output root directory (default: artifacts/publish)
  --payload-dir DIR   Use an existing payload directory instead of building into <out>/<version>/payload
  --profile-env PATH  profile.env to read (default: <out>/profile.env, falls back to host/profile.env)
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version) VERSION="$2"; shift 2 ;;
        --out) OUT_DIR="$2"; shift 2 ;;
        --payload-dir) PAYLOAD_DIR_OVERRIDE="$2"; shift 2 ;;
        --profile-env) PROFILE_ENV_PATH="$2"; shift 2 ;;
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

# Give nightly/dev a unique suffix so artifacts are distinguishable.
if [[ "$VERSION" =~ ^(nightly|dev)$ ]]; then
    if command -v git >/dev/null 2>&1 && git -C "$PROJECT_ROOT" rev-parse --short HEAD >/dev/null 2>&1; then
        VERSION="$VERSION-$(git -C "$PROJECT_ROOT" rev-parse --short HEAD)"
    else
        VERSION="$VERSION-$(date -u +%Y%m%d%H%M%S)"
    fi
fi

PROFILE_ENV="${PROFILE_ENV_PATH:-$OUT_DIR/profile.env}"
PAYLOAD_DIR="${PAYLOAD_DIR_OVERRIDE:-$OUT_DIR/$VERSION/payload}"

if [[ -z "$PAYLOAD_DIR_OVERRIDE" ]]; then
    build_args=(
        --version "$VERSION"
        --out "$OUT_DIR"
        --profile-env "$PROFILE_ENV"
    )
    "$BUILD_SCRIPT" "${build_args[@]}"
else
    if [[ ! -d "$PAYLOAD_DIR_OVERRIDE" ]]; then
        echo "❌ Provided payload directory does not exist: $PAYLOAD_DIR_OVERRIDE" >&2
        exit 1
    fi
fi

"$PACKAGE_SCRIPT" \
    --version "$VERSION" \
    --out "$OUT_DIR" \
    --profile-env "$PROFILE_ENV" \
    --payload-dir "$PAYLOAD_DIR"
