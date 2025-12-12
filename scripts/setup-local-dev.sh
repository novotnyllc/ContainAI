#!/usr/bin/env bash
# Install containai launchers to PATH
# Adds host/launchers/entrypoints directory to ~/.bashrc or ~/.zshrc

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LAUNCHERS_PATH="$REPO_ROOT/host/launchers/entrypoints"
# Security profiles MUST be root-owned to prevent tampering - same location for dev and prod
# This path is hardcoded and NOT overridable - security critical.
readonly CONTAINAI_SYSTEM_PROFILES_DIR="/opt/containai/profiles"
# Source profiles in repo (these get copied to system location)
SECURITY_PROFILES_DIR="$REPO_ROOT/host/profiles"
# Channel for profile names (dev, nightly, prod)
CONTAINAI_LAUNCHER_CHANNEL="${CONTAINAI_LAUNCHER_CHANNEL:-dev}"
# Manifest name includes channel for multi-channel coexistence
SECURITY_MANIFEST_NAME="containai-profiles-${CONTAINAI_LAUNCHER_CHANNEL}.sha256"
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

# Source common functions for DRY
# shellcheck source=../host/utils/common-functions.sh
source "$REPO_ROOT/host/utils/common-functions.sh"

echo "Installing launchers to PATH..."

install_security_assets() {
    local dry_run="${1:-0}"
    local asset_dir="$CONTAINAI_SYSTEM_PROFILES_DIR"
    local channel="$CONTAINAI_LAUNCHER_CHANNEL"
    local manifest_path="$asset_dir/$SECURITY_MANIFEST_NAME"
    local prepare_profiles="$REPO_ROOT/host/utils/prepare-profiles.sh"

    echo "Syncing security profiles to $asset_dir (channel: $channel)..."

    # Verify source profiles exist
    local required_sources=(
        "$SECURITY_PROFILES_DIR/seccomp-containai-agent.json"
        "$SECURITY_PROFILES_DIR/apparmor-containai-agent.profile"
        "$SECURITY_PROFILES_DIR/seccomp-containai-proxy.json"
        "$SECURITY_PROFILES_DIR/apparmor-containai-proxy.profile"
        "$SECURITY_PROFILES_DIR/seccomp-containai-log-forwarder.json"
        "$SECURITY_PROFILES_DIR/apparmor-containai-log-forwarder.profile"
        "$SECURITY_PROFILES_DIR/apparmor-containai-logcollector.profile"
    )
    for src in "${required_sources[@]}"; do
        if [[ ! -f "$src" ]]; then
            echo "❌ Security profile missing: $src" >&2
            exit 1
        fi
    done

    # Verify prepare-profiles.sh exists
    if [[ ! -x "$prepare_profiles" ]]; then
        echo "❌ prepare-profiles.sh not found or not executable: $prepare_profiles" >&2
        exit 1
    fi

    # Use shared AppArmor prereq checks from common-functions.sh
    require_apparmor_tools || exit 1
    require_apparmor_enabled || exit 1

    # Check if update is needed by comparing source hashes with existing manifest
    local needs_update=0
    if [[ ! -f "$manifest_path" ]]; then
        needs_update=1
    else
        # Generate fresh manifest to compare
        local temp_dir
        temp_dir="$(mktemp -d)"
        trap 'rm -rf "$temp_dir"' RETURN
        
        if "$prepare_profiles" --channel "$channel" --source "$SECURITY_PROFILES_DIR" --dest "$temp_dir" --manifest "$temp_dir/manifest" 2>/dev/null; then
            if ! diff -q "$temp_dir/manifest" "$manifest_path" >/dev/null 2>&1; then
                needs_update=1
            fi
        else
            needs_update=1
        fi
    fi

    if [[ "$needs_update" -eq 0 ]]; then
        echo "✓ Security assets already current at $asset_dir"
    else
        if [[ "$dry_run" -eq 1 ]]; then
            echo "↻ Security assets differ from repo; run with sudo ./scripts/setup-local-dev.sh to update."
            return 1
        fi

        local runner=()
        if [[ "$(id -u)" -ne 0 ]]; then
            if command -v sudo >/dev/null 2>&1; then
                runner=(sudo)
            else
                echo "❌ sudo not available; root privileges required to install security assets." >&2
                exit 1
            fi
        fi

        # Create asset directory
        "${runner[@]}" install -d -m 0755 "$asset_dir"

        # Generate channel-specific profiles directly to system location
        # Use a temp directory first, then move with proper ownership
        local staging_dir
        staging_dir="$(mktemp -d)"
        
        if ! "$prepare_profiles" --channel "$channel" --source "$SECURITY_PROFILES_DIR" --dest "$staging_dir" --manifest "$staging_dir/$SECURITY_MANIFEST_NAME"; then
            rm -rf "$staging_dir"
            echo "❌ Failed to generate security profiles for channel $channel" >&2
            exit 1
        fi

        # Install generated files using shared function (handles copy, manifest, and loading)
        # The shared function needs root, so we may need to re-invoke with sudo
        if [[ "$(id -u)" -ne 0 ]]; then
            # Re-invoke the shared function with sudo
            "${runner[@]}" bash -c "
                source '$REPO_ROOT/host/utils/common-functions.sh'
                install_security_profiles_to_system '$staging_dir' '$channel' '$SECURITY_MANIFEST_NAME'
            " || {
                rm -rf "$staging_dir"
                echo "❌ Failed to install security profiles" >&2
                exit 1
            }
        else
            install_security_profiles_to_system "$staging_dir" "$channel" "$SECURITY_MANIFEST_NAME" || {
                rm -rf "$staging_dir"
                echo "❌ Failed to install security profiles" >&2
                exit 1
            }
        fi
        rm -rf "$staging_dir"
    fi
}

if [[ $CHECK_ONLY -eq 1 ]]; then
    install_security_assets 1
    exit $?
fi

install_security_assets

# Run prerequisite and health checks AFTER security assets are installed
# This ensures profiles are in place before checking for them
echo ""
echo "Running ContainAI prerequisite and health checks..."
echo ""
if ! "$REPO_ROOT/host/utils/verify-prerequisites.sh"; then
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "❌ Prerequisite verification failed."
    echo ""
    echo "Review the errors marked with ✗ above and fix them, then re-run:"
    echo "    ./scripts/setup-local-dev.sh"
    echo ""
    echo "Common fixes:"
    echo "  • Docker not running    → Start Docker Desktop or: sudo systemctl start docker"
    echo "  • Git not configured    → git config --global user.name \"Your Name\""
    echo "                            git config --global user.email \"you@example.com\""
    echo "  • socat missing         → sudo apt-get install socat  (Debian/Ubuntu)"
    echo "                            brew install socat          (macOS)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    exit 1
fi

if ! "$REPO_ROOT/host/utils/check-health.sh"; then
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "❌ Health check failed."
    echo ""
    echo "Review the errors above and fix them, then re-run:"
    echo "    ./scripts/setup-local-dev.sh"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    exit 1
fi

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
