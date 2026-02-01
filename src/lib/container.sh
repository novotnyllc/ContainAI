#!/usr/bin/env bash
# ==============================================================================
# ContainAI Container Operations
# ==============================================================================
# This file must be sourced, not executed directly.
#
# Provides:
#   _cai_sanitize_hostname         - Sanitize value to RFC 1123 hostname
#   _containai_container_name      - Generate sanitized container name
#   _containai_legacy_container_name - Generate legacy hash-based container name
#   _cai_find_workspace_container  - Find container using shared lookup order (config/label/new/legacy)
#   _cai_find_container_by_name    - Find container by name across multiple contexts
#   _cai_resolve_container_name    - Resolve container name for creation (duplicate-aware)
#   _cai_find_container            - Find container by workspace and optional image-tag filter
#   _containai_check_isolation     - Detect container isolation status
#   _containai_validate_masked_paths - Validate Docker MaskedPaths are applied (in-container)
#   _containai_ensure_volumes      - Ensure a volume exists (takes volume name param)
#   _containai_start_container     - Start or attach to container
#   _containai_stop_all            - Stop all ContainAI containers
#
# Container inspection helpers:
#   _containai_container_exists         - Check if container exists
#   _containai_get_container_label      - Get ContainAI label value
#   _containai_get_container_image      - Get container image name
#   _containai_get_container_data_volume - Get mounted data volume name
#   _containai_is_our_container         - Check if container belongs to ContainAI
#   _containai_check_container_ownership - Check ownership with error messaging
#   _containai_check_volume_match       - Check if volume matches desired
#
# Constants:
#   _CONTAINAI_IMAGE              - Default image name
#   _CONTAINAI_LABEL              - Container label for ContainAI ownership
#
# Dependencies:
#   - lib/core.sh (logging functions)
#   - lib/docker.sh (Docker availability checks)
#   - lib/doctor.sh (context selection: _cai_select_context, _cai_sysbox_available_for_context)
#
# Usage: source lib/container.sh
# ==============================================================================

# Require bash first (before using BASH_SOURCE)
if [[ -z "${BASH_VERSION:-}" ]]; then
    echo "[ERROR] lib/container.sh requires bash" >&2
    return 1 2>/dev/null || exit 1
fi

# Detect direct execution (must be sourced, not executed)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "[ERROR] lib/container.sh must be sourced, not executed directly" >&2
    echo "Usage: source lib/container.sh" >&2
    exit 1
fi

# ==============================================================================
# Constants
# ==============================================================================

# Guard against re-sourcing
: "${_CONTAINAI_LABEL:=containai.managed=true}"

# ==============================================================================
# Security: Docker Default Protections
# ==============================================================================
#
# Docker applies MaskedPaths and ReadonlyPaths by default for all containers.
# These provide baseline protection against container escape vectors.
# Sysbox respects these defaults.
#
# IMPORTANT: We must NEVER disable these defaults by using:
#   - --security-opt systempaths=unconfined
#   - --privileged (disables ALL security features)
#
# MaskedPaths (bind-mounted from /dev/null - appears empty):
#   /proc/acpi, /proc/asound, /proc/interrupts, /proc/kcore, /proc/keys,
#   /proc/latency_stats, /proc/sched_debug, /proc/scsi, /proc/timer_list,
#   /proc/timer_stats, /sys/devices/virtual/powercap, /sys/firmware
#
# ReadonlyPaths (mounted read-only in container):
#   /proc/bus, /proc/fs, /proc/irq, /proc/sys, /proc/sysrq-trigger
#
# Future hardening (deferred - requires baseline testing):
#   - --security-opt=no-new-privileges: Conflicts with entrypoint sudo usage
#   - --cap-drop=ALL: Needs capability baseline established first
#
# See: https://docs.docker.com/engine/security/seccomp/
# ==============================================================================
: "${_CONTAINAI_DEFAULT_REPO:=containai}"
: "${_CONTAINAI_DEFAULT_AGENT:=claude}"
: "${_CONTAINAI_DEFAULT_CREDENTIALS:=none}"

# Map agent name to default image tag
# Format: agent -> tag
declare -A _CONTAINAI_AGENT_TAGS 2>/dev/null || true
_CONTAINAI_AGENT_TAGS=(
    [claude]="latest"
    [gemini]="latest"
)

# ==============================================================================
# Image resolution
# ==============================================================================

# Resolve the image to use based on agent and optional tag override
# Arguments: $1 = agent name (claude, gemini), $2 = optional image tag override
# Outputs: Full image name (repo:tag)
# Returns: 0 on success, 1 on invalid agent
_containai_resolve_image() {
    local agent="${1:-$_CONTAINAI_DEFAULT_AGENT}"
    local explicit_tag="${2:-}"
    local repo="$_CONTAINAI_DEFAULT_REPO"
    local tag

    # Validate agent and get default tag
    if [[ -z "${_CONTAINAI_AGENT_TAGS[$agent]:-}" ]]; then
        _cai_error "Unknown agent: $agent"
        _cai_error "  Supported agents: claude, gemini"
        return 1
    fi

    # Tag precedence: --image-tag > CONTAINAI_AGENT_TAG > agent default
    if [[ -n "$explicit_tag" ]]; then
        tag="$explicit_tag"
    elif [[ -n "${CONTAINAI_AGENT_TAG:-}" ]]; then
        tag="$CONTAINAI_AGENT_TAG"
    else
        tag="${_CONTAINAI_AGENT_TAGS[$agent]}"
    fi

    printf '%s:%s' "$repo" "$tag"
    return 0
}

# Check if image exists locally
# Arguments: $1 = image name, $2 = context name (optional)
# Returns: 0 if exists, 1 if not found
_containai_check_image() {
    local image="$1"
    local context="${2:-}"
    local inspect_output
    local -a docker_cmd=(docker)
    if [[ -n "$context" ]]; then
        docker_cmd=(docker --context "$context")
    fi

    if ! inspect_output=$("${docker_cmd[@]}" image inspect "$image" 2>&1); then
        if printf '%s' "$inspect_output" | grep -qiE "no such image|not found"; then
            _cai_error "Image not found: $image"
            if [[ -n "$context" ]]; then
                _cai_warn "Pull the image with: docker --context $context pull $image"
            else
                _cai_warn "Pull the image with: docker pull $image"
            fi
        else
            printf '%s\n' "$inspect_output" >&2
        fi
        return 1
    fi
    return 0
}

# ==============================================================================
# Volume name validation (local copy for independence from config.sh)
# ==============================================================================

# Validate Docker volume name pattern (private helper to avoid collision with config.sh)
# Pattern: ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$
# Length: 1-255 characters
# Returns: 0=valid, 1=invalid
_containai__validate_volume_name() {
    local name="$1"

    # Check length
    if [[ -z "$name" ]] || [[ ${#name} -gt 255 ]]; then
        return 1
    fi

    # Check pattern: must start with alphanumeric, followed by alphanumeric, underscore, dot, or dash
    if [[ ! "$name" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]]; then
        return 1
    fi

    return 0
}

# ==============================================================================
# Docker availability check
# ==============================================================================

# Check if Docker is available and responsive
# Returns: 0=available, 1=not available (with error message)
# Note: Uses _cai_docker_available for timeout-protected daemon check
_containai_check_docker() {
    # Delegate to lib/docker.sh which has timeout protection
    # The 'verbose' flag enables actionable error messages
    if ! _cai_docker_available verbose; then
        return 1
    fi
    return 0
}

# ==============================================================================
# Container log capture
# ==============================================================================

# Write docker logs for a container to ~/.config/containai/logs/ with a smart name
# Arguments:
#   $1 = container name
#   $2 = docker context (optional)
#   $3 = reason tag (optional, e.g., "start-timeout")
# Outputs: log file path on stdout
# Returns: 0 on success, 1 on failure
_cai_write_container_logs() {
    local container_name="$1"
    local context="${2:-}"
    local reason="${3:-startup}"
    local log_dir="$HOME/.config/containai/logs"
    local ts=""
    local ctx_label="${context:-default}"
    local safe_container=""
    local safe_context=""
    local safe_reason=""
    local log_file=""
    local -a docker_cmd=(docker)

    if ! mkdir -p "$log_dir" 2>/dev/null; then
        _cai_warn "Failed to create log directory: $log_dir"
        return 1
    fi

    ts=$(date -u +%Y%m%dT%H%M%SZ 2>/dev/null)
    if [[ -z "$ts" ]]; then
        ts=$(date +%Y%m%dT%H%M%SZ 2>/dev/null)
    fi
    if [[ -z "$ts" ]]; then
        ts="unknown-time"
    fi

    safe_container="${container_name//[^a-zA-Z0-9_.-]/_}"
    safe_context="${ctx_label//[^a-zA-Z0-9_.-]/_}"
    safe_reason="${reason//[^a-zA-Z0-9_.-]/_}"
    log_file="$log_dir/docker-${safe_container}-${safe_context}-${safe_reason}-${ts}.log"

    if [[ -n "$context" ]]; then
        docker_cmd=(docker --context "$context")
    fi

    {
        printf '%s\n' "# ContainAI docker logs"
        printf '%s\n' "timestamp=$ts"
        printf '%s\n' "container=$container_name"
        printf '%s\n' "context=$ctx_label"
        printf '%s\n' "reason=$reason"
        printf '\n'
        "${docker_cmd[@]}" logs "$container_name" 2>&1 || printf '%s\n' "[ERROR] docker logs failed"
    } >"$log_file" || {
        _cai_warn "Failed to write container logs: $log_file"
        return 1
    }

    printf '%s' "$log_file"
    return 0
}

# ==============================================================================
# Container naming
# ==============================================================================

# Portable path hashing for container naming
# Normalizes path then hashes with SHA-256, returns first 12 hex characters
# Works on Linux (sha256sum), macOS (shasum -a 256), and fallback (openssl)
# Arguments: $1 = path to hash
# Returns: 12-character hex hash via stdout
_cai_hash_path() {
    local path="$1"
    local normalized hash

    # Normalize path using platform-aware helper
    # macOS: preserves symlinks for Lima mount compatibility
    # Linux/WSL: resolves symlinks for consistency
    normalized=$(_cai_normalize_path "$path")

    # Hash with most available tool (all output same format for same input)
    if command -v sha256sum >/dev/null 2>&1; then
        # Linux: sha256sum
        hash=$(printf '%s' "$normalized" | sha256sum | cut -c1-12)
    elif command -v shasum >/dev/null 2>&1; then
        # macOS: shasum -a 256
        hash=$(printf '%s' "$normalized" | shasum -a 256 | cut -c1-12)
    elif command -v openssl >/dev/null 2>&1; then
        # Fallback: openssl dgst -sha256
        hash=$(printf '%s' "$normalized" | openssl dgst -sha256 | awk '{print substr($NF,1,12)}')
    else
        # No SHA-256 tool available - this is a hard error since deterministic naming requires hashing
        echo "[ERROR] No SHA-256 tool available (sha256sum, shasum, or openssl required)" >&2
        return 1
    fi

    # Ensure hash is non-empty (should never happen with proper SHA-256 tools)
    if [[ -z "$hash" ]]; then
        echo "[ERROR] Hash computation failed for path: $normalized" >&2
        return 1
    fi

    printf '%s' "$hash"
}

# Sanitize a value to be a valid RFC 1123 hostname
# Hostnames must be: lowercase, alphanumeric + hyphens, max 63 chars,
# start/end with alphanumeric (no leading/trailing hyphens)
# Arguments: $1 = value to sanitize (required)
# Returns: sanitized hostname via stdout
_cai_sanitize_hostname() {
    local value="$1"
    local sanitized

    # Lowercase
    sanitized="${value,,}"
    # Replace underscores with hyphens (common in container names but invalid in hostnames)
    sanitized="${sanitized//_/-}"
    # Remove any character that's not alphanumeric or hyphen
    sanitized=$(printf '%s' "$sanitized" | LC_ALL=C tr -cd 'a-z0-9-')
    # Collapse multiple hyphens
    while [[ "$sanitized" == *--* ]]; do sanitized="${sanitized//--/-}"; done
    # Remove leading/trailing hyphens
    sanitized="${sanitized#-}"
    sanitized="${sanitized%-}"
    # Truncate to 63 chars (max hostname length per RFC 1123)
    sanitized="${sanitized:0:63}"
    # Remove trailing hyphen from truncation
    sanitized="${sanitized%-}"
    # Fallback if sanitizes to empty
    [[ -z "$sanitized" ]] && sanitized="container"

    printf '%s' "$sanitized"
}

# Generate container name from workspace path
# Format: {repo}-{branch_leaf}, max 24 chars (no prefix)
# Branch leaf = last segment of '/'-separated branch (e.g., feature/oauth → oauth)
# Arguments: $1 = workspace path (required)
# Returns: container name via stdout, or 1 on error
# Note: This is a pure function - no docker calls or collision logic.
#       Collision handling is done in _cai_resolve_container_name.
_containai_container_name() {
    local workspace_path="$1"
    local repo_name branch_name branch_leaf repo_s branch_s name

    if [[ -z "$workspace_path" ]]; then
        # Fallback to current directory if no workspace provided
        workspace_path="$(pwd)"
    fi

    # Get repo name = directory name (last path component)
    repo_name="${workspace_path##*/}"
    # Handle case where path ends with / (e.g., /foo/bar/)
    if [[ -z "$repo_name" ]]; then
        repo_name="${workspace_path%/}"
        repo_name="${repo_name##*/}"
    fi

    # Get branch name from git (guard against git not being installed)
    if command -v git >/dev/null 2>&1 && git -C "$workspace_path" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        branch_name=$(git -C "$workspace_path" rev-parse --abbrev-ref HEAD 2>/dev/null) || branch_name=""
        # Detached HEAD: use "detached" token (no hashes per spec)
        if [[ "$branch_name" == "HEAD" || -z "$branch_name" ]]; then
            branch_name="detached"
        fi
    else
        # Non-git directory or git not installed
        branch_name="nogit"
    fi

    # Extract branch leaf (last segment of '/'-separated branch path)
    # e.g., feature/oauth → oauth, bugfix/login-fix → login-fix, main → main
    branch_leaf="${branch_name##*/}"
    # Handle empty leaf (shouldn't happen but be safe)
    [[ -z "$branch_leaf" ]] && branch_leaf="$branch_name"

    # Sanitize repo: lowercase, remove non-alphanum except -
    repo_s="${repo_name,,}"              # lowercase
    repo_s="${repo_s//\//-}"             # / → -
    repo_s=$(printf '%s' "$repo_s" | LC_ALL=C tr -cd 'a-z0-9-')
    # Collapse multiple dashes and trim
    while [[ "$repo_s" == *--* ]]; do repo_s="${repo_s//--/-}"; done
    repo_s="${repo_s#-}"; repo_s="${repo_s%-}"
    # Fallback if repo sanitizes to empty
    [[ -z "$repo_s" ]] && repo_s="repo"

    # Sanitize branch leaf: lowercase, remove non-alphanum except -
    branch_s="${branch_leaf,,}"          # lowercase
    branch_s="${branch_s//\//-}"         # / → - (shouldn't have any, but be safe)
    branch_s=$(printf '%s' "$branch_s" | LC_ALL=C tr -cd 'a-z0-9-')
    # Collapse multiple dashes and trim
    while [[ "$branch_s" == *--* ]]; do branch_s="${branch_s//--/-}"; done
    branch_s="${branch_s#-}"; branch_s="${branch_s%-}"
    # Fallback if branch sanitizes to empty
    [[ -z "$branch_s" ]] && branch_s="branch"

    # Truncate repo/branch to fit max 24 chars: {repo}-{branch}
    # Separator = 1 char, so repo+branch max = 23 chars
    local max_combined=23
    local repo_keep=${#repo_s}
    local branch_keep=${#branch_s}
    if (( repo_keep + branch_keep > max_combined )); then
        # Prioritize repo, then truncate branch if needed
        # Start by trimming whichever is longer, alternating
        while (( repo_keep + branch_keep > max_combined )); do
            if (( repo_keep >= branch_keep && repo_keep > 1 )); then
                repo_keep=$((repo_keep - 1))
            elif (( branch_keep > 1 )); then
                branch_keep=$((branch_keep - 1))
            else
                break
            fi
        done
        repo_s="${repo_s:0:repo_keep}"
        branch_s="${branch_s:0:branch_keep}"
        # Remove trailing dashes from truncation
        repo_s="${repo_s%-}"
        branch_s="${branch_s%-}"
        [[ -z "$repo_s" ]] && repo_s="repo"
        [[ -z "$branch_s" ]] && branch_s="branch"
    fi

    # Build name: {repo}-{branch} (no prefix, max 24 chars)
    name="${repo_s}-${branch_s}"

    printf '%s' "$name"
}

# Legacy container name - MUST match existing containers
# Uses the SAME logic as current implementation to ensure compatibility
# This wraps _cai_hash_path which handles:
# - Path normalization (trailing slashes, realpath)
# - sha256sum/shasum/openssl fallback
# DO NOT reimplement the hash algorithm
# Arguments: $1 = workspace path (required)
# Returns: legacy container name via stdout, or 1 on error
_containai_legacy_container_name() {
    local workspace_path="$1"
    local hash

    if [[ -z "$workspace_path" ]]; then
        workspace_path="$(pwd)"
    fi

    # Use existing _cai_hash_path - do NOT reimplement
    if ! hash=$(_cai_hash_path "$workspace_path"); then
        return 1
    fi

    printf 'containai-%s' "$hash"
}

# Find container for a workspace using shared lookup order
# This is the primary lookup helper that all commands MUST use.
#
# Lookup order:
#   1. Workspace config: container_name from user config (if exists in docker)
#   2. Label match: containai.workspace=<resolved-path> (most reliable)
#   3. New naming format: result from _containai_container_name()
#   4. Legacy hash format: result from _containai_legacy_container_name()
#
# Arguments:
#   $1 = workspace path (required, should be normalized/resolved)
#   $2 = docker context (optional, empty for default)
#
# Returns:
#   0 with container name on stdout if found
#   1 if not found (no error message - caller should handle)
#   2 if multiple containers match (error message to stderr) - caller must abort
_cai_find_workspace_container() {
    local workspace_path="$1"
    local context="${2:-}"
    local -a docker_cmd=(docker)
    local line

    if [[ -z "$workspace_path" ]]; then
        echo "[ERROR] workspace path is required" >&2
        return 1
    fi

    [[ -n "$context" ]] && docker_cmd=(docker --context "$context")

    # 1. Workspace config: check if container_name is saved and container still exists for this workspace
    local config_name config_workspace
    if config_name=$(_containai_read_workspace_key "$workspace_path" "container_name" 2>/dev/null); then
        if [[ -n "$config_name" ]]; then
            # Check if this container actually exists (use -- for option injection protection)
            if DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" inspect --type container -- "$config_name" >/dev/null 2>&1; then
                # Verify container still belongs to this workspace via label
                config_workspace=$(DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" inspect --format '{{index .Config.Labels "containai.workspace"}}' -- "$config_name" 2>/dev/null) || config_workspace=""
                if [[ "$config_workspace" == "$workspace_path" ]]; then
                    printf '%s\n' "$config_name"
                    return 0
                fi
                # Container exists but belongs to different workspace - fall through
            fi
            # Container gone or wrong workspace - fall through to other methods
        fi
    fi

    # 2. Label match (most reliable) - with duplicate detection
    local -a by_label=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && by_label+=("$line")
    done < <(DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" ps -a \
        --filter "label=containai.workspace=$workspace_path" \
        --format '{{.Names}}' 2>/dev/null)

    # Error on multiple matches - user must be explicit
    # Return exit code 2 to distinguish from "not found"
    if [[ ${#by_label[@]} -gt 1 ]]; then
        echo "[ERROR] Multiple containers found for workspace: $workspace_path" >&2
        echo "[ERROR] Containers: ${by_label[*]}" >&2
        echo "[ERROR] Use --container to specify which one" >&2
        return 2
    fi

    if [[ ${#by_label[@]} -eq 1 ]]; then
        printf '%s\n' "${by_label[0]}"
        return 0
    fi

    # 3. New naming format (from _containai_container_name)
    local new_name
    if new_name=$(_containai_container_name "$workspace_path"); then
        if DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" inspect --type container "$new_name" >/dev/null 2>&1; then
            printf '%s\n' "$new_name"
            return 0
        fi
    fi

    # 4. Legacy hash format (using existing _cai_hash_path via wrapper)
    local legacy_name
    if legacy_name=$(_containai_legacy_container_name "$workspace_path"); then
        if DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" inspect --type container "$legacy_name" >/dev/null 2>&1; then
            printf '%s\n' "$legacy_name"
            return 0
        fi
    fi

    return 1  # Not found
}

# Find container by name across multiple Docker contexts
# Searches config-specified, secure, and default contexts. Returns error if container
# exists in multiple contexts (ambiguity). This scans all candidate contexts and does
# NOT use first-match-wins semantics.
#
# Arguments:
#   $1 = container_name (required)
#   $2 = explicit_config (optional, config file path for context override)
#   $3 = workspace_path (optional, for discovering config when explicit_config not provided)
#
# Returns:
#   0 with found context on stdout (always returns context name, including "default")
#   1 if container not found in any context
#   2 if container found in multiple contexts (ambiguous - error printed to stderr)
#   3 if explicit config parse error (error printed to stderr)
#
# Usage:
#   if found_context=$(_cai_find_container_by_name "my-container" "$config_file" "$workspace"); then
#       # Always use --context explicitly (even for "default")
#       docker --context "$found_context" inspect my-container
#   elif [[ $? -eq 2 ]]; then
#       return 1  # Ambiguity error already printed
#   elif [[ $? -eq 3 ]]; then
#       return 1  # Config parse error already printed
#   else
#       echo "Container not found"
#   fi
_cai_find_container_by_name() {
    local container_name="${1:-}"
    local explicit_config="${2:-}"
    local workspace_path="${3:-}"  # Only use if explicitly provided
    local ctx cfg_ctx c already_added
    local -a found_contexts=()

    if [[ -z "$container_name" ]]; then
        echo "[ERROR] container name is required" >&2
        return 1
    fi

    # Build list of contexts to check - prioritize configured/secure contexts over default
    local -a contexts_to_check=()

    # 1. Add secure engine context from explicit config if provided
    if [[ -n "$explicit_config" ]]; then
        # Propagate errors for explicit config (don't suppress) - user should know if config is bad
        if ! cfg_ctx=$(_containai_resolve_secure_engine_context "${workspace_path:-$PWD}" "$explicit_config"); then
            echo "[ERROR] Failed to parse config: $explicit_config" >&2
            return 3  # Config parse error (distinct from not found)
        fi
        if [[ -n "$cfg_ctx" ]]; then
            # Check if already in list (inline loop, no nested function)
            already_added=false
            for c in "${contexts_to_check[@]}"; do
                [[ "$c" == "$cfg_ctx" ]] && already_added=true && break
            done
            [[ "$already_added" == "false" ]] && contexts_to_check+=("$cfg_ctx")
        fi
    elif [[ -n "$workspace_path" ]]; then
        # 2. Only try discovered config when workspace path was explicitly provided
        # (avoids surprising behavior when cwd changes)
        cfg_ctx=$(_containai_resolve_secure_engine_context "$workspace_path" "" 2>/dev/null) || cfg_ctx=""
        if [[ -n "$cfg_ctx" ]]; then
            already_added=false
            for c in "${contexts_to_check[@]}"; do
                [[ "$c" == "$cfg_ctx" ]] && already_added=true && break
            done
            [[ "$already_added" == "false" ]] && contexts_to_check+=("$cfg_ctx")
        fi
    fi

    # 3. Add standard secure context if it exists
    already_added=false
    for c in "${contexts_to_check[@]}"; do
        [[ "$c" == "$_CAI_CONTAINAI_DOCKER_CONTEXT" ]] && already_added=true && break
    done
    if [[ "$already_added" == "false" ]]; then
        if DOCKER_CONTEXT= DOCKER_HOST= docker context inspect -- "$_CAI_CONTAINAI_DOCKER_CONTEXT" >/dev/null 2>&1; then
            contexts_to_check+=("$_CAI_CONTAINAI_DOCKER_CONTEXT")
        fi
    fi

    # 4. Add default context last (lowest priority)
    already_added=false
    for c in "${contexts_to_check[@]}"; do
        [[ "$c" == "default" ]] && already_added=true && break
    done
    [[ "$already_added" == "false" ]] && contexts_to_check+=("default")

    # Search for container in ALL contexts to detect ambiguity
    # Use DOCKER_CONTEXT= DOCKER_HOST= to avoid env leakage, and always use --context
    for ctx in "${contexts_to_check[@]}"; do
        if DOCKER_CONTEXT= DOCKER_HOST= docker --context "$ctx" inspect --type container -- "$container_name" >/dev/null 2>&1; then
            found_contexts+=("$ctx")
        fi
    done

    # Handle results
    if [[ ${#found_contexts[@]} -eq 0 ]]; then
        return 1  # Not found in any context
    elif [[ ${#found_contexts[@]} -eq 1 ]]; then
        # Found in exactly one context - success
        printf '%s' "${found_contexts[0]}"
        return 0
    else
        # Found in multiple contexts - ambiguous
        echo "[ERROR] Container '$container_name' exists in multiple contexts:" >&2
        for ctx in "${found_contexts[@]}"; do
            echo "  - $ctx" >&2
        done
        echo "Remove or rename the duplicate to resolve ambiguity." >&2
        return 2  # Ambiguity exit code
    fi
}

# Resolve container name for creation
# For new containers, determines the appropriate name to use.
# If container already exists for this workspace, returns that name.
# Otherwise returns a new name (with duplicate suffix if needed).
#
# Arguments:
#   $1 = workspace path (required, should be normalized/resolved)
#   $2 = docker context (optional, empty for default)
#
# Returns:
#   0 with container name via stdout
#   1 on error
#   2 if multiple containers exist for workspace (caller must abort)
_cai_resolve_container_name() {
    local workspace_path="$1"
    local context="${2:-}"
    local -a docker_cmd=(docker)
    local base_name candidate existing_workspace existing_name
    local suffix=1 find_rc line

    if [[ -z "$workspace_path" ]]; then
        echo "[ERROR] workspace path is required" >&2
        return 1
    fi

    [[ -n "$context" ]] && docker_cmd=(docker --context "$context")

    # First, check if a container already exists for this workspace via label
    # This prevents creating duplicates when existing container has suffixed name
    # Clear DOCKER_HOST/DOCKER_CONTEXT to make --context authoritative
    local -a by_label=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && by_label+=("$line")
    done < <(DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" ps -a \
        --filter "label=containai.workspace=$workspace_path" \
        --format '{{.Names}}' 2>/dev/null)

    # Multiple containers for same workspace - abort
    if [[ ${#by_label[@]} -gt 1 ]]; then
        echo "[ERROR] Multiple containers found for workspace: $workspace_path" >&2
        echo "[ERROR] Containers: ${by_label[*]}" >&2
        echo "[ERROR] Use --container to specify which one" >&2
        return 2
    fi

    # Found exactly one - return it
    if [[ ${#by_label[@]} -eq 1 ]]; then
        printf '%s\n' "${by_label[0]}"
        return 0
    fi

    # No existing container by label - generate new name with collision handling
    if ! base_name=$(_containai_container_name "$workspace_path"); then
        return 1
    fi
    candidate="$base_name"

    # Check if name is taken by another workspace (handle collisions)
    # Truncate base name to fit suffix while staying within 24 chars max
    # Cap suffix at 99 as a reasonable limit for edge cases
    # Clear DOCKER_HOST/DOCKER_CONTEXT to make --context authoritative
    while DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" inspect --type container "$candidate" >/dev/null 2>&1; do
        # Check if this container is for our workspace via workspace label
        existing_workspace=$(DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" inspect --format '{{index .Config.Labels "containai.workspace"}}' "$candidate" 2>/dev/null) || existing_workspace=""
        if [[ "$existing_workspace" == "$workspace_path" ]]; then
            # Same workspace - reuse this container name
            printf '%s\n' "$candidate"
            return 0
        fi
        # Different workspace (or no label) - try next suffix
        ((suffix++)) || true
        if [[ $suffix -gt 99 ]]; then
            echo "[ERROR] Too many container name collisions (max 99)" >&2
            return 1
        fi
        # Truncate base name to fit suffix within 24 chars: base + "-" + suffix
        local suffix_len=${#suffix}
        local max_base=$((24 - 1 - suffix_len))  # 24 - "-" - suffix digits
        local truncated_base="${base_name:0:$max_base}"
        # Remove trailing dash from truncation
        truncated_base="${truncated_base%-}"
        candidate="${truncated_base}-${suffix}"
    done

    printf '%s\n' "$candidate"
}

# Find container by workspace and optionally filter by image-tag label
# This is for advanced/debugging use when running multiple images per workspace.
# Normal use should use _cai_find_workspace_container for lookups (config → label → new name → legacy hash).
#
# Arguments:
#   $1 = workspace path (required)
#   $2 = docker context (optional, empty for default)
#   $3 = image-tag filter (optional, filters by containai.image-tag label)
#
# Returns: container name via stdout, or 1 if not found/error
# Note: Returns the first matching container if multiple match (deterministic via sort)
_cai_find_container() {
    local workspace_path="$1"
    local docker_context="${2:-}"
    local image_tag_filter="${3:-}"
    local container_name containers line

    if [[ -z "$workspace_path" ]]; then
        echo "[ERROR] workspace path is required" >&2
        return 1
    fi

    # Build docker command with optional context
    local -a docker_cmd=(docker)
    if [[ -n "$docker_context" ]]; then
        docker_cmd=(docker --context "$docker_context")
    fi

    # If no image-tag filter, just check if the container exists
    if [[ -z "$image_tag_filter" ]]; then
        if container_name=$(_cai_find_workspace_container "$workspace_path" "$docker_context"); then
            printf '%s' "$container_name"
            return 0
        fi
        return 1
    fi

    # With image-tag filter, search for containers with matching workspace AND image-tag labels
    # This supports advanced use cases where users want multiple images per workspace
    local filter_output
    filter_output=$("${docker_cmd[@]}" ps -a \
        --filter "label=containai.workspace=$workspace_path" \
        --filter "label=containai.image-tag=$image_tag_filter" \
        --format '{{.Names}}' 2>/dev/null | sort | head -1) || filter_output=""

    if [[ -n "$filter_output" ]]; then
        printf '%s' "$filter_output"
        return 0
    fi

    return 1
}

# FR-4: Validate container mounts match expected configuration
# Validates that workspace bind mount has correct source and data volume is correct
# Arguments:
#   $1 = docker context (empty string for default context)
#   $2 = container name
#   $3 = expected workspace path
#   $4 = expected data volume name
#   $5 = skip_volume_check (optional, "true" to skip volume name validation)
# Returns: 0 if valid, 1 if tainted (with error message)
_containai_validate_fr4_mounts() {
    local docker_context="$1"
    local container_name="$2"
    local expected_workspace="$3"
    local expected_volume="$4"
    local skip_volume_check="${5:-false}"

    # Build docker command with optional context
    local -a docker_cmd=(docker)
    if [[ -n "$docker_context" ]]; then
        docker_cmd=(docker --context "$docker_context")
    fi

    # Get mount info: Type|Source|Name|Destination per line
    # Source is host path (useful for bind mounts), Name is volume name (for volumes)
    local mount_info
    mount_info=$("${docker_cmd[@]}" inspect --format '{{range .Mounts}}{{.Type}}|{{.Source}}|{{.Name}}|{{.Destination}}{{"\n"}}{{end}}' "$container_name" 2>/dev/null) || mount_info=""

    local workspace_found=false
    local volume_found=false
    local mount_type mount_source mount_name mount_dest

    while IFS='|' read -r mount_type mount_source mount_name mount_dest; do
        [[ -z "$mount_dest" ]] && continue

        case "$mount_dest" in
            /home/agent/workspace)
                # Must be a bind mount with correct source
                if [[ "$mount_type" != "bind" ]]; then
                    echo "[ERROR] FR-4: Workspace mount is not a bind mount (type: $mount_type)" >&2
                    return 1
                fi
                if [[ "$mount_source" != "$expected_workspace" ]]; then
                    echo "[ERROR] FR-4: Workspace mount source mismatch" >&2
                    echo "  Expected: $expected_workspace" >&2
                    echo "  Actual:   $mount_source" >&2
                    return 1
                fi
                workspace_found=true
                ;;
            /mnt/agent-data)
                # Must be a named volume
                if [[ "$mount_type" != "volume" ]]; then
                    echo "[ERROR] FR-4: Data mount is not a named volume (type: $mount_type)" >&2
                    return 1
                fi
                # Check volume name (using .Name field, not .Source which is host path)
                # Skip if volume_mismatch_warn is enabled
                if [[ "$skip_volume_check" != "true" ]] && [[ "$mount_name" != "$expected_volume" ]]; then
                    echo "[ERROR] FR-4: Data volume name mismatch" >&2
                    echo "  Expected: $expected_volume" >&2
                    echo "  Actual:   $mount_name" >&2
                    return 1
                fi
                volume_found=true
                ;;
            /etc/hosts | /etc/hostname | /etc/resolv.conf)
                # Docker-managed, allowed
                ;;
            *)
                # Unexpected mount destination
                _cai_error "FR-4: Container has unexpected mount: $mount_dest"
                # Guidance messages use _cai_warn since they should always emit
                _cai_warn "Container may have been tainted by 'cai shell --volume'"
                _cai_warn "Use --fresh to recreate with clean mount configuration"
                return 1
                ;;
        esac
    done <<<"$mount_info"

    # Ensure both required mounts are present
    if [[ "$workspace_found" != "true" ]]; then
        echo "[ERROR] FR-4: Workspace mount not found" >&2
        return 1
    fi
    if [[ "$volume_found" != "true" ]]; then
        echo "[ERROR] FR-4: Data volume mount not found" >&2
        return 1
    fi

    return 0
}

# ==============================================================================
# Isolation detection
# ==============================================================================

# Validate that Docker's default MaskedPaths are applied (for use in tests)
# This uses mount metadata to verify paths are masked, NOT by expecting cat to fail.
# MaskedPaths are bind-mounted from /dev/null, so cat may succeed with empty output.
# Returns: 0 if MaskedPaths appear to be applied, 1 if not applied or cannot verify
#
# Usage (inside container):
#   if _containai_validate_masked_paths; then
#       echo "MaskedPaths are applied"
#   fi
#
# Note: This function must be run INSIDE a container to validate its security config.
# Running on the host will likely return 1 (not in container context).
_containai_validate_masked_paths() {
    # Check for /proc/kcore being masked via mount metadata
    # In a properly secured container, /proc/kcore should be bind-mounted from /dev/null
    # We verify by checking mount info rather than trying to read the file
    #
    # mountinfo format (space-separated fields):
    #   mount_id parent_id major:minor root mountpoint options ...
    # For masked paths, the mountpoint field will be exactly " /proc/kcore "
    # and the mount source will be /dev/null
    #
    # Use grep -F for fixed string matching to avoid regex interpretation
    if grep -qF ' /proc/kcore ' /proc/self/mountinfo 2>/dev/null; then
        return 0
    fi

    # Could not verify MaskedPaths are applied
    # This is expected when running on the host (not in a container)
    return 1
}

# Container isolation detection (conservative - prefer return 2 over false positive/negative)
# Checks docker info for Sysbox runtime, rootless mode, or user namespace remapping.
# Requires: Docker must be available (call _containai_check_docker first)
# Returns: 0=isolated (detected), 1=not isolated (definite), 2=unknown (ambiguous)
_containai_check_isolation() {
    local runtime rootless userns

    # If we are already inside a Sysbox system container, outer isolation exists.
    # Nested Sysbox is unsupported, so treat this as isolated for preflight.
    if _cai_is_sysbox_container; then
        return 0
    fi

    # Guard: check docker availability
    if ! command -v docker >/dev/null 2>&1; then
        _cai_warn "Unable to determine isolation status (docker not found)"
        return 2
    fi

    # Use docker info --format for reliable structured output with timeout
    # Use if ! pattern for set -e safety
    if ! runtime=$(_cai_timeout 5 docker info --format '{{.DefaultRuntime}}' 2>/dev/null); then
        _cai_warn "Unable to determine isolation status"
        return 2
    fi
    if [[ -z "$runtime" ]]; then
        _cai_warn "Unable to determine isolation status"
        return 2
    fi

    # These can fail without blocking (we only use them if available)
    # Use timeout to avoid hanging on slow/unhealthy daemons
    rootless=$(_cai_timeout 5 docker info --format '{{.Rootless}}' 2>/dev/null) || rootless=""
    userns=$(_cai_timeout 5 docker info --format '{{.SecurityOptions}}' 2>/dev/null) || userns=""

    # Sysbox runtime provides isolation
    if [[ "$runtime" == "sysbox-runc" ]]; then
        return 0
    fi

    # Rootless mode
    if [[ "$rootless" == "true" ]]; then
        return 0
    fi

    # User namespace remapping enabled
    if printf '%s' "$userns" | grep -q "userns"; then
        return 0
    fi

    # Standard runc without isolation features
    if [[ "$runtime" == "runc" ]]; then
        _cai_warn "No additional isolation detected (standard runtime)"
        return 1
    fi

    _cai_warn "Unable to determine isolation status"
    return 2
}

# ==============================================================================
# Preflight checks
# ==============================================================================

# Preflight checks for isolation before container start
# Arguments: $1 = force flag ("true" to skip checks)
# Returns: 0=proceed, 1=block
_containai_preflight_checks() {
    local force_flag="$1"
    local isolation_rc

    # Nested Sysbox is unsupported. When already inside a Sysbox container,
    # skip isolation checks silently and proceed with the default context.
    if _cai_is_sysbox_container; then
        return 0
    fi

    if [[ "$force_flag" == "true" ]]; then
        _cai_warn "Skipping isolation check (--force)"
        if [[ "${CONTAINAI_REQUIRE_ISOLATION:-0}" == "1" ]]; then
            _cai_warn "*** WARNING: Bypassing isolation requirement with --force"
            _cai_warn "*** Running without verified isolation may expose host system"
        fi
        return 0
    fi

    # Guard for set -e safety (non-zero is valid control flow)
    if _containai_check_isolation; then
        isolation_rc=0
    else
        isolation_rc=$?
    fi

    if [[ "${CONTAINAI_REQUIRE_ISOLATION:-0}" == "1" ]]; then
        case $isolation_rc in
            0) ;;
            1)
                echo "[ERROR] Container isolation required but not detected. Use --force to bypass." >&2
                return 1
                ;;
            2)
                echo "[ERROR] Cannot verify isolation status. Use --force to bypass." >&2
                return 1
                ;;
        esac
    fi

    return 0
}

# ==============================================================================
# Volume management
# ==============================================================================

# Ensure a volume exists, creating it if necessary
# Arguments: $1 = volume name, $2 = quiet flag (optional, default false), $3 = context (optional)
# Returns: 0 on success, 1 on failure
_containai_ensure_volumes() {
    local volume_name="$1"
    local quiet="${2:-false}"
    local context="${3:-}"

    if [[ -z "$volume_name" ]]; then
        echo "[ERROR] Volume name is required" >&2
        return 1
    fi

    # Validate volume name
    if ! _containai__validate_volume_name "$volume_name"; then
        echo "[ERROR] Invalid volume name: $volume_name" >&2
        echo "  Volume names must start with alphanumeric and contain only [a-zA-Z0-9_.-]" >&2
        return 1
    fi

    # Build context-aware docker command
    local -a docker_cmd=(docker)
    if [[ -n "$context" ]]; then
        docker_cmd=(docker --context "$context")
    fi

    if ! "${docker_cmd[@]}" volume inspect "$volume_name" >/dev/null 2>&1; then
        _cai_info "Creating volume: $volume_name"
        if ! "${docker_cmd[@]}" volume create "$volume_name" >/dev/null; then
            echo "[ERROR] Failed to create volume $volume_name" >&2
            return 1
        fi
    fi
    return 0
}

# ==============================================================================
# Container inspection helpers
# ==============================================================================

# Check if container exists
# Arguments: $1 = container name
# Returns: 0=exists, 1=does not exist, 2=docker error (daemon down, etc.)
_containai_container_exists() {
    local container_name="$1"
    local inspect_output

    # Use if ! pattern for set -e safety
    if inspect_output=$(docker inspect --type container --format '{{.Id}}' "$container_name" 2>&1); then
        return 0 # Container exists
    fi

    # Check if it's "no such" vs other errors
    if printf '%s' "$inspect_output" | grep -qiE "no such object|not found|error.*no such"; then
        return 1 # Container doesn't exist
    fi

    # Docker error (daemon down, permission, etc.)
    return 2
}

# Get label value for ContainAI container
# Arguments: $1 = container name
# Outputs to stdout: label value (may be empty)
# Returns: 0 on success, 1 on docker error
_containai_get_container_label() {
    local container_name="$1"
    local label_value

    # Use if ! pattern for set -e safety
    if ! label_value=$(docker inspect --format '{{ index .Config.Labels "containai.managed" }}' "$container_name" 2>/dev/null); then
        return 1
    fi
    # Normalize "<no value>" to empty
    if [[ "$label_value" == "<no value>" ]]; then
        label_value=""
    fi

    printf '%s' "$label_value"
    return 0
}

# Get the image name of a container (empty if not found or error)
_containai_get_container_image() {
    local container_name="$1"
    local image_name

    # Use if pattern for set -e safety
    if image_name=$(docker inspect --format '{{.Config.Image}}' "$container_name" 2>/dev/null); then
        printf '%s' "$image_name"
    else
        echo ""
    fi
}

# Get the data volume mounted at /mnt/agent-data from a container
# Returns: volume name or empty if not found
_containai_get_container_data_volume() {
    local container_name="$1"
    local volume_name

    # Use if pattern for set -e safety
    if volume_name=$(docker inspect --format '{{range .Mounts}}{{if eq .Destination "/mnt/agent-data"}}{{.Name}}{{end}}{{end}}' "$container_name" 2>/dev/null); then
        printf '%s' "$volume_name"
    else
        echo ""
    fi
}

# Check if an image name belongs to ContainAI (from our repo)
# Arguments: $1 = image name
# Returns: 0=ours, 1=not ours
_containai_is_our_image() {
    local image_name="$1"
    # Check if image starts with our repo prefix
    [[ "$image_name" == "${_CONTAINAI_DEFAULT_REPO}:"* ]]
}

# Verify container was created by ContainAI (has our label or uses our image)
# Returns: 0=ours (label or image matches), 1=foreign (no match), 2=docker error
_containai_is_our_container() {
    local container_name="$1"
    local exists_rc label_value image_name

    # Guard for set -e safety (non-zero is valid control flow)
    if _containai_container_exists "$container_name"; then
        exists_rc=0
    else
        exists_rc=$?
    fi
    if [[ $exists_rc -eq 1 ]]; then
        return 1 # Doesn't exist = not ours
    elif [[ $exists_rc -eq 2 ]]; then
        return 2 # Docker error
    fi

    # Get label value - use if ! pattern for set -e safety
    if ! label_value=$(_containai_get_container_label "$container_name"); then
        return 2 # Docker error
    fi

    # Check label
    if [[ "$label_value" == "true" ]]; then
        return 0
    fi

    # Fallback: check image (for containers without label)
    if [[ -z "$label_value" ]]; then
        image_name="$(_containai_get_container_image "$container_name")"
        if _containai_is_our_image "$image_name"; then
            return 0
        fi
    fi

    return 1
}

# Check container ownership with appropriate messaging
# Returns: 0=owned, 1=foreign (with error), 2=does not exist, 3=docker error
_containai_check_container_ownership() {
    local container_name="$1"
    local exists_rc is_ours_rc label_value actual_image

    # Guard for set -e safety (non-zero is valid control flow)
    if _containai_container_exists "$container_name"; then
        exists_rc=0
    else
        exists_rc=$?
    fi
    if [[ $exists_rc -eq 1 ]]; then
        return 2 # Container doesn't exist
    elif [[ $exists_rc -eq 2 ]]; then
        echo "[ERROR] Cannot check container ownership - Docker error" >&2
        return 3
    fi

    # Guard for set -e safety (non-zero is valid control flow)
    if _containai_is_our_container "$container_name"; then
        is_ours_rc=0
    else
        is_ours_rc=$?
    fi
    if [[ $is_ours_rc -eq 0 ]]; then
        return 0
    elif [[ $is_ours_rc -eq 2 ]]; then
        echo "[ERROR] Cannot check container ownership - Docker error" >&2
        return 3
    fi

    # Foreign container - show detailed info (use || true for set -e safety on info gathering)
    label_value=$(_containai_get_container_label "$container_name") || label_value=""
    actual_image="$(_containai_get_container_image "$container_name")"

    echo "[ERROR] Container '$container_name' exists but was not created by ContainAI" >&2
    echo "" >&2
    echo "  Expected label 'containai.managed': true" >&2
    echo "  Actual label 'containai.managed':   ${label_value:-<not set>}" >&2
    echo "  Expected image prefix:              ${_CONTAINAI_DEFAULT_REPO}:" >&2
    echo "  Actual image:                       ${actual_image:-<unknown>}" >&2
    echo "" >&2
    echo "This is a name collision with a container not managed by ContainAI." >&2
    echo "To recreate as a ContainAI-managed sandbox container, run: cai --restart" >&2
    echo "" >&2
    return 1
}

# Check if container's image matches the resolved image for the requested agent
# Arguments: $1 = container name, $2 = resolved image name, $3 = quiet flag
# Returns: 0 if match, 1 if mismatch (with warning)
_containai_check_image_match() {
    local container_name="$1"
    local resolved_image="$2"
    local quiet_flag="$3"
    local actual_image

    actual_image="$(_containai_get_container_image "$container_name")"

    if [[ -z "$actual_image" ]]; then
        # Can't determine image - allow proceeding
        return 0
    fi

    if [[ "$actual_image" != "$resolved_image" ]]; then
        # Warnings always emit regardless of quiet flag
        _cai_warn "Image mismatch for container '$container_name'"
        printf '\n' >&2
        _cai_warn "  Container image: $actual_image"
        _cai_warn "  Requested image: $resolved_image"
        printf '\n' >&2
        _cai_warn "The container was created with a different agent/image."
        _cai_warn "To use the requested agent, recreate the container:"
        _cai_warn "  cai --restart"
        _cai_warn "Or specify a different container name:"
        _cai_warn "  cai run --container <unique-name>"
        printf '\n' >&2
        return 1
    fi

    return 0
}

# Check if container's mounted volume matches the desired volume
# Arguments: $1 = container name, $2 = desired volume name, $3 = quiet flag
# Returns: 0 if match or no mount found, 1 if mismatch (with warning)
_containai_check_volume_match() {
    local container_name="$1"
    local desired_volume="$2"
    local quiet_flag="$3"
    local mounted_volume

    mounted_volume=$(_containai_get_container_data_volume "$container_name")

    if [[ -z "$mounted_volume" ]]; then
        return 0
    fi

    if [[ "$mounted_volume" != "$desired_volume" ]]; then
        # Warnings always emit regardless of quiet flag
        _cai_warn "Volume mismatch for container '$container_name'"
        printf '\n' >&2
        _cai_warn "  Container uses volume: $mounted_volume"
        _cai_warn "  Workspace expects:     $desired_volume"
        printf '\n' >&2
        _cai_warn "The container was created with a different workspace/config."
        _cai_warn "To use the correct volume, recreate the container:"
        _cai_warn "  cai --restart"
        _cai_warn "Or specify a different container name:"
        _cai_warn "  cai run --container <unique-name>"
        printf '\n' >&2
        return 1
    fi

    return 0
}

# ==============================================================================
# Start container
# ==============================================================================

# Start or attach to a ContainAI sandbox container
# This is the core container operation function
# Arguments:
#   --name <name>        Container name (default: auto-generated)
#   --workspace <path>   Workspace path (default: $PWD)
#   --data-volume <vol>  Data volume name (required)
#   --credentials <mode> Credential mode (none; default: none)
#   --volume-mismatch-warn  Warn on volume mismatch instead of blocking (for implicit volumes)
#   --fresh              Remove and recreate container (preserves data volume)
#   --restart            Alias for --fresh (legacy)
#   --force              Skip preflight checks
#   --detached           Run detached
#   --shell              Start with shell instead of agent
#   --quiet              Suppress verbose output
#   --verbose            Show container/volume names (stderr, for script-friendliness)
#   --debug              Enable debug logging
#   --image-tag <tag>    Image tag for container (advanced/debugging, stored as label)
#   --template <name>    Template name for container build (default: "default")
#   -e, --env <VAR=val>  Environment variable (repeatable, passed to command via SSH)
#   -v, --volume <spec>  Extra volume mount (repeatable)
#   -- <cmd>             Command to run (default: agent); e.g., -- bash runs bash
# Returns: 0 on success, 1 on failure
_containai_start_container() {
    local container_name=""
    local workspace=""
    local data_volume=""
    local explicit_config=""
    local explicit_context=""  # Override context selection (use when container already exists in known context)
    local image_tag=""
    local cli_template=""  # Template name from --template flag
    local credentials="$_CONTAINAI_DEFAULT_CREDENTIALS"
    local acknowledge_credential_risk=false
    local allow_host_credentials=false
    local ack_host_credentials=false
    local allow_host_docker_socket=false
    local ack_host_docker_socket=false
    local volume_mismatch_warn=false
    local restart_flag=false
    local fresh_flag=false
    local force_flag=false
    local detached_flag=false
    local shell_flag=false
    local quiet_flag=false
    local verbose_flag=false
    local debug_flag=false
    local dry_run_flag=false
    local mount_docker_socket=false
    local please_root_my_host=false
    local -a env_vars=()
    local -a extra_volumes=()
    local -a agent_args=()
    local arg

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --)
                shift
                agent_args=("$@")
                break
                ;;
            --name)
                if [[ -z "${2-}" ]]; then
                    echo "[ERROR] --name requires a value" >&2
                    return 1
                fi
                container_name="$2"
                shift 2
                ;;
            --name=*)
                container_name="${1#--name=}"
                shift
                ;;
            --workspace | -w)
                if [[ -z "${2-}" ]]; then
                    echo "[ERROR] --workspace requires a value" >&2
                    return 1
                fi
                workspace="$2"
                workspace="${workspace/#\~/$HOME}"
                shift 2
                ;;
            --workspace=*)
                workspace="${1#--workspace=}"
                workspace="${workspace/#\~/$HOME}"
                shift
                ;;
            -w*)
                workspace="${1#-w}"
                workspace="${workspace/#\~/$HOME}"
                shift
                ;;
            --data-volume)
                if [[ -z "${2-}" ]]; then
                    echo "[ERROR] --data-volume requires a value" >&2
                    return 1
                fi
                data_volume="$2"
                shift 2
                ;;
            --data-volume=*)
                data_volume="${1#--data-volume=}"
                shift
                ;;
            --config)
                if [[ -z "${2-}" ]]; then
                    echo "[ERROR] --config requires a value" >&2
                    return 1
                fi
                explicit_config="$2"
                shift 2
                ;;
            --config=*)
                explicit_config="${1#--config=}"
                if [[ -z "$explicit_config" ]]; then
                    echo "[ERROR] --config requires a value" >&2
                    return 1
                fi
                shift
                ;;
            --docker-context)
                if [[ -z "${2-}" ]]; then
                    echo "[ERROR] --docker-context requires a value" >&2
                    return 1
                fi
                explicit_context="$2"
                shift 2
                ;;
            --docker-context=*)
                explicit_context="${1#--docker-context=}"
                if [[ -z "$explicit_context" ]]; then
                    echo "[ERROR] --docker-context requires a value" >&2
                    return 1
                fi
                shift
                ;;
            --credentials)
                if [[ -z "${2-}" ]]; then
                    echo "[ERROR] --credentials requires a value" >&2
                    return 1
                fi
                credentials="$2"
                shift 2
                ;;
            --credentials=*)
                credentials="${1#--credentials=}"
                if [[ -z "$credentials" ]]; then
                    echo "[ERROR] --credentials requires a value" >&2
                    return 1
                fi
                shift
                ;;
            --acknowledge-credential-risk)
                acknowledge_credential_risk=true
                shift
                ;;
            --volume-mismatch-warn)
                volume_mismatch_warn=true
                shift
                ;;
            --restart)
                restart_flag=true
                shift
                ;;
            --fresh)
                fresh_flag=true
                shift
                ;;
            --force)
                force_flag=true
                shift
                ;;
            --detached | -d)
                detached_flag=true
                shift
                ;;
            --shell)
                shell_flag=true
                shift
                ;;
            --quiet | -q)
                quiet_flag=true
                _cai_set_quiet
                shift
                ;;
            --verbose)
                verbose_flag=true
                _cai_set_verbose
                shift
                ;;
            --debug | -D)
                debug_flag=true
                shift
                ;;
            --dry-run)
                dry_run_flag=true
                shift
                ;;
            --image-tag)
                if [[ -z "${2-}" ]]; then
                    echo "[ERROR] --image-tag requires a value" >&2
                    return 1
                fi
                image_tag="$2"
                shift 2
                ;;
            --image-tag=*)
                image_tag="${1#--image-tag=}"
                if [[ -z "$image_tag" ]]; then
                    echo "[ERROR] --image-tag requires a value" >&2
                    return 1
                fi
                shift
                ;;
            --template)
                if [[ -z "${2-}" ]]; then
                    echo "[ERROR] --template requires a value" >&2
                    return 1
                fi
                cli_template="$2"
                shift 2
                ;;
            --template=*)
                cli_template="${1#--template=}"
                if [[ -z "$cli_template" ]]; then
                    echo "[ERROR] --template requires a value" >&2
                    return 1
                fi
                shift
                ;;
            --mount-docker-socket)
                mount_docker_socket=true
                shift
                ;;
            --please-root-my-host)
                please_root_my_host=true
                shift
                ;;
            --allow-host-credentials)
                allow_host_credentials=true
                shift
                ;;
            --i-understand-this-exposes-host-credentials)
                ack_host_credentials=true
                shift
                ;;
            --allow-host-docker-socket)
                allow_host_docker_socket=true
                shift
                ;;
            --i-understand-this-grants-root-access)
                ack_host_docker_socket=true
                shift
                ;;
            --env | -e)
                if [[ -z "${2-}" ]]; then
                    echo "[ERROR] --env requires a value" >&2
                    return 1
                fi
                env_vars+=("$2")
                shift 2
                ;;
            --env=*)
                env_vars+=("${1#--env=}")
                shift
                ;;
            -e*)
                env_vars+=("${1#-e}")
                shift
                ;;
            --volume | -v)
                if [[ -z "${2-}" ]]; then
                    echo "[ERROR] --volume requires a value" >&2
                    return 1
                fi
                extra_volumes+=("$2")
                shift 2
                ;;
            --volume=*)
                extra_volumes+=("${1#--volume=}")
                shift
                ;;
            -v*)
                extra_volumes+=("${1#-v}")
                shift
                ;;
            *)
                echo "[ERROR] Unknown option: $1" >&2
                return 1
                ;;
        esac
    done

    # Validate required arguments
    if [[ -z "$data_volume" ]]; then
        echo "[ERROR] --data-volume is required" >&2
        return 1
    fi

    # Reject legacy options that are no longer supported
    if [[ "$allow_host_credentials" == "true" ]] || [[ "$credentials" == "host" ]]; then
        echo "" >&2
        echo "[ERROR] --credentials=host and --allow-host-credentials are no longer supported" >&2
        echo "" >&2
        echo "Host credential sharing is not available with Sysbox isolation." >&2
        echo "" >&2
        echo "For credential access inside containers, use 'cai import' to copy credentials." >&2
        echo "" >&2
        return 1
    fi

    if [[ "$allow_host_docker_socket" == "true" ]] || [[ "$mount_docker_socket" == "true" ]]; then
        echo "" >&2
        echo "[ERROR] --mount-docker-socket and --allow-host-docker-socket are no longer supported" >&2
        echo "" >&2
        echo "Docker socket mounting is not available with Sysbox isolation." >&2
        echo "" >&2
        echo "Sysbox containers have Docker-in-Docker capability built in." >&2
        echo "Use the inner Docker daemon instead of mounting the host socket." >&2
        echo "" >&2
        return 1
    fi

    # First-use detection: ensure default templates are installed
    # This enables template customization (fn-33-lp4) even if user skipped `cai setup`
    if ! _cai_ensure_default_templates "$dry_run_flag"; then
        _cai_debug "Some default templates could not be installed (continuing)"
    fi

    # Template name for container creation
    # Precedence: --template > default
    # When --image-tag is specified without --template, skip template build (advanced/debugging mode)
    local template_name="default"
    local use_template="true"

    # Apply --template if specified
    if [[ -n "$cli_template" ]]; then
        # Validate template name
        if ! _cai_validate_template_name "$cli_template"; then
            _cai_error "Invalid template name: $cli_template"
            _cai_warn "Template names must be lowercase alphanumeric with dashes/underscores/dots"
            return 1
        fi
        template_name="$cli_template"
        # If both --template and --image-tag specified, warn that --image-tag is ignored
        if [[ -n "$image_tag" ]]; then
            _cai_warn "--image-tag is ignored when --template is specified"
        fi
    elif [[ -n "$image_tag" ]]; then
        # Advanced mode: explicit image tag bypasses template build (no --template specified)
        use_template="false"
    fi

    # Resolve image: use --image-tag if provided (advanced/debugging), else default
    # Note: For new containers, template build happens later (after context selection)
    # to use the same Docker context as container creation
    # When use_template=true (either default or --template), image_tag is ignored for image selection
    local resolved_image
    if [[ -n "$image_tag" && "$use_template" != "true" ]]; then
        # Advanced mode: explicit image tag for debugging or multi-image workflows
        # Only used when template is NOT being built
        resolved_image="${_CONTAINAI_DEFAULT_REPO}:${image_tag}"
    else
        # Default: one container per workspace with default agent image
        # Will be overridden by template build for new containers
        resolved_image="${_CONTAINAI_DEFAULT_REPO}:${_CONTAINAI_AGENT_TAGS[$_CONTAINAI_DEFAULT_AGENT]}"
    fi

    # Early docker check
    if ! command -v docker >/dev/null 2>&1; then
        echo "[ERROR] Docker is not installed or not in PATH" >&2
        return 1
    fi

    # Resolve workspace using platform-aware normalization
    local workspace_resolved workspace_input
    workspace_input="${workspace:-$PWD}"
    workspace_resolved=$(_cai_normalize_path "$workspace_input")
    # Check if path exists (normalize_path returns as-is for non-existent paths)
    if [[ ! -d "$workspace_resolved" ]]; then
        echo "[ERROR] Workspace path does not exist: $workspace_input" >&2
        return 1
    fi

    # === CONFIG PARSING (must happen early to populate globals) ===
    # Parse config file to populate global settings including:
    # - _CAI_SECURE_ENGINE_CONTEXT (for context selection)
    # - _CAI_CONTAINER_MEMORY, _CAI_CONTAINER_CPUS (for resource limits)
    # Note: We parse directly here to preserve globals (subshell would lose them)
    local config_file=""
    if [[ -n "$explicit_config" ]]; then
        if [[ ! -f "$explicit_config" ]]; then
            echo "[ERROR] Config file not found: $explicit_config" >&2
            return 1
        fi
        config_file="$explicit_config"
        if ! _containai_parse_config "$config_file" "$workspace_resolved" "strict"; then
            echo "[ERROR] Failed to parse config: $explicit_config" >&2
            return 1
        fi
    else
        # Discovered config: suppress errors gracefully
        config_file=$(_containai_find_config "$workspace_resolved")
        if [[ -n "$config_file" ]]; then
            _containai_parse_config "$config_file" "$workspace_resolved" 2>/dev/null || true
        fi
    fi
    local config_context_override="${_CAI_SECURE_ENGINE_CONTEXT:-}"

    # Select Docker context
    # If explicit_context is provided (e.g., from --container finding an existing container),
    # validate Sysbox availability; otherwise auto-select based on isolation availability
    local selected_context=""
    if [[ -n "$explicit_context" ]]; then
        # Use the explicitly provided context (container was found in this context)
        # Validate the context exists and has Sysbox isolation
        if ! docker context inspect -- "$explicit_context" >/dev/null 2>&1; then
            _cai_error "Docker context not found: $explicit_context"
            _cai_warn "Run 'docker context ls' to see available contexts"
            return 1
        fi
        # Validate Sysbox availability for the explicit context (security requirement)
        if ! _cai_sysbox_available_for_context "$explicit_context"; then
            if [[ "$force_flag" == "true" ]]; then
                _cai_warn "Context '$explicit_context' does not have Sysbox isolation available."
                _cai_warn "Proceeding with --force; container may lack proper isolation."
            else
                _cai_error "Context '$explicit_context' does not have Sysbox isolation available."
                _cai_warn "Use --force to bypass isolation check, or recreate container with --fresh in an isolated context."
                _cai_warn "Run 'cai doctor' for setup instructions."
                return 1
            fi
        fi
        selected_context="$explicit_context"
    else
        # Auto-select context based on isolation availability
        local debug_mode=""
        if [[ "$debug_flag" == "true" ]]; then
            debug_mode="debug"
        fi
        local verbose_str="false"
        if [[ "$verbose_flag" == "true" ]]; then
            verbose_str="true"
        fi
        if ! selected_context=$(_cai_select_context "$config_context_override" "$debug_mode" "$verbose_str"); then
            if [[ "$force_flag" == "true" ]]; then
                _cai_warn "Sysbox context check failed; attempting to use an existing context without validation."
                _cai_warn "Container creation will still require sysbox-runc runtime."
                if [[ -n "$config_context_override" ]] && docker context inspect "$config_context_override" >/dev/null 2>&1; then
                    selected_context="$config_context_override"
                elif _cai_containai_docker_context_exists; then
                    selected_context="$_CAI_CONTAINAI_DOCKER_CONTEXT"
                else
                    _cai_error "No isolation context available. Run 'cai setup' to create $_CAI_CONTAINAI_DOCKER_CONTEXT."
                    return 1
                fi
            else
                _cai_error "No isolation available. Run 'cai doctor' for setup instructions."
                _cai_error "Use --force to bypass context selection (Sysbox runtime still required)"
                return 1
            fi
        fi
    fi

    # Build docker command prefix based on context
    # Context should have Sysbox mode (validated above, unless --force bypassed)
    local -a docker_cmd=(docker)
    if [[ -n "$selected_context" ]]; then
        docker_cmd=(docker --context "$selected_context")
    fi

    # Get container name using shared resolution helper
    # Uses _cai_resolve_container_name for duplicate-aware naming
    if [[ -z "$container_name" ]]; then
        if ! container_name=$(_cai_resolve_container_name "$workspace_resolved" "$selected_context"); then
            echo "[ERROR] Failed to resolve container name for workspace: $workspace_resolved" >&2
            return 1
        fi
    fi

    # Handle --dry-run flag: show what would happen without executing
    if [[ "$dry_run_flag" == "true" ]]; then
        # Check if container already exists (use --type container to avoid matching images)
        local dry_run_state="none"
        local dry_run_ssh_port=""
        if "${docker_cmd[@]}" inspect --type container -- "$container_name" >/dev/null 2>&1; then
            dry_run_state=$("${docker_cmd[@]}" inspect --type container --format '{{.State.Status}}' -- "$container_name" 2>/dev/null) || dry_run_state="unknown"
            dry_run_ssh_port=$(_cai_get_container_ssh_port "$container_name" "$selected_context") || dry_run_ssh_port=""
        fi

        # Output in machine-parseable format (key=value, one per line)
        echo "CONTAINER_NAME=$container_name"
        echo "CONTAINER_STATE=$dry_run_state"
        echo "WORKSPACE=$workspace_resolved"
        echo "DATA_VOLUME=$data_volume"
        echo "IMAGE=$resolved_image"
        if [[ -n "$selected_context" ]]; then
            echo "DOCKER_CONTEXT=$selected_context"
        else
            echo "DOCKER_CONTEXT=default"
        fi

        # Template information
        if [[ "$use_template" == "true" ]]; then
            echo "TEMPLATE_NAME=$template_name"

            # Template mismatch check for existing containers
            if [[ "$dry_run_state" != "none" ]]; then
                local dry_run_template
                dry_run_template=$("${docker_cmd[@]}" inspect --format '{{with index .Config.Labels "ai.containai.template"}}{{.}}{{end}}' -- "$container_name" 2>/dev/null) || dry_run_template=""
                if [[ -n "$dry_run_template" ]]; then
                    echo "CONTAINER_TEMPLATE=$dry_run_template"
                else
                    echo "CONTAINER_TEMPLATE=<none - pre-existing container>"
                fi

                if [[ -z "$dry_run_template" && "$template_name" != "default" ]]; then
                    echo "TEMPLATE_MISMATCH=pre-existing container requires --fresh"
                elif [[ -n "$dry_run_template" && "$dry_run_template" != "$template_name" ]]; then
                    echo "TEMPLATE_MISMATCH=container has template '$dry_run_template', use --fresh to rebuild"
                fi
            fi

            # Template build command (for new containers or --fresh/--restart)
            if [[ "$dry_run_state" == "none" || "$fresh_flag" == "true" || "$restart_flag" == "true" ]]; then
                # Output the build command using _cai_build_template dry-run mode
                _cai_build_template "$template_name" "$selected_context" "true" 2>/dev/null || {
                    echo "TEMPLATE_BUILD_ERROR=Failed to generate build command"
                }
            fi
        fi

        # Port allocation
        # For existing containers (not being recreated), use the allocated port
        # For new containers or --fresh/--restart, compute what port would be allocated
        local candidate_port=""
        if [[ -n "$dry_run_ssh_port" && "$fresh_flag" != "true" && "$restart_flag" != "true" ]]; then
            # Existing container, not being recreated
            # Check for port conflict (mirrors real code behavior for stopped containers)
            local port_conflict=false
            local port_check_failed=false
            if [[ "$dry_run_state" == "exited" || "$dry_run_state" == "created" ]]; then
                local port_avail_rc
                if _cai_is_port_available "$dry_run_ssh_port" 2>/dev/null; then
                    port_avail_rc=0
                else
                    port_avail_rc=$?
                fi
                # rc=1 means port is in use by another process
                # rc=2 means we can't check (ss failed) - real execution would abort
                if [[ $port_avail_rc -eq 1 ]]; then
                    port_conflict=true
                elif [[ $port_avail_rc -eq 2 ]]; then
                    port_check_failed=true
                fi
            fi

            if [[ "$port_check_failed" == "true" ]]; then
                # Cannot verify port availability - real execution would fail
                echo "SSH_PORT=<unknown - cannot verify port availability>"
                echo "SSH_PORT_CHECK_ERROR=ss command failed"
            elif [[ "$port_conflict" == "true" ]]; then
                # Port conflict - container would be auto-recreated with new port
                echo "SSH_PORT_CONFLICT=$dry_run_ssh_port"
                if candidate_port=$(_cai_find_available_port "" "" "$selected_context" "$dry_run_ssh_port" 2>/dev/null); then
                    echo "SSH_PORT=$candidate_port"
                else
                    echo "SSH_PORT=<allocation failed - no ports available>"
                fi
            else
                # No conflict - use current port
                echo "SSH_PORT=$dry_run_ssh_port"
                candidate_port="$dry_run_ssh_port"
            fi
        elif [[ -n "$dry_run_ssh_port" && ("$fresh_flag" == "true" || "$restart_flag" == "true") ]]; then
            # Container exists but will be recreated with --fresh/--restart
            # Compute port using same algorithm as creation, ignoring current container's port
            # (since it will be removed before new allocation)
            # Use force_ignore=true only for running containers (port is actively in use by us)
            # For stopped containers, don't force ignore - another process may have taken the port
            local force_ignore_port=""
            if [[ "$dry_run_state" == "running" ]]; then
                force_ignore_port="true"
            fi
            if candidate_port=$(_cai_find_available_port "" "" "$selected_context" "$dry_run_ssh_port" "$force_ignore_port" 2>/dev/null); then
                echo "SSH_PORT=$candidate_port"
            else
                echo "SSH_PORT=<allocation failed - no ports available>"
            fi
        else
            # New container - compute candidate port
            if candidate_port=$(_cai_find_available_port "" "" "$selected_context" 2>/dev/null); then
                echo "SSH_PORT=$candidate_port"
            else
                echo "SSH_PORT=<allocation failed - no ports available>"
            fi
        fi

        # Mount details
        echo "MOUNT_WORKSPACE=$workspace_resolved:/home/agent/workspace"
        echo "MOUNT_DATA=$data_volume:/mnt/agent-data"

        # Extra volumes that would be mounted (if any)
        if [[ ${#extra_volumes[@]} -gt 0 ]]; then
            local vol_idx=0
            for vol in "${extra_volumes[@]}"; do
                echo "MOUNT_EXTRA_$vol_idx=$vol"
                vol_idx=$((vol_idx + 1))
            done
        fi

        # Connection details - use container name (works via SSH config)
        echo "SSH_COMMAND=ssh $container_name"
        echo "SSH_CONFIG_HOST=$container_name"
        # Direct SSH command with port - always use candidate_port when available
        # (candidate_port reflects the actual port that would be used after any conflict resolution)
        if [[ -n "${candidate_port:-}" ]]; then
            echo "SSH_COMMAND_DIRECT=ssh -p $candidate_port agent@localhost"
        fi

        # What action would be taken
        case "$dry_run_state" in
            running)
                echo "ACTION=attach"
                echo "ACTION_DETAIL=Would attach to running container via SSH"
                ;;
            exited | created)
                echo "ACTION=start"
                echo "ACTION_DETAIL=Would start stopped container and attach via SSH"
                ;;
            none)
                echo "ACTION=create"
                echo "ACTION_DETAIL=Would create new container and attach via SSH"
                ;;
            *)
                echo "ACTION=unknown"
                echo "ACTION_DETAIL=Container in unexpected state: $dry_run_state"
                ;;
        esac

        # Fresh/restart flag effect
        if [[ "$fresh_flag" == "true" || "$restart_flag" == "true" ]]; then
            if [[ "$dry_run_state" != "none" ]]; then
                echo "FRESH_FLAG=true"
                echo "FRESH_ACTION=Would remove existing container and recreate"
            fi
        fi

        # Shell vs run mode
        if [[ "$shell_flag" == "true" ]]; then
            echo "MODE=shell"
        else
            echo "MODE=run"
            if [[ ${#agent_args[@]} -gt 0 ]]; then
                echo "COMMAND=${agent_args[*]}"
            else
                echo "COMMAND=$_CONTAINAI_DEFAULT_AGENT"
            fi
        fi

        # Environment variables that would be passed
        if [[ ${#env_vars[@]} -gt 0 ]]; then
            local env_idx=0
            for env_var in "${env_vars[@]}"; do
                echo "ENV_VAR_$env_idx=$env_var"
                env_idx=$((env_idx + 1))
            done
        fi

        return 0
    fi

    # Check container state - guard for set -e safety (non-zero is valid control flow)
    # Use context-aware docker command for container inspection
    local container_state exists_rc
    if "${docker_cmd[@]}" inspect "$container_name" >/dev/null 2>&1; then
        exists_rc=0
    else
        exists_rc=1
    fi

    if [[ $exists_rc -eq 0 ]]; then
        # Use || true for set -e safety (success already confirmed by exists check)
        container_state=$("${docker_cmd[@]}" inspect --format '{{.State.Status}}' "$container_name" 2>/dev/null) || container_state=""
    else
        container_state="none"
    fi

    # Template mismatch check for existing containers
    # Skip if --fresh/--restart will rebuild anyway (they will recreate with the requested template)
    # Check if --template is specified (or use_template=true) and container exists
    if [[ "$container_state" != "none" && "$use_template" == "true" && "$fresh_flag" != "true" && "$restart_flag" != "true" ]]; then
        # Get container's template label (using with...end to get empty string for missing labels)
        local container_template
        container_template=$("${docker_cmd[@]}" inspect --format '{{with index .Config.Labels "ai.containai.template"}}{{.}}{{end}}' -- "$container_name" 2>/dev/null) || container_template=""

        if [[ -z "$container_template" ]]; then
            # Missing label = pre-existing container (created before templates feature)
            # Allow if template is "default", otherwise error
            if [[ "$template_name" != "default" ]]; then
                _cai_error "Container was created before templates. Use --fresh to rebuild with template."
                _cai_warn "Container: $container_name"
                _cai_warn "Requested template: $template_name"
                return 1
            fi
            # Default template on pre-existing container - allow (fallthrough)
        elif [[ "$container_template" != "$template_name" ]]; then
            # Label mismatch - error with guidance
            _cai_error "Container exists with template '$container_template'. Use --fresh to rebuild."
            _cai_warn "Container: $container_name"
            _cai_warn "Requested template: $template_name"
            _cai_warn "Existing template: $container_template"
            return 1
        fi
        # Template matches - continue normally
    fi

    # Check for SSH port conflict on stopped containers and auto-recreate if needed
    # This handles the case where the allocated port is now in use by another process
    if [[ "$container_state" == "exited" || "$container_state" == "created" ]]; then
        local existing_ssh_port port_check_rc
        if existing_ssh_port=$(_cai_get_container_ssh_port "$container_name" "$selected_context"); then
            # Capture return code safely (set -e safe)
            if _cai_is_port_available "$existing_ssh_port"; then
                port_check_rc=0
            else
                port_check_rc=$?
            fi
            if [[ $port_check_rc -eq 2 ]]; then
                # ss command failed - cannot determine port availability, abort without deleting
                echo "[ERROR] Cannot verify SSH port availability (ss command failed)" >&2
                echo "[ERROR] Ensure 'ss' (iproute2) is installed" >&2
                return 1
            elif [[ $port_check_rc -eq 1 ]]; then
                # Port is in use by another process - need to recreate with new port
                # First verify this is a ContainAI-managed container before deleting
                local port_conflict_label port_conflict_image
                port_conflict_label=$("${docker_cmd[@]}" inspect --format '{{index .Config.Labels "containai.managed"}}' "$container_name" 2>/dev/null) || port_conflict_label=""
                if [[ "$port_conflict_label" != "true" ]]; then
                    # Check image fallback for legacy containers
                    port_conflict_image=$("${docker_cmd[@]}" inspect --format '{{.Config.Image}}' "$container_name" 2>/dev/null) || port_conflict_image=""
                    if ! _containai_is_our_image "$port_conflict_image"; then
                        echo "[ERROR] Cannot recreate container - '$container_name' was not created by ContainAI" >&2
                        echo "[ERROR] SSH port $existing_ssh_port is in use. Remove the container manually or use a different name." >&2
                        return 1
                    fi
                fi
                # Warnings always emit regardless of quiet flag
                _cai_warn "SSH port $existing_ssh_port is in use by another process"
                _cai_info "Recreating container with new port allocation..."
                # Remove the old container first (like --fresh but automatic)
                if ! "${docker_cmd[@]}" rm -f "$container_name" >/dev/null 2>&1; then
                    echo "[ERROR] Failed to remove container for port reallocation" >&2
                    return 1
                fi
                # Clean up SSH configuration after successful container removal
                _cai_cleanup_container_ssh "$container_name" "$existing_ssh_port"
                container_state="none"
            fi
            # port_check_rc == 0 means port is available, continue normally
        fi
    fi

    # Handle --fresh flag (removes and recreates container, preserves data volume)
    # --fresh is equivalent to --restart but with clearer semantics for the new lifecycle model
    if [[ "$fresh_flag" == "true" && "$container_state" != "none" ]]; then
        # Check if container belongs to ContainAI using context-aware inspection (label or image fallback)
        local fresh_label_val fresh_image_fallback
        fresh_label_val=$("${docker_cmd[@]}" inspect --format '{{index .Config.Labels "containai.managed"}}' "$container_name" 2>/dev/null) || fresh_label_val=""
        if [[ "$fresh_label_val" != "true" ]]; then
            # Fallback: check if image is from our repo (for legacy containers without label)
            fresh_image_fallback=$("${docker_cmd[@]}" inspect --format '{{.Config.Image}}' "$container_name" 2>/dev/null) || fresh_image_fallback=""
            if ! _containai_is_our_image "$fresh_image_fallback"; then
                echo "[ERROR] Cannot use --fresh - container '$container_name' was not created by ContainAI" >&2
                echo "Remove the conflicting container manually if needed: docker rm -f '$container_name'" >&2
                return 1
            fi
        fi
        _cai_info "Removing existing container (--fresh)..."
        # Get SSH port before removal for cleanup
        local fresh_ssh_port
        fresh_ssh_port=$(_cai_get_container_ssh_port "$container_name" "$selected_context") || fresh_ssh_port=""
        # Stop container, ignoring "not running" errors but surfacing others
        local fresh_stop_output
        fresh_stop_output="$("${docker_cmd[@]}" stop "$container_name" 2>&1)" || {
            if ! printf '%s' "$fresh_stop_output" | grep -qiE "is not running"; then
                echo "$fresh_stop_output" >&2
            fi
        }
        # Remove container, ignoring "not found" errors but surfacing others
        local fresh_rm_output
        fresh_rm_output="$("${docker_cmd[@]}" rm "$container_name" 2>&1)" || {
            if ! printf '%s' "$fresh_rm_output" | grep -qiE "no such container|not found"; then
                echo "$fresh_rm_output" >&2
                return 1
            fi
        }
        # Clean up SSH configuration after successful container removal
        if [[ -n "$fresh_ssh_port" ]]; then
            _cai_cleanup_container_ssh "$container_name" "$fresh_ssh_port"
        fi
        container_state="none"
    fi

    # Handle --restart flag (legacy, same behavior as --fresh)
    if [[ "$restart_flag" == "true" && "$container_state" != "none" ]]; then
        # Check if container belongs to ContainAI using context-aware inspection (label or image fallback)
        local label_val restart_image_fallback
        label_val=$("${docker_cmd[@]}" inspect --format '{{index .Config.Labels "containai.managed"}}' "$container_name" 2>/dev/null) || label_val=""
        if [[ "$label_val" != "true" ]]; then
            # Fallback: check if image is from our repo (for legacy containers without label)
            restart_image_fallback=$("${docker_cmd[@]}" inspect --format '{{.Config.Image}}' "$container_name" 2>/dev/null) || restart_image_fallback=""
            if ! _containai_is_our_image "$restart_image_fallback"; then
                echo "[ERROR] Cannot restart - container '$container_name' was not created by ContainAI" >&2
                echo "Remove the conflicting container manually if needed: docker rm -f '$container_name'" >&2
                return 1
            fi
        fi
        _cai_info "Stopping existing container..."
        # Get SSH port before removal for cleanup
        local restart_ssh_port
        restart_ssh_port=$(_cai_get_container_ssh_port "$container_name" "$selected_context") || restart_ssh_port=""
        # Stop container, ignoring "not running" errors but surfacing others
        local stop_output
        stop_output="$("${docker_cmd[@]}" stop "$container_name" 2>&1)" || {
            if ! printf '%s' "$stop_output" | grep -qiE "is not running"; then
                echo "$stop_output" >&2
            fi
        }
        # Remove container, ignoring "not found" errors but surfacing others
        local rm_output
        rm_output="$("${docker_cmd[@]}" rm "$container_name" 2>&1)" || {
            if ! printf '%s' "$rm_output" | grep -qiE "no such container|not found"; then
                echo "$rm_output" >&2
                return 1
            fi
        }
        # Clean up SSH configuration after successful container removal
        if [[ -n "$restart_ssh_port" ]]; then
            _cai_cleanup_container_ssh "$container_name" "$restart_ssh_port"
        fi
        container_state="none"
    fi

    # Note: Shell mode with stopped container is handled by the exited|created case
    # which starts the container and exec's into it (no recreation needed)

    # Check image exists when creating new container (use selected context)
    if [[ "$container_state" == "none" ]]; then
        if ! _containai_check_image "$resolved_image" "$selected_context"; then
            return 1
        fi
    fi

    case "$container_state" in
        running)
            # Check ownership using context-aware docker command (label or image fallback)
            local running_label_val running_image_val
            running_label_val=$("${docker_cmd[@]}" inspect --format '{{index .Config.Labels "containai.managed"}}' "$container_name" 2>/dev/null) || running_label_val=""
            if [[ "$running_label_val" != "true" ]]; then
                # Fallback: check if image is from our repo (for legacy containers without label)
                running_image_val=$("${docker_cmd[@]}" inspect --format '{{.Config.Image}}' "$container_name" 2>/dev/null) || running_image_val=""
                if ! _containai_is_our_image "$running_image_val"; then
                    echo "[ERROR] Container '$container_name' was not created by ContainAI" >&2
                    return 1
                fi
            fi
            # Check volume match using context-aware docker command
            local running_volume
            running_volume=$("${docker_cmd[@]}" inspect --format '{{range .Mounts}}{{if eq .Destination "/mnt/agent-data"}}{{.Name}}{{end}}{{end}}' "$container_name" 2>/dev/null) || running_volume=""
            if [[ "$running_volume" != "$data_volume" ]]; then
                # Warnings always emit regardless of quiet flag
                _cai_warn "Data volume mismatch:"
                _cai_warn "  Running:   ${running_volume:-<none>}"
                _cai_warn "  Requested: $data_volume"
                if [[ "$volume_mismatch_warn" != "true" ]]; then
                    echo "[ERROR] Volume mismatch prevents attachment. Use --fresh to recreate." >&2
                    return 1
                fi
            fi
            # FR-4: Validate container mounts match expected configuration (type + source)
            # This prevents shell --volume from tainting containers that run will later use
            if [[ "$shell_flag" != "true" ]]; then
                # Pass volume_mismatch_warn to skip strict volume name check when allowed
                if ! _containai_validate_fr4_mounts "$selected_context" "$container_name" "$workspace_resolved" "$data_volume" "$volume_mismatch_warn"; then
                    return 1
                fi
            fi
            # Ensure SSH setup is configured for running container
            # This handles containers that were running before SSH setup was added
            local running_ssh_port
            running_ssh_port=$(_cai_get_container_ssh_port "$container_name" "$selected_context") || running_ssh_port=""
            if [[ -n "$running_ssh_port" ]]; then
                # Setup SSH with quick_check mode (fast path for running containers)
                # Uses single keyscan attempt to avoid 30s wait if sshd/port is broken
                if ! _cai_setup_container_ssh "$container_name" "$running_ssh_port" "$selected_context" "" "true"; then
                    # SSH setup failure - command will fail, give user manual options
                    _cai_warn "SSH setup failed. For manual access:"
                    _cai_warn "  docker exec -it $container_name bash"
                    _cai_warn "  Or recreate: cai run --fresh /path/to/workspace"
                fi
            fi

            # Print container/volume info if verbose (uses _cai_info which checks verbose state)
            if [[ "$verbose_flag" == "true" ]]; then
                _cai_info "Container: $container_name"
                _cai_info "Volume: ${running_volume:-$data_volume}"
            fi

            # Execute command via SSH (container stays running after exit)
            # Behavior: -- <cmd> runs <cmd>, no -- runs default agent
            if [[ "$shell_flag" == "true" ]]; then
                # Shell mode uses the SSH shell function
                local quiet_arg=""
                if [[ "$quiet_flag" == "true" ]]; then
                    quiet_arg="true"
                fi
                _cai_ssh_shell "$container_name" "$selected_context" "" "$quiet_arg"
            else
                # Build command: env vars + (custom command OR default agent)
                local -a run_cmd=()
                # Add env vars as VAR=value prefix
                local env_var
                for env_var in "${env_vars[@]}"; do
                    run_cmd+=("$env_var")
                done
                # If -- <cmd> provided, run that command; otherwise run default agent
                if [[ ${#agent_args[@]} -gt 0 ]]; then
                    run_cmd+=("${agent_args[@]}")
                else
                    run_cmd+=("$_CONTAINAI_DEFAULT_AGENT")
                fi
                local quiet_arg=""
                if [[ "$quiet_flag" == "true" ]]; then
                    quiet_arg="true"
                fi
                if [[ "$detached_flag" == "true" ]]; then
                    # Detached mode - run in background
                    _cai_ssh_run "$container_name" "$selected_context" "" "$quiet_arg" "true" "false" "${run_cmd[@]}"
                else
                    # Interactive mode - allocate TTY
                    _cai_ssh_run "$container_name" "$selected_context" "" "$quiet_arg" "false" "true" "${run_cmd[@]}"
                fi
            fi
            ;;
        exited | created)
            # Check ownership using context-aware docker command (label or image fallback)
            local exited_label_val exited_image_fallback
            exited_label_val=$("${docker_cmd[@]}" inspect --format '{{index .Config.Labels "containai.managed"}}' "$container_name" 2>/dev/null) || exited_label_val=""
            if [[ "$exited_label_val" != "true" ]]; then
                # Fallback: check if image is from our repo (for legacy containers without label)
                exited_image_fallback=$("${docker_cmd[@]}" inspect --format '{{.Config.Image}}' "$container_name" 2>/dev/null) || exited_image_fallback=""
                if ! _containai_is_our_image "$exited_image_fallback"; then
                    echo "[ERROR] Container '$container_name' was not created by ContainAI" >&2
                    return 1
                fi
            fi
            # Check volume match using context-aware docker command
            local exited_volume
            exited_volume=$("${docker_cmd[@]}" inspect --format '{{range .Mounts}}{{if eq .Destination "/mnt/agent-data"}}{{.Name}}{{end}}{{end}}' "$container_name" 2>/dev/null) || exited_volume=""
            if [[ "$exited_volume" != "$data_volume" ]]; then
                # Warnings always emit regardless of quiet flag
                _cai_warn "Data volume mismatch:"
                _cai_warn "  Running:   ${exited_volume:-<none>}"
                _cai_warn "  Requested: $data_volume"
                if [[ "$volume_mismatch_warn" != "true" ]]; then
                    echo "[ERROR] Volume mismatch prevents start. Use --fresh to recreate." >&2
                    return 1
                fi
            fi
            # FR-4: Validate container mounts match expected configuration (type + source)
            # This prevents shell --volume from tainting containers that run will later use
            if [[ "$shell_flag" != "true" ]]; then
                # Pass volume_mismatch_warn to skip strict volume name check when allowed
                if ! _containai_validate_fr4_mounts "$selected_context" "$container_name" "$workspace_resolved" "$data_volume" "$volume_mismatch_warn"; then
                    return 1
                fi
            fi
            # Note: SSH port conflict check is handled earlier in the function (before case statement)
            # If we reach here, the port is available

            # Start stopped container (systemd is PID 1)
            _cai_info "Starting stopped container..."
            local start_output
            if ! start_output=$("${docker_cmd[@]}" start "$container_name" 2>&1); then
                local log_file=""
                log_file=$(_cai_write_container_logs "$container_name" "$selected_context" "start-failed") || log_file=""
                if [[ -n "$log_file" ]]; then
                    echo "[ERROR] Failed to start container: $start_output (logs: $log_file)" >&2
                else
                    echo "[ERROR] Failed to start container: $start_output" >&2
                fi
                return 1
            fi
            # Wait for container to be running (poll with bounded timeout)
            local wait_count=0
            local max_wait=30
            while [[ $wait_count -lt $max_wait ]]; do
                local state
                state=$("${docker_cmd[@]}" inspect --format '{{.State.Status}}' "$container_name" 2>/dev/null) || state=""
                if [[ "$state" == "running" ]]; then
                    break
                fi
                sleep 0.5
                ((wait_count++))
            done
            if [[ $wait_count -ge $max_wait ]]; then
                local log_file=""
                log_file=$(_cai_write_container_logs "$container_name" "$selected_context" "start-timeout") || log_file=""
                if [[ -n "$log_file" ]]; then
                    echo "[ERROR] Container failed to start within ${max_wait} attempts (logs: $log_file)" >&2
                else
                    echo "[ERROR] Container failed to start within ${max_wait} attempts" >&2
                fi
                return 1
            fi

            # Set up SSH access (wait for sshd, inject key, update known_hosts, write config)
            # Get SSH port from container label for stopped containers being started
            local exited_ssh_port
            exited_ssh_port=$(_cai_get_container_ssh_port "$container_name" "$selected_context") || exited_ssh_port=""
            if [[ -n "$exited_ssh_port" ]]; then
                if ! _cai_setup_container_ssh "$container_name" "$exited_ssh_port" "$selected_context"; then
                    echo "[ERROR] SSH setup failed for container" >&2
                    return 1
                fi
            fi

            # Print container/volume info if verbose (uses _cai_info which checks verbose state)
            if [[ "$verbose_flag" == "true" ]]; then
                _cai_info "Container: $container_name"
                _cai_info "Volume: ${exited_volume:-$data_volume}"
            fi

            # Execute command via SSH (container stays running after exit)
            # Behavior: -- <cmd> runs <cmd>, no -- runs default agent
            if [[ "$shell_flag" == "true" ]]; then
                # Shell mode uses the SSH shell function
                local quiet_arg=""
                if [[ "$quiet_flag" == "true" ]]; then
                    quiet_arg="true"
                fi
                _cai_ssh_shell "$container_name" "$selected_context" "" "$quiet_arg"
            else
                # Build command: env vars + (custom command OR default agent)
                local -a run_cmd=()
                # Add env vars as VAR=value prefix
                local env_var
                for env_var in "${env_vars[@]}"; do
                    run_cmd+=("$env_var")
                done
                # If -- <cmd> provided, run that command; otherwise run default agent
                if [[ ${#agent_args[@]} -gt 0 ]]; then
                    run_cmd+=("${agent_args[@]}")
                else
                    run_cmd+=("$_CONTAINAI_DEFAULT_AGENT")
                fi
                local quiet_arg=""
                if [[ "$quiet_flag" == "true" ]]; then
                    quiet_arg="true"
                fi
                if [[ "$detached_flag" == "true" ]]; then
                    # Detached mode - run in background
                    _cai_ssh_run "$container_name" "$selected_context" "" "$quiet_arg" "true" "false" "${run_cmd[@]}"
                else
                    # Interactive mode - allocate TTY
                    _cai_ssh_run "$container_name" "$selected_context" "" "$quiet_arg" "false" "true" "${run_cmd[@]}"
                fi
            fi
            ;;
        none)
            # Skip preflight checks - context selection already validated isolation
            if ! _containai_ensure_volumes "$data_volume" "$quiet_flag" "$selected_context"; then
                return 1
            fi

            # Context already selected earlier in the function (stored in docker_cmd and selected_context)

            local -a vol_args=()
            vol_args+=("-v" "$data_volume:/mnt/agent-data")

            # Create new container (systemd is PID 1)
            # Agent sessions use docker exec; container stays running between sessions
            if [[ -n "$selected_context" ]]; then
                _cai_info "Creating new container (Sysbox mode, context: $selected_context)..."
            else
                _cai_info "Creating new container (Sysbox mode)..."
            fi

            # Validate extra_volumes don't target protected paths (FR-4)
            local vol vol_dest
            for vol in "${extra_volumes[@]}"; do
                # Extract destination from volume spec (format: src:dest or src:dest:opts)
                vol_dest="${vol#*:}"       # Remove source prefix
                vol_dest="${vol_dest%%:*}" # Remove options suffix
                case "$vol_dest" in
                    /home/agent/workspace | /home/agent/workspace/*)
                        echo "[ERROR] FR-4: --volume cannot target /home/agent/workspace (protected path)" >&2
                        return 1
                        ;;
                    /mnt/agent-data | /mnt/agent-data/*)
                        echo "[ERROR] FR-4: --volume cannot target /mnt/agent-data (protected path)" >&2
                        return 1
                        ;;
                esac
            done

            # Build template image if using templates (default unless --image-tag specified)
            # This builds the user's Dockerfile using the same Docker context as container creation
            if [[ "$use_template" == "true" ]]; then
                local template_image
                # Args: template_name, context, dry_run=false, suppress_base_warning from config
                if ! template_image=$(_cai_build_template "$template_name" "$selected_context" "false" "$_CAI_TEMPLATE_SUPPRESS_BASE_WARNING"); then
                    _cai_error "Failed to build template '$template_name'"
                    return 1
                fi
                # Use the built template image for container creation
                resolved_image="$template_image"
                _cai_debug "Using template image: $resolved_image"
            fi

            # Build container creation args - always detached with tini init + sleep infinity
            local -a args=()
            if [[ -n "$selected_context" ]]; then
                args+=(--context "$selected_context")
            fi

            # Allocate SSH port and create container atomically under lock
            # This prevents race conditions where concurrent allocations pick the same port
            local ssh_port lock_fd lock_file="$_CAI_CONFIG_DIR/.ssh-port.lock"
            mkdir -p "$_CAI_CONFIG_DIR" 2>/dev/null || true

            # Use flock if available for atomic port allocation + container creation
            if command -v flock >/dev/null 2>&1; then
                exec {lock_fd}>"$lock_file"
                if ! flock -w 30 "$lock_fd"; then
                    echo "[ERROR] Timeout acquiring port allocation lock" >&2
                    return 1
                fi
            fi

            # Allocate SSH port for this container (inside lock)
            if ! ssh_port=$(_cai_allocate_ssh_port "$container_name" "$selected_context"); then
                [[ -n "${lock_fd:-}" ]] && exec {lock_fd}>&-
                echo "[ERROR] Failed to allocate SSH port for container" >&2
                return 1
            fi
            _cai_debug "Allocated SSH port $ssh_port for container $container_name"

            args+=(run)
            local runtime="sysbox-runc"
            if _cai_is_sysbox_container; then
                # Nested Sysbox is unsupported; force runc to avoid sysbox-mgr dependency.
                runtime="runc"
            fi
            args+=(--runtime="$runtime")
            args+=(--name "$container_name")
            # Hostname must be RFC 1123 compliant (lowercase, alphanumeric + hyphens)
            # Container names may contain underscores, so sanitize for hostname use
            local container_hostname
            container_hostname=$(_cai_sanitize_hostname "$container_name")
            args+=(--hostname "$container_hostname")
            args+=(--label "$_CONTAINAI_LABEL")
            args+=(--label "containai.workspace=$workspace_resolved")
            args+=(--label "containai.ssh-port=$ssh_port")
            args+=(--label "containai.data-volume=$data_volume")
            # Store template name label when using templates (fn-33-lp4.4)
            if [[ "$use_template" == "true" ]]; then
                args+=(--label "ai.containai.template=$template_name")
            fi
            # Store image-tag label when explicitly specified (advanced/debugging feature)
            # Only write when NOT using templates (image-tag is ignored with templates)
            if [[ -n "$image_tag" && "$use_template" != "true" ]]; then
                args+=(--label "containai.image-tag=$image_tag")
            fi
            args+=(-p "${ssh_port}:22") # Map allocated port to container SSH
            args+=(-d)                  # Always detached - systemd manages services

            # Cgroup resource limits (configurable via [container] config section or CLI flags)
            # Precedence: CLI flag > config > dynamic default (50% of host, 2GB/1CPU min)
            local mem_limit cpu_limit
            if [[ -n "${_CAI_CLI_MEMORY:-}" ]]; then
                mem_limit="$_CAI_CLI_MEMORY"
            elif [[ -n "${_CAI_CONTAINER_MEMORY:-}" ]]; then
                mem_limit="$_CAI_CONTAINER_MEMORY"
            else
                mem_limit=$(_cai_default_container_memory)
            fi
            if [[ -n "${_CAI_CLI_CPUS:-}" ]]; then
                cpu_limit="$_CAI_CLI_CPUS"
            elif [[ -n "${_CAI_CONTAINER_CPUS:-}" ]]; then
                cpu_limit="$_CAI_CONTAINER_CPUS"
            else
                cpu_limit=$(_cai_default_container_cpus)
            fi
            args+=(--memory="$mem_limit" --memory-swap="$mem_limit") # memory-swap=memory disables swap
            args+=(--cpus="$cpu_limit")
            args+=(--stop-timeout 100) # Allow systemd services to shut down gracefully

            # Volume mounts
            args+=("${vol_args[@]}")
            args+=(-v "$workspace_resolved:/home/agent/workspace")

            local env_var
            for vol in "${extra_volumes[@]}"; do
                args+=(-v "$vol")
            done

            # Environment variables - only stable non-secret vars at container creation
            # User-provided --env values are passed via SSH as VAR=value command prefix
            args+=(-e "CAI_HOST_WORKSPACE=$workspace_resolved")

            # Working directory
            args+=(-w /home/agent/workspace)

            # Image
            args+=("$resolved_image")

            # No command: entrypoint runs systemd as PID 1

            # Create the container (inside lock to reserve the port)
            # Clear DOCKER_HOST/DOCKER_CONTEXT to make --context in args authoritative
            local create_output
            if ! create_output=$(DOCKER_CONTEXT= DOCKER_HOST= docker "${args[@]}" 2>&1); then
                [[ -n "${lock_fd:-}" ]] && exec {lock_fd}>&-
                echo "[ERROR] Failed to create container: $create_output" >&2
                return 1
            fi

            # Release lock after container is created (port is now reserved by container)
            [[ -n "${lock_fd:-}" ]] && exec {lock_fd}>&-

            # Wait for container to be running
            # Clear DOCKER_HOST/DOCKER_CONTEXT to match creation context
            local wait_count=0
            local max_wait=30
            while [[ $wait_count -lt $max_wait ]]; do
                local state
                state=$(DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" inspect --format '{{.State.Status}}' "$container_name" 2>/dev/null) || state=""
                if [[ "$state" == "running" ]]; then
                    break
                fi
                sleep 0.5
                ((wait_count++))
            done
            if [[ $wait_count -ge $max_wait ]]; then
                local log_file=""
                log_file=$(_cai_write_container_logs "$container_name" "$selected_context" "start-timeout") || log_file=""
                if [[ -n "$log_file" ]]; then
                    echo "[ERROR] Container failed to start within ${max_wait} attempts (logs: $log_file)" >&2
                else
                    echo "[ERROR] Container failed to start within ${max_wait} attempts" >&2
                fi
                return 1
            fi

            # Set up SSH access (wait for sshd, inject key, update known_hosts, write config)
            # Force update for newly created containers (host keys are fresh)
            if ! _cai_setup_container_ssh "$container_name" "$ssh_port" "$selected_context" "true"; then
                echo "[ERROR] SSH setup failed for container" >&2
                return 1
            fi

            # Print container/volume info if verbose (uses _cai_info which checks verbose state)
            if [[ "$verbose_flag" == "true" ]]; then
                _cai_info "Container: $container_name"
                _cai_info "Volume: $data_volume"
            fi

            # Execute command via SSH (container stays running after exit)
            # Behavior: -- <cmd> runs <cmd>, no -- runs default agent
            if [[ "$shell_flag" == "true" ]]; then
                # Shell mode uses the SSH shell function
                local quiet_arg=""
                if [[ "$quiet_flag" == "true" ]]; then
                    quiet_arg="true"
                fi
                # Force SSH config update for new containers
                _cai_ssh_shell "$container_name" "$selected_context" "true" "$quiet_arg"
            else
                # Build command: env vars + (custom command OR default agent)
                local -a run_cmd=()
                # Add env vars as VAR=value prefix
                local env_var
                for env_var in "${env_vars[@]}"; do
                    run_cmd+=("$env_var")
                done
                # If -- <cmd> provided, run that command; otherwise run default agent
                if [[ ${#agent_args[@]} -gt 0 ]]; then
                    run_cmd+=("${agent_args[@]}")
                else
                    run_cmd+=("$_CONTAINAI_DEFAULT_AGENT")
                fi
                local quiet_arg=""
                if [[ "$quiet_flag" == "true" ]]; then
                    quiet_arg="true"
                fi
                if [[ "$detached_flag" == "true" ]]; then
                    # Detached mode - run in background, force SSH config update for new containers
                    _cai_ssh_run "$container_name" "$selected_context" "true" "$quiet_arg" "true" "false" "${run_cmd[@]}"
                else
                    # Interactive mode - allocate TTY, force SSH config update for new containers
                    _cai_ssh_run "$container_name" "$selected_context" "true" "$quiet_arg" "false" "true" "${run_cmd[@]}"
                fi
            fi
            ;;
        *)
            echo "[ERROR] Unexpected container state: $container_state" >&2
            return 1
            ;;
    esac
}

# ==============================================================================
# Stop all containers
# ==============================================================================

# Helper to list containers from a specific context
# Arguments: $1 = context name (empty for default)
# Outputs: containers in format "name\tstatus\tcontext" (one per line)
_containai_list_containers_for_context() {
    local context="${1:-}"
    local -a docker_cmd=(docker)
    if [[ -n "$context" ]]; then
        docker_cmd=(docker --context "$context")
    fi

    local labeled ancestor_claude ancestor_gemini line
    local claude_tag gemini_tag
    claude_tag="${_CONTAINAI_AGENT_TAGS[claude]:-latest}"
    gemini_tag="${_CONTAINAI_AGENT_TAGS[gemini]:-latest}"
    # Use || true for set -e safety - empty result is valid
    labeled=$("${docker_cmd[@]}" ps -a --filter "label=$_CONTAINAI_LABEL" --format "{{.Names}}\t{{.Status}}" 2>/dev/null) || labeled=""
    ancestor_claude=$("${docker_cmd[@]}" ps -a --filter "ancestor=${_CONTAINAI_DEFAULT_REPO}:${claude_tag}" --format "{{.Names}}\t{{.Status}}" 2>/dev/null) || ancestor_claude=""
    ancestor_gemini=$("${docker_cmd[@]}" ps -a --filter "ancestor=${_CONTAINAI_DEFAULT_REPO}:${gemini_tag}" --format "{{.Names}}\t{{.Status}}" 2>/dev/null) || ancestor_gemini=""

    # Combine and dedupe, adding context as third column
    local combined
    combined=$(printf '%s\n%s\n%s' "$labeled" "$ancestor_claude" "$ancestor_gemini" | sed -e '/^$/d' | sort -t$'\t' -k1,1 -u)
    while IFS=$'\t' read -r name status; do
        if [[ -n "$name" ]]; then
            printf '%s\t%s\t%s\n' "$name" "$status" "$context"
        fi
    done <<<"$combined"
}

# Interactive container stop selection
# Finds all ContainAI containers (by label or ancestor image) and prompts user
# Checks both default context and secure engine context (containai-docker)
# Arguments:
#   --all    Stop all containers without prompting (non-interactive mode)
#   --remove Also remove containers (not just stop) and clean SSH configs
# Returns: 0 on success, 1 on error (non-interactive without --all, or docker unavailable)
_containai_stop_all() {
    local stop_all_flag=false
    local remove_flag=false
    local arg

    for arg in "$@"; do
        case "$arg" in
            --all)
                stop_all_flag=true
                ;;
            --remove)
                remove_flag=true
                ;;
        esac
    done

    # Check docker availability first
    if ! _containai_check_docker; then
        return 1
    fi

    # Collect containers from default context
    local default_containers secure_containers all_containers
    default_containers=$(_containai_list_containers_for_context "")

    # Determine which secure engine contexts to check
    # Check both configured context (if different) and default containai-docker
    local configured_context default_secure_context="$_CAI_CONTAINAI_DOCKER_CONTEXT"
    configured_context=$(_containai_resolve_secure_engine_context 2>/dev/null) || configured_context=""

    secure_containers=""

    # Check default containai-docker context
    if docker context inspect "$default_secure_context" >/dev/null 2>&1; then
        secure_containers=$(_containai_list_containers_for_context "$default_secure_context")
    fi

    # Also check configured context if different from default
    if [[ -n "$configured_context" ]] && [[ "$configured_context" != "$default_secure_context" ]]; then
        if docker context inspect "$configured_context" >/dev/null 2>&1; then
            local config_containers
            config_containers=$(_containai_list_containers_for_context "$configured_context")
            if [[ -n "$config_containers" ]]; then
                secure_containers=$(printf '%s\n%s' "$secure_containers" "$config_containers")
            fi
        fi
    fi

    # Merge results (containers may exist in both contexts with same name - keep both)
    all_containers=$(printf '%s\n%s' "$default_containers" "$secure_containers" | sed -e '/^$/d')

    if [[ -z "$all_containers" ]]; then
        echo "No ContainAI containers found."
        return 0
    fi

    echo "ContainAI containers:"
    echo ""

    local i=0
    local names=()
    local contexts=()
    local name status ctx display_ctx
    while IFS=$'\t' read -r name status ctx; do
        i=$((i + 1))
        names+=("$name")
        contexts+=("$ctx")
        if [[ -n "$ctx" ]]; then
            display_ctx=" [context: $ctx]"
        else
            display_ctx=""
        fi
        printf "  %d) %s (%s)%s\n" "$i" "$name" "$status" "$display_ctx"
    done <<<"$all_containers"

    if [[ "$stop_all_flag" == "true" ]]; then
        echo ""
        if [[ "$remove_flag" == "true" ]]; then
            echo "Removing all containers (--all --remove flags)..."
        else
            echo "Stopping all containers (--all flag)..."
        fi
        local idx container_to_stop ctx_to_use ssh_port
        for idx in "${!names[@]}"; do
            container_to_stop="${names[$idx]}"
            ctx_to_use="${contexts[$idx]}"

            # Get SSH port before stopping/removing (for cleanup)
            ssh_port=""
            if [[ "$remove_flag" == "true" ]]; then
                ssh_port=$(_cai_get_container_ssh_port "$container_to_stop" "$ctx_to_use" 2>/dev/null) || ssh_port=""
            fi

            if [[ "$remove_flag" == "true" ]]; then
                echo "Removing: $container_to_stop${ctx_to_use:+ [context: $ctx_to_use]}"
                local rm_success=false
                if [[ -n "$ctx_to_use" ]]; then
                    if docker --context "$ctx_to_use" rm -f "$container_to_stop" >/dev/null 2>&1; then
                        rm_success=true
                    fi
                else
                    if docker rm -f "$container_to_stop" >/dev/null 2>&1; then
                        rm_success=true
                    fi
                fi
                # Only clean up SSH config after SUCCESSFUL removal
                if [[ "$rm_success" == "true" ]]; then
                    # Clean by port if known, otherwise try to get port from config file
                    if [[ -z "$ssh_port" ]]; then
                        # Legacy container - try to get port from config file before removing it
                        local config_file="$_CAI_SSH_CONFIG_DIR/${container_to_stop}.conf"
                        if [[ -f "$config_file" ]]; then
                            ssh_port=$(grep -E '^[[:space:]]*Port[[:space:]]+' "$config_file" 2>/dev/null | awk '{print $2}' | head -1) || ssh_port=""
                        fi
                    fi
                    if [[ -n "$ssh_port" ]]; then
                        _cai_cleanup_container_ssh "$container_to_stop" "$ssh_port"
                    else
                        # No port found anywhere - just remove config file
                        _cai_remove_ssh_host_config "$container_to_stop"
                    fi
                else
                    echo "  Warning: Failed to remove $container_to_stop (skipping SSH cleanup)"
                fi
            else
                echo "Stopping: $container_to_stop${ctx_to_use:+ [context: $ctx_to_use]}"
                if [[ -n "$ctx_to_use" ]]; then
                    docker --context "$ctx_to_use" stop "$container_to_stop" >/dev/null 2>&1 || true
                else
                    docker stop "$container_to_stop" >/dev/null 2>&1 || true
                fi
            fi
        done
        echo "Done."
        return 0
    fi

    if [[ ! -t 0 ]]; then
        echo "" >&2
        echo "[ERROR] Non-interactive terminal detected." >&2
        echo "Use --all flag to stop all containers without prompting:" >&2
        echo "  cai-stop-all --all" >&2
        return 1
    fi

    echo ""
    echo "Enter numbers to stop (space-separated), 'all', or 'q' to quit:"
    local selection
    # Guard read for set -e safety (EOF returns non-zero)
    if ! read -r selection; then
        echo "Cancelled."
        return 0
    fi

    if [[ "$selection" == "q" || "$selection" == "Q" ]]; then
        echo "Cancelled."
        return 0
    fi

    local -a to_stop_idx=()

    if [[ "$selection" == "all" || "$selection" == "ALL" ]]; then
        local idx
        for idx in "${!names[@]}"; do
            to_stop_idx+=("$idx")
        done
    else
        local num
        for num in $selection; do
            if [[ "$num" =~ ^[0-9]+$ ]] && [[ "$num" -ge 1 ]] && [[ "$num" -le "${#names[@]}" ]]; then
                to_stop_idx+=("$((num - 1))")
            else
                _cai_warn "Invalid selection: $num"
            fi
        done
    fi

    if [[ ${#to_stop_idx[@]} -eq 0 ]]; then
        echo "No containers selected."
        return 0
    fi

    echo ""
    local idx container_to_stop ctx_to_use ssh_port
    for idx in "${to_stop_idx[@]}"; do
        container_to_stop="${names[$idx]}"
        ctx_to_use="${contexts[$idx]}"

        # Get SSH port before stopping/removing (for cleanup)
        ssh_port=""
        if [[ "$remove_flag" == "true" ]]; then
            ssh_port=$(_cai_get_container_ssh_port "$container_to_stop" "$ctx_to_use" 2>/dev/null) || ssh_port=""
        fi

        if [[ "$remove_flag" == "true" ]]; then
            echo "Removing: $container_to_stop${ctx_to_use:+ [context: $ctx_to_use]}"
            local rm_success=false
            if [[ -n "$ctx_to_use" ]]; then
                if docker --context "$ctx_to_use" rm -f "$container_to_stop" >/dev/null 2>&1; then
                    rm_success=true
                fi
            else
                if docker rm -f "$container_to_stop" >/dev/null 2>&1; then
                    rm_success=true
                fi
            fi
            # Only clean up SSH config after SUCCESSFUL removal
            if [[ "$rm_success" == "true" ]]; then
                # Clean by port if known, otherwise try to get port from config file
                if [[ -z "$ssh_port" ]]; then
                    # Legacy container - try to get port from config file before removing it
                    local config_file="$_CAI_SSH_CONFIG_DIR/${container_to_stop}.conf"
                    if [[ -f "$config_file" ]]; then
                        ssh_port=$(grep -E '^[[:space:]]*Port[[:space:]]+' "$config_file" 2>/dev/null | awk '{print $2}' | head -1) || ssh_port=""
                    fi
                fi
                if [[ -n "$ssh_port" ]]; then
                    _cai_cleanup_container_ssh "$container_to_stop" "$ssh_port"
                else
                    # No port found anywhere - just remove config file
                    _cai_remove_ssh_host_config "$container_to_stop"
                fi
            else
                echo "  Warning: Failed to remove $container_to_stop (skipping SSH cleanup)"
            fi
        else
            echo "Stopping: $container_to_stop${ctx_to_use:+ [context: $ctx_to_use]}"
            if [[ -n "$ctx_to_use" ]]; then
                docker --context "$ctx_to_use" stop "$container_to_stop" >/dev/null 2>&1 || true
            else
                docker stop "$container_to_stop" >/dev/null 2>&1 || true
            fi
        fi
    done

    echo "Done."
}

return 0
