#!/usr/bin/env bash
# Install containai launchers to PATH
# Adds host/launchers/entrypoints directory to ~/.bashrc or ~/.zshrc

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LAUNCHERS_PATH="$REPO_ROOT/host/launchers/entrypoints"
SECURITY_ASSET_DIR="${CONTAINAI_ROOT:-$REPO_ROOT}/profiles"
SECURITY_PROFILES_DIR="$REPO_ROOT/host/profiles"
SECURITY_MANIFEST_NAME="containai-profiles.sha256"
CHECK_ONLY=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --check-only)
            CHECK_ONLY=1
            shift
            ;;
        *)
            echo "Unknown argument: $1" >&2
            echo "Usage: $0 [--check-only]" >&2
            exit 1
            ;;
    esac
done

if [[ ! -d "$LAUNCHERS_PATH" ]]; then
    echo "ERROR: Launchers directory not found: $LAUNCHERS_PATH"
    exit 1
fi

echo "Installing launchers to PATH..."

if [[ $CHECK_ONLY -eq 0 ]]; then
    echo "Running ContainAI prerequisite and health checks..."
    if ! "$REPO_ROOT/host/utils/verify-prerequisites.sh"; then
        echo "❌ Prerequisite verification failed. Resolve the issues above and re-run scripts/setup-local-dev.sh."
        exit 1
    fi

    if ! "$REPO_ROOT/host/utils/check-health.sh"; then
        echo "❌ Health check failed. Resolve the issues above and re-run scripts/setup-local-dev.sh."
        exit 1
    fi
else
    echo "Checking security assets only (skipping prerequisite and health checks)..."
fi

file_sha256() {
    local file="$1"
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$file" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$file" | awk '{print $1}'
    else
        python3 - "$file" <<'PY'
import hashlib, sys, pathlib
path = pathlib.Path(sys.argv[1])
print(hashlib.sha256(path.read_bytes()).hexdigest())
PY
    fi
}

install_security_assets() {
    local dry_run="${1:-0}"
    local asset_dir="$SECURITY_ASSET_DIR"
    local src_seccomp="$SECURITY_PROFILES_DIR/seccomp-containai-agent.json"
    local src_apparmor="$SECURITY_PROFILES_DIR/apparmor-containai-agent.profile"
    local src_seccomp_proxy="$SECURITY_PROFILES_DIR/seccomp-containai-proxy.json"
    local src_apparmor_proxy="$SECURITY_PROFILES_DIR/apparmor-containai-proxy.profile"
    local src_seccomp_fwd="$SECURITY_PROFILES_DIR/seccomp-containai-log-forwarder.json"
    local src_apparmor_fwd="$SECURITY_PROFILES_DIR/apparmor-containai-log-forwarder.profile"
    local manifest_path="$asset_dir/$SECURITY_MANIFEST_NAME"

    echo "Syncing security profiles to $asset_dir..."
    if [[ ! -f "$src_seccomp" || ! -f "$src_apparmor" || ! -f "$src_seccomp_proxy" || ! -f "$src_apparmor_proxy" || ! -f "$src_seccomp_fwd" || ! -f "$src_apparmor_fwd" ]]; then
        echo "❌ Security profiles missing under $SECURITY_PROFILES_DIR. Verify your checkout or regenerate profiles." >&2
        exit 1
    fi

    local target_seccomp="$asset_dir/seccomp-containai-agent.json"
    local target_apparmor="$asset_dir/apparmor-containai-agent.profile"
    local target_seccomp_proxy="$asset_dir/seccomp-containai-proxy.json"
    local target_apparmor_proxy="$asset_dir/apparmor-containai-proxy.profile"
    local target_seccomp_fwd="$asset_dir/seccomp-containai-log-forwarder.json"
    local target_apparmor_fwd="$asset_dir/apparmor-containai-log-forwarder.profile"

    local repo_seccomp_hash repo_apparmor_hash repo_seccomp_proxy_hash repo_apparmor_proxy_hash repo_seccomp_fwd_hash repo_apparmor_fwd_hash
    local target_seccomp_hash target_apparmor_hash target_seccomp_proxy_hash target_apparmor_proxy_hash target_seccomp_fwd_hash target_apparmor_fwd_hash

    repo_seccomp_hash=$(file_sha256 "$src_seccomp")
    repo_apparmor_hash=$(file_sha256 "$src_apparmor")
    repo_seccomp_proxy_hash=$(file_sha256 "$src_seccomp_proxy")
    repo_apparmor_proxy_hash=$(file_sha256 "$src_apparmor_proxy")
    repo_seccomp_fwd_hash=$(file_sha256 "$src_seccomp_fwd")
    repo_apparmor_fwd_hash=$(file_sha256 "$src_apparmor_fwd")

    if [[ -f "$target_seccomp" ]]; then target_seccomp_hash=$(file_sha256 "$target_seccomp"); fi
    if [[ -f "$target_apparmor" ]]; then target_apparmor_hash=$(file_sha256 "$target_apparmor"); fi
    if [[ -f "$target_seccomp_proxy" ]]; then target_seccomp_proxy_hash=$(file_sha256 "$target_seccomp_proxy"); fi
    if [[ -f "$target_apparmor_proxy" ]]; then target_apparmor_proxy_hash=$(file_sha256 "$target_apparmor_proxy"); fi
    if [[ -f "$target_seccomp_fwd" ]]; then target_seccomp_fwd_hash=$(file_sha256 "$target_seccomp_fwd"); fi
    if [[ -f "$target_apparmor_fwd" ]]; then target_apparmor_fwd_hash=$(file_sha256 "$target_apparmor_fwd"); fi

    if [[ "$repo_seccomp_hash" = "${target_seccomp_hash:-}" ]] && \
       [[ "$repo_apparmor_hash" = "${target_apparmor_hash:-}" ]] && \
       [[ "$repo_seccomp_proxy_hash" = "${target_seccomp_proxy_hash:-}" ]] && \
       [[ "$repo_apparmor_proxy_hash" = "${target_apparmor_proxy_hash:-}" ]] && \
       [[ "$repo_seccomp_fwd_hash" = "${target_seccomp_fwd_hash:-}" ]] && \
       [[ "$repo_apparmor_fwd_hash" = "${target_apparmor_fwd_hash:-}" ]]; then
        echo "✓ Security assets already current at $asset_dir"
        # Clean legacy names if we already have permissions; ignore failures quietly.
        local cleaner=()
        if [[ "$(id -u)" -eq 0 ]]; then
            cleaner=()
        elif command -v sudo >/dev/null 2>&1; then
            cleaner=(sudo)
        fi
        if [[ ${#cleaner[@]} -gt 0 || "$(id -u)" -eq 0 ]]; then
            "${cleaner[@]}" rm -f \
                "$asset_dir/seccomp-coding-agents.json" \
                "$asset_dir/apparmor-coding-agents.profile" \
                "$asset_dir/seccomp-containai.json" \
                "$asset_dir/apparmor-containai.profile" \
                "$asset_dir/seccomp-containai-agent.json" \
                "$asset_dir/apparmor-containai-agent.profile" >/dev/null 2>&1 || true
        fi
        return 0
    fi

    if [[ "$dry_run" -eq 1 ]]; then
        echo "↻ Security assets differ from repo; run with sudo ./scripts/setup-local-dev.sh to update."
        return 1
    fi

    local runner=()
    if [[ "$(id -u)" -ne 0 ]]; then
        if command -v sudo >/dev/null 2>&1; then
            runner=(sudo)
        else
            echo "⚠️  sudo not available; attempting to write security assets without elevation." >&2
        fi
    fi

    "${runner[@]}" install -d -m 0755 "$asset_dir"
    "${runner[@]}" install -m 0644 "$src_seccomp" "$target_seccomp"
    "${runner[@]}" install -m 0644 "$src_apparmor" "$target_apparmor"
    "${runner[@]}" install -m 0644 "$src_seccomp_proxy" "$target_seccomp_proxy"
    "${runner[@]}" install -m 0644 "$src_apparmor_proxy" "$target_apparmor_proxy"
    "${runner[@]}" install -m 0644 "$src_seccomp_fwd" "$target_seccomp_fwd"
    "${runner[@]}" install -m 0644 "$src_apparmor_fwd" "$target_apparmor_fwd"

    cat <<EOF | "${runner[@]}" tee "$manifest_path" >/dev/null
seccomp-containai-agent.json $repo_seccomp_hash
apparmor-containai-agent.profile $repo_apparmor_hash
seccomp-containai-proxy.json $repo_seccomp_proxy_hash
apparmor-containai-proxy.profile $repo_apparmor_proxy_hash
seccomp-containai-log-forwarder.json $repo_seccomp_fwd_hash
apparmor-containai-log-forwarder.profile $repo_apparmor_fwd_hash
EOF

    # Remove legacy names to avoid stale policy usage.
    "${runner[@]}" rm -f \
        "$asset_dir/seccomp-coding-agents.json" \
        "$asset_dir/apparmor-coding-agents.profile" \
        "$asset_dir/seccomp-containai-agent.json" \
        "$asset_dir/apparmor-containai-agent.profile"

    echo "✓ Security assets synced to $asset_dir"
}

if [[ $CHECK_ONLY -eq 1 ]]; then
    install_security_assets 1
    exit $?
fi

install_security_assets

# Determine shell rc file
if [[ -n "${ZSH_VERSION:-}" ]] || [[ "$SHELL" == *"zsh"* ]]; then
    RC_FILE="$HOME/.zshrc"
else
    RC_FILE="$HOME/.bashrc"
fi

# Create rc file if it doesn't exist
touch "$RC_FILE"

# Check if already in PATH
if grep -q "$LAUNCHERS_PATH" "$RC_FILE" 2>/dev/null; then
    echo "✓ Launchers already in $RC_FILE"
else
    # Add to rc file
    {
        echo ""
        echo "# ContainAI launchers"
        echo "export PATH=\"$LAUNCHERS_PATH:\$PATH\""
    } >> "$RC_FILE"
    
    echo "✓ Added to $RC_FILE"
    echo ""
    echo "NOTE: Restart your terminal or run: source $RC_FILE"
fi

# Update current session
export PATH="$LAUNCHERS_PATH:$PATH"

echo ""
echo "Installation complete! You can now run:"
echo "  run-copilot, run-codex, run-claude"
echo "  launch-agent, list-agents, remove-agent"
