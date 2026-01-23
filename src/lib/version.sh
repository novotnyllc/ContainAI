#!/usr/bin/env bash
# ==============================================================================
# ContainAI Version Library - Version display and update commands
# ==============================================================================
# This file must be sourced, not executed directly.
#
# Provides:
#   _cai_version()      - Show current version
#   _cai_update()       - Update ContainAI installation
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

# Get the configured or tracking branch for updates
# Arguments: $1 = install_dir
# Outputs: branch name
# Returns: 0=found, 1=not found
_cai_get_update_branch() {
    local install_dir="$1"

    # Check for CAI_BRANCH env var first (installer sets this)
    if [[ -n "${CAI_BRANCH:-}" ]]; then
        printf '%s' "$CAI_BRANCH"
        return 0
    fi

    # Try to get the upstream tracking branch
    local tracking_branch
    if tracking_branch=$(cd -- "$install_dir" && git rev-parse --abbrev-ref '@{u}' 2>/dev/null); then
        # tracking_branch is like "origin/main" - extract just branch name
        printf '%s' "${tracking_branch#*/}"
        return 0
    fi

    # Default to main
    printf 'main'
    return 0
}

# Update ContainAI installation
# Arguments: [--check] to only check for updates without installing
# Returns: 0=success/up-to-date, 1=error
_cai_update() {
    local check_only="false"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --check)
                check_only="true"
                shift
                ;;
            --help | -h)
                _cai_update_help
                return 0
                ;;
            *)
                _cai_error "Unknown option: $1"
                _cai_info "Use 'cai update --help' for usage"
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

    # Get the update branch
    local update_branch
    update_branch=$(_cai_get_update_branch "$install_dir")

    _cai_info "Checking for updates (branch: $update_branch)..."

    # Fetch latest from remote
    if ! (cd -- "$install_dir" && git fetch origin "$update_branch" --quiet 2>/dev/null); then
        _cai_error "Failed to fetch updates from remote"
        _cai_info "Check your network connection and try again"
        return 1
    fi

    # Compare commits (not just version) to detect updates
    local local_head remote_head
    local_head=$(cd -- "$install_dir" && git rev-parse HEAD 2>/dev/null)
    remote_head=$(cd -- "$install_dir" && git rev-parse "origin/$update_branch" 2>/dev/null)

    if [[ -z "$remote_head" ]]; then
        _cai_error "Could not determine remote HEAD"
        return 1
    fi

    # Check if up to date by comparing commits
    if [[ "$local_head" == "$remote_head" ]]; then
        _cai_ok "Already up to date (version $current_version)"
        return 0
    fi

    # Get remote version for display
    local remote_version
    remote_version=$(cd -- "$install_dir" && git show "origin/$update_branch:VERSION" 2>/dev/null | tr -d '[:space:]')
    if [[ -z "$remote_version" ]]; then
        remote_version="(unknown)"
    fi

    _cai_info "Update available: $current_version -> $remote_version"

    # Show changelog if available
    local changelog_diff
    changelog_diff=$(cd -- "$install_dir" && git diff HEAD.."origin/$update_branch" -- CHANGELOG.md 2>/dev/null | grep '^+' | grep -v '^+++' | head -20)
    if [[ -n "$changelog_diff" ]]; then
        _cai_info "Changes:"
        printf '%s\n' "$changelog_diff" | sed 's/^+/  /'
    fi

    if [[ "$check_only" == "true" ]]; then
        _cai_info "Run 'cai update' to install the update"
        return 0
    fi

    # Check current branch matches update branch
    local current_branch
    current_branch=$(cd -- "$install_dir" && git rev-parse --abbrev-ref HEAD 2>/dev/null)

    if [[ "$current_branch" != "$update_branch" ]]; then
        _cai_warn "Currently on branch '$current_branch', update branch is '$update_branch'"

        # Prompt for confirmation (only if interactive)
        if [[ -t 0 ]]; then
            printf '%s' "Switch to '$update_branch' and update? [y/N] "
            local confirm
            if ! read -r confirm; then
                _cai_info "Update cancelled"
                return 0
            fi
            case "$confirm" in
                y | Y | yes | YES) ;;
                *)
                    _cai_info "Update cancelled"
                    return 0
                    ;;
            esac
        else
            _cai_error "Non-interactive mode: cannot switch branches"
            _cai_info "Run: cd $install_dir && git checkout $update_branch && cai update"
            return 1
        fi
    fi

    # Check for local changes that would be lost
    local local_changes
    local_changes=$(cd -- "$install_dir" && git status --porcelain 2>/dev/null)
    if [[ -n "$local_changes" ]]; then
        _cai_warn "Local changes detected in $install_dir"
        _cai_warn "These will be discarded during update:"
        printf '%s\n' "$local_changes" | head -10 | while IFS= read -r line; do
            _cai_warn "  $line"
        done

        # Prompt for confirmation (only if interactive)
        if [[ -t 0 ]]; then
            printf '%s' "Continue with update? [y/N] "
            local confirm
            if ! read -r confirm; then
                _cai_info "Update cancelled"
                return 0
            fi
            case "$confirm" in
                y | Y | yes | YES) ;;
                *)
                    _cai_info "Update cancelled"
                    return 0
                    ;;
            esac
        else
            _cai_error "Local changes present - cannot update non-interactively"
            _cai_info "Resolve local changes or run interactively to confirm"
            return 1
        fi
    fi

    # Perform the update
    _cai_info "Updating..."

    # First checkout the update branch if needed
    if [[ "$current_branch" != "$update_branch" ]]; then
        if ! (cd -- "$install_dir" && git checkout "$update_branch" --quiet 2>/dev/null); then
            _cai_error "Failed to checkout $update_branch"
            return 1
        fi
    fi

    # Check if local update_branch is ahead of remote (would lose commits on reset)
    # Must be done AFTER checkout so we compare the correct local branch
    local ahead_behind
    ahead_behind=$(cd -- "$install_dir" && git rev-list --left-right --count "origin/${update_branch}...${update_branch}" 2>/dev/null)
    local behind ahead
    behind=$(printf '%s' "$ahead_behind" | cut -f1)
    ahead=$(printf '%s' "$ahead_behind" | cut -f2)

    if [[ "${ahead:-0}" -gt 0 ]]; then
        _cai_warn "Local '$update_branch' has $ahead commit(s) not in remote"
        _cai_warn "Updating will discard these local commits"

        # Prompt for confirmation (only if interactive)
        if [[ -t 0 ]]; then
            printf '%s' "Discard local commits and update? [y/N] "
            local confirm
            if ! read -r confirm; then
                _cai_info "Update cancelled"
                return 0
            fi
            case "$confirm" in
                y | Y | yes | YES) ;;
                *)
                    _cai_info "Update cancelled"
                    return 0
                    ;;
            esac
        else
            _cai_error "Local commits would be lost - cannot update non-interactively"
            _cai_info "Run interactively to confirm, or reset manually"
            return 1
        fi
    fi

    # Use pull --ff-only for safer updates when possible, fall back to reset
    if ! (cd -- "$install_dir" && git pull --ff-only origin "$update_branch" --quiet 2>/dev/null); then
        _cai_warn "Fast-forward not possible, using reset"
        if ! (cd -- "$install_dir" && git reset --hard "origin/$update_branch" --quiet 2>/dev/null); then
            _cai_error "Failed to update"
            return 1
        fi
    fi

    # Re-read version after update
    local new_version
    new_version=$(tr -d '[:space:]' <"$install_dir/VERSION")

    _cai_ok "Updated to version $new_version"
    _cai_info "Restart your shell or re-source containai.sh to use the new version"

    return 0
}

_cai_update_help() {
    cat <<'EOF'
ContainAI Update - Update installation

Usage: cai update [options]

Options:
  --check       Check for updates without installing
  -h, --help    Show this help message

This command updates a git-based ContainAI installation by pulling
the latest changes from the configured branch.

Branch Selection:
  - Uses CAI_BRANCH environment variable if set
  - Otherwise uses the upstream tracking branch
  - Falls back to 'main' if neither is set

Requirements:
  - git must be installed
  - Installation must be git-based (not downloaded archive)

For Docker image updates (GHCR), pull the latest image directly:
  docker pull ghcr.io/novotnyllc/containai:latest

Note: The image name may vary based on your configuration. Check your
cai config or use 'cai doctor' to see the configured image.

Examples:
  cai update           Update to latest version
  cai update --check   Check for updates without installing
EOF
}

return 0
