#!/usr/bin/env bash
# Lightweight tests for packaging and prod install workflows (no Docker required).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ARTIFACTS_ROOT="$PROJECT_ROOT/artifacts"

mkdir -p "$ARTIFACTS_ROOT/test"
WORK_DIR="$(mktemp -d "$ARTIFACTS_ROOT/test/work-XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

BIN_DIR="$WORK_DIR/bin"
mkdir -p "$BIN_DIR"
export PATH="$BIN_DIR:$PATH"

UTILS_DIR="$WORK_DIR/utils"
rsync -a "$PROJECT_ROOT/host/utils/" "$UTILS_DIR/"

VERSION="test-$(date +%s)"
OUT_DIR="$ARTIFACTS_ROOT/test/publish"
PROFILE_ENV="$OUT_DIR/profile.env"

mkdir -p "$(dirname "$PROFILE_ENV")"
cat > "$PROFILE_ENV" <<'EOF'
PROFILE=dev
IMAGE_PREFIX=containai-test
IMAGE_TAG=dev
REGISTRY=ghcr.io/containai/test
IMAGE_DIGEST=sha256:dummy
IMAGE_DIGEST_COPILOT=sha256:dummy
IMAGE_DIGEST_CODEX=sha256:dummy
IMAGE_DIGEST_CLAUDE=sha256:dummy
IMAGE_DIGEST_PROXY=sha256:dummy
IMAGE_DIGEST_LOG_FORWARDER=sha256:dummy
EOF

# Tests MUST run with proper security enforcement - no stubbing AppArmor.
# If this test fails due to AppArmor, run with sudo or fix the test environment.

# Allow non-root installs in tests by removing the root guard in the copied installer.
perl -0pi -e 's/^if \[\[ \$\(id -u\) -ne 0 \]\]; then\n    die "System installs must run as root"\nfi\n\n//' "$UTILS_DIR/install-release.sh"
# Remove install_parent ownership enforcement for test installs.
perl -0777 -pi -e 's/install_parent="\$\(cd "\$\(dirname "\$INSTALL_ROOT"\)" && pwd\)"\n.*?\nEXTRACT_DIR="\$\(mktemp -d\)"/EXTRACT_DIR="$(mktemp -d)"/s' "$UTILS_DIR/install-release.sh"
# Point cosign root to the local copy for offline tests and relax installer integrity (tests only).
COSIGN_LOCAL_URL="file://$UTILS_DIR/cosign-root.pem"
COSIGN_LOCAL_SHA=$(_sha256_file "$UTILS_DIR/cosign-root.pem")
perl -0777 -pi -e "s#^COSIGN_ROOT_URL=.*#COSIGN_ROOT_URL=\"$COSIGN_LOCAL_URL\"#; s/^COSIGN_ROOT_EXPECTED_SHA256=.*/COSIGN_ROOT_EXPECTED_SHA256=\"$COSIGN_LOCAL_SHA\"/; s/^INSTALLER_SELF_SHA256=.*/INSTALLER_SELF_SHA256=\"RELAXED\"/; s/verify_self_integrity\\(\\)\\s*{.*?}\\n/verify_self_integrity(){ :; }\\n/s; s/fetch_trust_anchor\\(\\)\\s*{.*?}\\n/fetch_trust_anchor(){ TRUST_ANCHOR_PATH=\"$UTILS_DIR/cosign-root.pem\"; }\\n/s" "$UTILS_DIR/install-release.sh"
perl -0777 -pi -e 's/Function\s+Assert-SelfIntegrity\s*{.*?}\s*/Function Assert-SelfIntegrity { return }\n/is; s/\$InstallerSelfSha256\s*=\s*\"[^\"]*\"/\$InstallerSelfSha256 = "RELAXED"/' "$UTILS_DIR/install-release.ps1"

echo "🔨 Running package.sh..."
if ! "$PROJECT_ROOT/scripts/release/package.sh" --version "$VERSION" --out "$OUT_DIR" --profile-env "$PROFILE_ENV"; then
    echo "❌ package.sh failed" >&2
    exit 1
fi

PAYLOAD_DIR="$OUT_DIR/$VERSION/payload"
[[ -d "$PAYLOAD_DIR" ]] || { echo "❌ Payload directory missing"; exit 1; }
# Seccomp profiles are now channelized (dev channel for tests)
[[ -f "$PAYLOAD_DIR/host/profiles/seccomp-containai-agent-dev.json" ]] || { echo "❌ seccomp profile missing in payload (expected seccomp-containai-agent-dev.json)"; exit 1; }
[[ -f "$PAYLOAD_DIR/install.sh" ]] || { echo "❌ install.sh missing in payload"; exit 1; }

PAYLOAD_TGZ="$OUT_DIR/$VERSION/containai-$VERSION.tar.gz"
[[ -f "$PAYLOAD_TGZ" ]] || { echo "❌ Expected transport tarball missing: $PAYLOAD_TGZ"; exit 1; }

INSTALL_ROOT="$WORK_DIR/install"
echo "🏗️  Installing to $INSTALL_ROOT"
"$UTILS_DIR/install-release.sh" \
    --version "$VERSION" \
    --asset-dir "$OUT_DIR/$VERSION" \
    --repo "local/test" \
    --install-root "$INSTALL_ROOT"

CURRENT_PATH="$(readlink -f "$INSTALL_ROOT/current")"
[[ -d "$CURRENT_PATH" ]] || { echo "❌ current symlink missing"; exit 1; }
[[ -f "$CURRENT_PATH/install.meta" ]] || { echo "❌ install.meta missing"; exit 1; }

echo "🔍 Verifying install via --verify-only"
"$UTILS_DIR/install-release.sh" \
    --version "$VERSION" \
    --asset-dir "$OUT_DIR/$VERSION" \
    --repo "local/test" \
    --install-root "$INSTALL_ROOT" \
    --verify-only

echo "✅ Packaging/install smoke tests passed"
