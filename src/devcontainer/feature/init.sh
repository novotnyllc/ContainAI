#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════
# init.sh - ContainAI postCreateCommand (runs once after container created)
#
# Responsibilities:
# - Verify sysbox environment
# - Create symlinks from link-spec.json (rewrite paths to user home)
# - Skip credential files unless enableCredentials=true
# ══════════════════════════════════════════════════════════════════════
set -euo pipefail

CONFIG_FILE="/usr/local/share/containai/config.json"

# Parse configuration from JSON (SECURITY: don't source untrusted data)
if [[ ! -f "$CONFIG_FILE" ]]; then
    printf 'ERROR: Configuration file not found: %s\n' "$CONFIG_FILE" >&2
    exit 1
fi

# Read config values using jq
ENABLE_CREDENTIALS=$(jq -r '.enable_credentials // false' "$CONFIG_FILE")
REMOTE_USER=$(jq -r '.remote_user // "auto"' "$CONFIG_FILE")

# Verify sysbox first
/usr/local/share/containai/verify-sysbox.sh || exit 1

DATA_DIR="/mnt/agent-data"
LINK_SPEC="/usr/local/lib/containai/link-spec.json"

# ──────────────────────────────────────────────────────────────────────
# Detect user home directory
# Devcontainers typically use: vscode, node, or root
# Uses getent passwd for accurate home directory resolution
# ──────────────────────────────────────────────────────────────────────
detect_user_home() {
    local target_user="$REMOTE_USER"

    # Auto-detect user if not specified
    if [[ "$target_user" == "auto" || -z "$target_user" ]]; then
        if id -u vscode &>/dev/null; then
            target_user="vscode"
        elif id -u node &>/dev/null; then
            target_user="node"
        elif [[ -n "${USER:-}" ]]; then
            target_user="$USER"
        else
            target_user="root"
        fi
    fi

    # Use getent passwd for accurate home directory resolution (if available)
    local home_dir=""
    if command -v getent &>/dev/null; then
        home_dir=$(getent passwd "$target_user" 2>/dev/null | cut -d: -f6)
    fi

    if [[ -n "$home_dir" && -d "$home_dir" ]]; then
        printf '%s' "$home_dir"
    elif [[ "$target_user" == "root" ]]; then
        printf '/root'
    elif [[ -d "/home/$target_user" ]]; then
        # Fallback: check if /home/<user> exists
        printf '/home/%s' "$target_user"
    elif [[ -n "${HOME:-}" && -d "$HOME" ]]; then
        # Last resort: use $HOME if set
        printf '%s' "$HOME"
    else
        # Final fallback to /home/<user> convention
        printf '/home/%s' "$target_user"
    fi
}

USER_HOME=$(detect_user_home)
printf 'ContainAI init: Setting up symlinks in %s\n' "$USER_HOME"

# Only set up symlinks if data volume is mounted
if [[ ! -d "$DATA_DIR" ]]; then
    printf 'Warning: Data volume not mounted at %s\n' "$DATA_DIR"
    printf 'Run "cai import" on host, then rebuild container with dataVolume option\n'
    exit 0
fi

# ──────────────────────────────────────────────────────────────────────
# Credential file targets that should be SKIPPED unless enableCredentials=true
# These contain tokens/API keys that should not be exposed to untrusted code
# ──────────────────────────────────────────────────────────────────────
CREDENTIAL_TARGETS=(
    "/mnt/agent-data/config/gh/hosts.yml"            # GitHub token
    "/mnt/agent-data/claude/credentials.json"        # Claude API key
    "/mnt/agent-data/codex/config.toml"              # May contain keys
    "/mnt/agent-data/codex/auth.json"                # Codex auth
    "/mnt/agent-data/local/share/opencode/auth.json" # OpenCode auth
    "/mnt/agent-data/gemini/settings.json"           # Gemini API keys
    "/mnt/agent-data/gemini/oauth_creds.json"        # Gemini OAuth
)

is_credential_file() {
    local target="$1"
    for cred in "${CREDENTIAL_TARGETS[@]}"; do
        [[ "$target" == "$cred" ]] && return 0
    done
    return 1
}

# ──────────────────────────────────────────────────────────────────────
# Process links from link-spec.json
# No hardcoded symlink lists - reads canonical source
# ──────────────────────────────────────────────────────────────────────
if [[ ! -f "$LINK_SPEC" ]]; then
    printf 'Warning: link-spec.json not found at %s\n' "$LINK_SPEC"
    printf 'Feature may not be fully installed\n'
    exit 0
fi

# Get home_dir from link-spec.json (usually /home/agent in container images)
SPEC_HOME=$(jq -r '.home_dir // "/home/agent"' "$LINK_SPEC")

# Process each link entry
links_count=$(jq -r '.links | length' "$LINK_SPEC")
created_count=0
skipped_count=0

for i in $(seq 0 $((links_count - 1))); do
    link=$(jq -r ".links[$i].link" "$LINK_SPEC")
    target=$(jq -r ".links[$i].target" "$LINK_SPEC")
    remove_first=$(jq -r ".links[$i].remove_first // 0" "$LINK_SPEC")

    # Skip credential files unless explicitly enabled
    if [[ "$ENABLE_CREDENTIALS" != "true" ]] && is_credential_file "$target"; then
        printf '  ⊘ %s (credentials disabled)\n' "$link"
        ((skipped_count++)) || true
        continue
    fi

    # Rewrite link path from spec's home_dir to detected USER_HOME
    # e.g., /home/agent/.config -> /home/vscode/.config
    link="${link/$SPEC_HOME/$USER_HOME}"

    # Skip if target doesn't exist in data volume
    if [[ ! -e "$target" ]]; then
        continue
    fi

    # Create parent directory
    mkdir -p "$(dirname "$link")"

    # Handle remove_first for directories (ln -sfn can't replace non-symlink directories)
    if [[ -d "$link" && ! -L "$link" ]]; then
        if [[ "$remove_first" == "true" || "$remove_first" == "1" ]]; then
            rm -rf "$link"
        else
            printf '  ✗ %s (directory exists, remove_first not set)\n' "$link" >&2
            continue
        fi
    fi

    # Create symlink (ln -sfn handles existing files/symlinks)
    if ln -sfn "$target" "$link" 2>/dev/null; then
        printf '  ✓ %s → %s\n' "$link" "$target"
        ((created_count++)) || true
    else
        printf '  ✗ %s (failed)\n' "$link" >&2
    fi
done

printf '\nContainAI init complete: %d symlinks created' "$created_count"
if [[ "$skipped_count" -gt 0 ]]; then
    printf ', %d credential files skipped' "$skipped_count"
fi
printf '\n'
