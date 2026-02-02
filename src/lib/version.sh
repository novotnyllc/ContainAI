#!/usr/bin/env bash
# ==============================================================================
# ContainAI Version Library - Version display and update commands
# ==============================================================================
# This file must be sourced, not executed directly.
#
# Provides:
#   _cai_version()       - Show current version
#   _cai_update_code()   - Update ContainAI CLI code (channel-aware git checkout)
#   _cai_resolve_update_mode() - Determine update mode (branch/nightly/stable)
#
# Dependencies:
#   - Requires lib/core.sh to be sourced first for logging functions
#
# Usage: source lib/version.sh
# ==============================================================================

# Require bash first (before using BASH_SOURCE)
if [[ -z "${BASH_VERSION:-}" ]]; then
    echo "[ERROR] lib/version.sh requires bash" >&2
    return 1 2>/dev/null || exit 1
fi

# Detect direct execution (must be sourced, not executed)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "[ERROR] lib/version.sh must be sourced, not executed directly" >&2
    echo "Usage: source lib/version.sh" >&2
    exit 1
fi

# Guard against re-sourcing side effects
if [[ -n "${_CAI_VERSION_LOADED:-}" ]]; then
    return 0
fi
_CAI_VERSION_LOADED=1

# ==============================================================================
# Version display
# ==============================================================================

# Get ContainAI version from VERSION file
# Outputs: Version string (e.g., "0.1.0")
# Returns: 0=success, 1=VERSION file not found
_cai_get_version() {
    local version_file="$_CAI_SCRIPT_DIR/../VERSION"

    # Try relative path from lib directory first
    if [[ ! -f "$version_file" ]]; then
        # Try parent of script directory (for when sourced from containai.sh)
        version_file="$(cd -- "$_CAI_SCRIPT_DIR/.." 2>/dev/null && pwd)/VERSION"
    fi

    if [[ ! -f "$version_file" ]]; then
        return 1
    fi

    # Read and trim whitespace
    tr -d '[:space:]' <"$version_file"
    return 0
}

# Escape a string for JSON output
# Arguments: $1 = string to escape
# Outputs: JSON-safe escaped string
_cai_json_escape() {
    local str="$1"
    # Escape backslashes first, then quotes, then other control chars
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\r'/\\r}"
    str="${str//$'\t'/\\t}"
    printf '%s' "$str"
}

# Show version information
# Arguments: $1 = "json" for JSON output (optional)
# Returns: 0=success, 1=error
_cai_version() {
    local json_output="false"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json)
                json_output="true"
                shift
                ;;
            --help | -h)
                _cai_version_help
                return 0
                ;;
            *)
                _cai_error "Unknown option: $1"
                _cai_info "Use 'cai version --help' for usage"
                return 1
                ;;
        esac
    done

    local version
    if ! version=$(_cai_get_version); then
        _cai_error "VERSION file not found"
        return 1
    fi

    # Detect install type
    local install_type="unknown"
    local install_dir=""

    # Check if running from git repo
    if [[ -d "$_CAI_SCRIPT_DIR/../.git" ]]; then
        install_type="git"
        install_dir="$(cd -- "$_CAI_SCRIPT_DIR/.." 2>/dev/null && pwd)"
    elif [[ -n "${CAI_INSTALL_DIR:-}" ]]; then
        install_dir="$CAI_INSTALL_DIR"
        if [[ -d "$install_dir/.git" ]]; then
            install_type="git"
        else
            install_type="local"
        fi
    fi

    if [[ "$json_output" == "true" ]]; then
        # Use proper JSON escaping for paths
        local escaped_dir
        escaped_dir=$(_cai_json_escape "$install_dir")
        printf '{"version":"%s","install_type":"%s","install_dir":"%s"}\n' \
            "$version" "$install_type" "$escaped_dir"
    else
        printf 'ContainAI version %s\n' "$version"
        if [[ "$install_type" == "git" ]]; then
            _cai_info "Install type: git (${install_dir})"
        elif [[ -n "$install_dir" ]]; then
            _cai_info "Install dir: ${install_dir}"
        fi
    fi

    return 0
}

_cai_version_help() {
    cat <<'EOF'
ContainAI Version - Show version information

Usage: cai version [options]

Options:
  --json        Output machine-parseable JSON
  -h, --help    Show this help message

Examples:
  cai version           Show current version
  cai version --json    Output version as JSON
EOF
}

# ==============================================================================
# Update functionality
# ==============================================================================

# Determine the update mode and target based on CAI_BRANCH and channel config
# Precedence:
#   1. CAI_BRANCH env var - explicit branch override (power users)
#   2. CAI_CHANNEL env var - channel override
#   3. _cai_config_channel() - channel from config file
#   4. Default: stable (checkout latest tag)
#
# Returns: 0=success
# Sets globals:
#   _CAI_UPDATE_MODE: "branch", "nightly", or "stable"
#   _CAI_UPDATE_TARGET: branch name for "branch" mode, empty otherwise
#   _CAI_UPDATE_DISPLAY: human-readable description
_cai_resolve_update_mode() {
    _CAI_UPDATE_MODE=""
    _CAI_UPDATE_TARGET=""
    _CAI_UPDATE_DISPLAY=""

    # 1. Check for explicit branch override (takes full precedence)
    if [[ -n "${CAI_BRANCH:-}" ]]; then
        # Validate branch name (reject option-like values)
        if [[ "$CAI_BRANCH" == -* ]]; then
            _cai_warn "Invalid CAI_BRANCH value: '$CAI_BRANCH' (looks like an option)"
            _cai_warn "Falling back to channel-based update"
        else
            _CAI_UPDATE_MODE="branch"
            _CAI_UPDATE_TARGET="$CAI_BRANCH"
            _CAI_UPDATE_DISPLAY="branch: $CAI_BRANCH (CAI_BRANCH override)"
            return 0
        fi
    fi

    # 2. Check CAI_CHANNEL env var (task spec precedence: env var before config file)
    # CAI_CHANNEL is the shorter env var name for scripting (like install.sh uses)
    # CONTAINAI_CHANNEL is checked by _cai_config_channel for runtime config
    local channel="stable"
    if [[ -n "${CAI_CHANNEL:-}" ]]; then
        case "${CAI_CHANNEL}" in
            stable|nightly)
                channel="${CAI_CHANNEL}"
                ;;
            *)
                _cai_warn "Invalid CAI_CHANNEL='$CAI_CHANNEL', falling back to stable"
                channel="stable"
                ;;
        esac
    elif command -v _cai_config_channel >/dev/null 2>&1; then
        # Use config system (checks CONTAINAI_CHANNEL env var and config file)
        channel=$(_cai_config_channel)
    fi

    case "$channel" in
        nightly)
            _CAI_UPDATE_MODE="nightly"
            _CAI_UPDATE_TARGET=""
            _CAI_UPDATE_DISPLAY="nightly channel (main branch)"
            ;;
        *)
            # stable (default)
            _CAI_UPDATE_MODE="stable"
            _CAI_UPDATE_TARGET=""
            _CAI_UPDATE_DISPLAY="stable channel (latest release)"
            ;;
    esac

    return 0
}

# Update ContainAI code distribution (git-based CLI code)
# Supports channel-aware updates:
#   - CAI_BRANCH: explicit branch override (highest precedence)
#   - stable channel: fetches tags, checks out latest v* tag
#   - nightly channel: pulls latest main branch
# Arguments: [--check] to only check for updates without installing
# Returns: 0=success/up-to-date, 1=error
# Note: This updates the CLI code. For infrastructure updates (sysbox, Docker), see update.sh
_cai_update_code() {
    local check_only="false"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --check)
                check_only="true"
                shift
                ;;
            --help | -h)
                _cai_update_code_help
                return 0
                ;;
            *)
                _cai_error "Unknown option: $1"
                return 1
                ;;
        esac
    done

    # Get current version
    local current_version
    if ! current_version=$(_cai_get_version); then
        _cai_error "VERSION file not found"
        return 1
    fi

    # Determine install directory
    local install_dir=""
    if [[ -d "$_CAI_SCRIPT_DIR/../.git" ]]; then
        install_dir="$(cd -- "$_CAI_SCRIPT_DIR/.." 2>/dev/null && pwd)"
    elif [[ -n "${CAI_INSTALL_DIR:-}" ]] && [[ -d "${CAI_INSTALL_DIR}/.git" ]]; then
        install_dir="$CAI_INSTALL_DIR"
    fi

    if [[ -z "$install_dir" ]] || [[ ! -d "$install_dir/.git" ]]; then
        _cai_info "Non-git installation detected"
        _cai_info ""
        _cai_info "For GHCR/Docker image updates, pull the latest image:"
        _cai_info "  docker pull ghcr.io/novotnyllc/containai:latest"
        _cai_info ""
        _cai_info "For git-based updates, re-install using:"
        _cai_info "  curl -fsSL https://raw.githubusercontent.com/novotnyllc/containai/main/install.sh | bash"
        return 0
    fi

    # Check if git is available
    if ! command -v git >/dev/null 2>&1; then
        _cai_error "git is required for updates"
        return 1
    fi

    # Resolve update mode based on CAI_BRANCH and channel config
    _cai_resolve_update_mode

    _cai_info "Checking for updates ($_CAI_UPDATE_DISPLAY)..."

    # Check for dirty working tree before any git operations
    local local_changes
    local_changes=$(cd -- "$install_dir" && git status --porcelain 2>/dev/null)
    if [[ -n "$local_changes" ]]; then
        _cai_warn "Local changes detected in $install_dir"
        _cai_warn "Please commit or stash changes before updating:"
        printf '%s\n' "$local_changes" | head -10 | while IFS= read -r line; do
            _cai_warn "  $line"
        done
        return 1
    fi

    # Fetch latest from remote (including tags for stable channel)
    _cai_info "Fetching updates from remote..."
    if ! (cd -- "$install_dir" && git fetch --tags origin 2>/dev/null); then
        _cai_error "Failed to fetch updates from remote"
        _cai_info "Check your network connection and try again"
        return 1
    fi

    # Save current state for before/after comparison
    local before_ref before_version
    if ! before_ref=$(cd -- "$install_dir" && git describe --tags --exact-match 2>/dev/null); then
        before_ref=$(cd -- "$install_dir" && git rev-parse --short HEAD 2>/dev/null) || before_ref="unknown"
    fi
    before_version="$current_version"

    # Handle update based on mode
    case "$_CAI_UPDATE_MODE" in
        branch)
            # Explicit branch override - update to latest on that branch
            local update_branch="$_CAI_UPDATE_TARGET"

            # Fetch the specific branch
            if ! (cd -- "$install_dir" && git fetch origin "refs/heads/$update_branch:refs/remotes/origin/$update_branch" 2>/dev/null); then
                _cai_error "Failed to fetch branch '$update_branch'"
                return 1
            fi

            # Check if already up to date
            local local_head remote_head
            local_head=$(cd -- "$install_dir" && git rev-parse HEAD 2>/dev/null)
            remote_head=$(cd -- "$install_dir" && git rev-parse "origin/$update_branch" 2>/dev/null)

            if [[ "$local_head" == "$remote_head" ]]; then
                _cai_ok "Already up to date (branch: $update_branch, version: $current_version)"
                return 0
            fi

            if [[ "$check_only" == "true" ]]; then
                local remote_version
                remote_version=$(cd -- "$install_dir" && git show "origin/$update_branch:VERSION" 2>/dev/null | tr -d '[:space:]') || remote_version="(unknown)"
                _cai_info "Update available: $current_version -> $remote_version"
                _cai_info "Run 'cai update' to install the update"
                return 0
            fi

            # Perform the update
            # Use checkout -B to handle both existing and new local branches
            _cai_info "Updating to latest on branch $update_branch..."
            if ! (cd -- "$install_dir" && git checkout -B "$update_branch" "origin/$update_branch" 2>/dev/null); then
                _cai_error "Failed to update branch $update_branch"
                return 1
            fi
            ;;

        nightly)
            # Nightly channel - track main branch
            # Check if already up to date
            local local_head remote_head
            local_head=$(cd -- "$install_dir" && git rev-parse HEAD 2>/dev/null)
            remote_head=$(cd -- "$install_dir" && git rev-parse origin/main 2>/dev/null)

            if [[ "$local_head" == "$remote_head" ]]; then
                local short_sha
                short_sha=$(cd -- "$install_dir" && git rev-parse --short HEAD 2>/dev/null)
                _cai_ok "Already up to date (nightly, $short_sha)"
                return 0
            fi

            if [[ "$check_only" == "true" ]]; then
                local remote_version remote_sha
                remote_version=$(cd -- "$install_dir" && git show "origin/main:VERSION" 2>/dev/null | tr -d '[:space:]') || remote_version="(unknown)"
                remote_sha=$(cd -- "$install_dir" && git rev-parse --short origin/main 2>/dev/null)
                _cai_info "Update available: $before_ref -> $remote_sha (version: $remote_version)"
                _cai_info "Run 'cai update' to install the update"
                return 0
            fi

            # Perform the update
            # Use checkout -B to handle both existing and detached states
            _cai_info "Updating to latest nightly..."
            if ! (cd -- "$install_dir" && git checkout -B main origin/main 2>/dev/null); then
                _cai_error "Failed to update to latest nightly"
                return 1
            fi
            ;;

        stable)
            # Stable channel - checkout latest semver tag
            local latest_tag
            latest_tag=$(cd -- "$install_dir" && git tag -l 'v*' | sort -V | tail -1)

            if [[ -z "$latest_tag" ]]; then
                # Gracefully handle no tags - warn and switch to main (per spec)
                _cai_warn "No release tags found, switching to main branch"
                _cai_info "Consider using nightly channel: CAI_CHANNEL=nightly cai update"
                if (cd -- "$install_dir" && git checkout -B main origin/main 2>/dev/null); then
                    _cai_ok "Switched to main (no tags available)"
                    return 0
                else
                    _cai_error "Failed to switch to main branch"
                    return 1
                fi
            fi

            # Check if already on latest tag
            local current_tag
            current_tag=$(cd -- "$install_dir" && git describe --tags --exact-match 2>/dev/null) || current_tag=""

            if [[ "$current_tag" == "$latest_tag" ]]; then
                _cai_ok "Already up to date (stable release: $latest_tag)"
                return 0
            fi

            if [[ "$check_only" == "true" ]]; then
                local remote_version
                remote_version=$(cd -- "$install_dir" && git show "$latest_tag:VERSION" 2>/dev/null | tr -d '[:space:]') || remote_version="(unknown)"
                _cai_info "Update available: $before_ref -> $latest_tag (version: $remote_version)"
                _cai_info "Run 'cai update' to install the update"
                return 0
            fi

            # Perform the update
            _cai_info "Updating to stable release: $latest_tag..."
            if ! (cd -- "$install_dir" && git checkout "$latest_tag" 2>/dev/null); then
                _cai_error "Failed to checkout $latest_tag"
                return 1
            fi
            ;;
    esac

    # Re-read version after update
    local new_version after_ref
    new_version=$(tr -d '[:space:]' <"$install_dir/VERSION")
    if ! after_ref=$(cd -- "$install_dir" && git describe --tags --exact-match 2>/dev/null); then
        after_ref=$(cd -- "$install_dir" && git rev-parse --short HEAD 2>/dev/null) || after_ref="unknown"
    fi

    # Show what changed
    case "$_CAI_UPDATE_MODE" in
        branch)
            _cai_ok "Updated branch $CAI_BRANCH: $before_ref -> $after_ref"
            ;;
        nightly)
            _cai_ok "Updated to latest nightly: $after_ref (version: $new_version)"
            ;;
        stable)
            _cai_ok "Updated to stable release: $after_ref"
            ;;
    esac

    _cai_info "Restart your shell or re-source containai.sh to use the new version"

    return 0
}

_cai_update_code_help() {
    cat <<'EOF'
ContainAI Code Update - Update CLI code distribution

Updates the ContainAI CLI code based on channel configuration.

Channel Selection (precedence highest to lowest):
  1. CAI_BRANCH env var - explicit branch override (power users)
  2. CAI_CHANNEL env var - channel override (or CONTAINAI_CHANNEL)
  3. [image].channel in config file
  4. Default: stable

Channel Behavior:
  stable (default):
    - Fetches tags, checks out latest v* tag
    - Use for production/reliable updates
    - Example: v0.2.0 -> v0.3.0

  nightly:
    - Pulls latest main branch
    - Use for latest features (may have breaking changes)
    - Example: abc123 -> def456

  CAI_BRANCH override:
    - Checks out and pulls specified branch
    - Use for testing specific branches
    - Example: CAI_BRANCH=feature-x cai update

Requirements:
  - git must be installed
  - Installation must be git-based (cloned from repo)

For Docker image updates (GHCR), use:
  cai --refresh
EOF
}

return 0
