#!/usr/bin/env bash
# ==============================================================================
# ContainAI Container Operations
# ==============================================================================
# This file must be sourced, not executed directly.
#
# Provides:
#   _containai_container_name      - Generate sanitized container name
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
: "${_CONTAINAI_DEFAULT_REPO:=agent-sandbox}"
: "${_CONTAINAI_DEFAULT_AGENT:=claude}"
: "${_CONTAINAI_DEFAULT_CREDENTIALS:=none}"

# Map agent name to default image tag
# Format: agent -> tag
declare -A _CONTAINAI_AGENT_TAGS 2>/dev/null || true
_CONTAINAI_AGENT_TAGS=(
    [claude]="claude-code"
    [gemini]="gemini-cli"
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
                _cai_info "Pull the image with: docker --context $context pull $image"
            else
                _cai_info "Pull the image with: docker pull $image"
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

    # Normalize path: resolve symlinks and canonicalize
    # cd + pwd -P is most portable; fallback to path as-is if it doesn't exist yet
    if normalized=$(cd -- "$path" 2>/dev/null && pwd -P); then
        : # success
    else
        # Path doesn't exist or isn't a directory - use as-is
        normalized="$path"
    fi

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

# Generate container name from workspace path hash
# Format: containai-<12-char-hash>
# Arguments: $1 = workspace path (required)
# Returns: container name via stdout, or 1 on error
_containai_container_name() {
    local workspace_path="$1"
    local hash name

    if [[ -z "$workspace_path" ]]; then
        # Fallback to current directory if no workspace provided
        workspace_path="$(pwd)"
    fi

    # Propagate hash errors - don't create invalid container names
    if ! hash=$(_cai_hash_path "$workspace_path"); then
        return 1
    fi

    name="containai-${hash}"

    printf '%s' "$name"
}

# Find container by workspace and optionally filter by image-tag label
# This is for advanced/debugging use when running multiple images per workspace.
# Normal use (one container per workspace) should use _containai_container_name directly.
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

    # Get the expected container name for this workspace
    if ! container_name=$(_containai_container_name "$workspace_path"); then
        return 1
    fi

    # Build docker command with optional context
    local -a docker_cmd=(docker)
    if [[ -n "$docker_context" ]]; then
        docker_cmd=(docker --context "$docker_context")
    fi

    # If no image-tag filter, just check if the container exists
    if [[ -z "$image_tag_filter" ]]; then
        if "${docker_cmd[@]}" inspect --type container "$container_name" >/dev/null 2>&1; then
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
            /etc/hosts|/etc/hostname|/etc/resolv.conf)
                # Docker-managed, allowed
                ;;
            *)
                # Unexpected mount destination
                echo "[ERROR] FR-4: Container has unexpected mount: $mount_dest" >&2
                echo "[INFO] Container may have been tainted by 'cai shell --volume'" >&2
                echo "[INFO] Use --fresh to recreate with clean mount configuration" >&2
                return 1
                ;;
        esac
    done <<< "$mount_info"

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

    # Guard: check docker availability
    if ! command -v docker >/dev/null 2>&1; then
        echo "[WARN] Unable to determine isolation status (docker not found)" >&2
        return 2
    fi

    # Use docker info --format for reliable structured output with timeout
    # Use if ! pattern for set -e safety
    if ! runtime=$(_cai_timeout 5 docker info --format '{{.DefaultRuntime}}' 2>/dev/null); then
        echo "[WARN] Unable to determine isolation status" >&2
        return 2
    fi
    if [[ -z "$runtime" ]]; then
        echo "[WARN] Unable to determine isolation status" >&2
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
        echo "[WARN] No additional isolation detected (standard runtime)" >&2
        return 1
    fi

    echo "[WARN] Unable to determine isolation status" >&2
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

    if [[ "$force_flag" == "true" ]]; then
        echo "[WARN] Skipping isolation check (--force)" >&2
        if [[ "${CONTAINAI_REQUIRE_ISOLATION:-0}" == "1" ]]; then
            echo "*** WARNING: Bypassing isolation requirement with --force" >&2
            echo "*** Running without verified isolation may expose host system" >&2
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
        if [[ "$quiet" != "true" ]]; then
            echo "Creating volume: $volume_name"
        fi
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
        return 0  # Container exists
    fi

    # Check if it's "no such" vs other errors
    if printf '%s' "$inspect_output" | grep -qiE "no such object|not found|error.*no such"; then
        return 1  # Container doesn't exist
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
        return 1  # Doesn't exist = not ours
    elif [[ $exists_rc -eq 2 ]]; then
        return 2  # Docker error
    fi

    # Get label value - use if ! pattern for set -e safety
    if ! label_value=$(_containai_get_container_label "$container_name"); then
        return 2  # Docker error
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
        return 2  # Container doesn't exist
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
        if [[ "$quiet_flag" != "true" ]]; then
            echo "[WARN] Image mismatch for container '$container_name'" >&2
            echo "" >&2
            echo "  Container image: $actual_image" >&2
            echo "  Requested image: $resolved_image" >&2
            echo "" >&2
            echo "The container was created with a different agent/image." >&2
            echo "To use the requested agent, recreate the container:" >&2
            echo "  cai --restart" >&2
            echo "Or specify a different container name:" >&2
            echo "  cai --name <unique-name>" >&2
            echo "" >&2
        fi
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
        if [[ "$quiet_flag" != "true" ]]; then
            echo "[WARN] Volume mismatch for container '$container_name'" >&2
            echo "" >&2
            echo "  Container uses volume: $mounted_volume" >&2
            echo "  Workspace expects:     $desired_volume" >&2
            echo "" >&2
            echo "The container was created with a different workspace/config." >&2
            echo "To use the correct volume, recreate the container:" >&2
            echo "  cai --restart" >&2
            echo "Or specify a different container name:" >&2
            echo "  cai --name <unique-name>" >&2
            echo "" >&2
        fi
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
#   --debug              Enable debug logging
#   --image-tag <tag>    Image tag for container (advanced/debugging, stored as label)
#   -e, --env <VAR=val>  Environment variable (repeatable, passed to command via SSH)
#   -v, --volume <spec>  Extra volume mount (repeatable)
#   -- <cmd>             Command to run (default: agent); e.g., -- bash runs bash
# Returns: 0 on success, 1 on failure
_containai_start_container() {
    local container_name=""
    local workspace=""
    local data_volume=""
    local explicit_config=""
    local image_tag=""
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
            --workspace|-w)
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
            --detached|-d)
                detached_flag=true
                shift
                ;;
            --shell)
                shell_flag=true
                shift
                ;;
            --quiet|-q)
                quiet_flag=true
                shift
                ;;
            --debug|-D)
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
            --env|-e)
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
            --volume|-v)
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

    # Resolve image: use --image-tag if provided (advanced/debugging), else default
    local resolved_image
    if [[ -n "$image_tag" ]]; then
        # Advanced mode: explicit image tag for debugging or multi-image workflows
        resolved_image="${_CONTAINAI_DEFAULT_REPO}:${image_tag}"
    else
        # Default: one container per workspace with default agent image
        resolved_image="${_CONTAINAI_DEFAULT_REPO}:${_CONTAINAI_AGENT_TAGS[$_CONTAINAI_DEFAULT_AGENT]}"
    fi

    # Early docker check
    if ! command -v docker >/dev/null 2>&1; then
        echo "[ERROR] Docker is not installed or not in PATH" >&2
        return 1
    fi

    # Resolve workspace
    local workspace_resolved
    workspace_resolved="${workspace:-$PWD}"
    # Use pwd -P to resolve symlinks consistently (matches _cai_hash_path normalization)
    if ! workspace_resolved=$(cd -- "$workspace_resolved" 2>/dev/null && pwd -P); then
        echo "[ERROR] Workspace path does not exist: ${workspace:-$PWD}" >&2
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

    # Auto-select Docker context based on isolation availability
    local selected_context debug_mode=""
    if [[ "$debug_flag" == "true" ]]; then
        debug_mode="debug"
    fi
    if ! selected_context=$(_cai_select_context "$config_context_override" "$debug_mode"); then
        if [[ "$force_flag" == "true" ]]; then
            echo "[WARN] No Sysbox context available but --force specified." >&2
            echo "[WARN] Container creation will still require sysbox-runc runtime." >&2
            echo "[WARN] This may fail if Sysbox is not installed on the default Docker host." >&2
            selected_context=""
        else
            _cai_error "No isolation available. Run 'cai doctor' for setup instructions."
            _cai_error "Use --force to bypass context selection (Sysbox runtime still required)"
            return 1
        fi
    fi

    # Build docker command prefix based on context
    # Context is always Sysbox mode
    local -a docker_cmd=(docker)
    if [[ -n "$selected_context" ]]; then
        docker_cmd=(docker --context "$selected_context")
    fi

    # Get container name (based on workspace path hash for deterministic naming)
    if [[ -z "$container_name" ]]; then
        if ! container_name=$(_containai_container_name "$workspace_resolved"); then
            echo "[ERROR] Failed to generate container name for workspace: $workspace_resolved" >&2
            return 1
        fi
    fi
    if [[ "$quiet_flag" != "true" && "$dry_run_flag" != "true" ]]; then
        echo "Container: $container_name"
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
            exited|created)
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
                    if [[ "$port_conflict_image" != "${_CONTAINAI_DEFAULT_REPO}:"* ]]; then
                        echo "[ERROR] Cannot recreate container - '$container_name' was not created by ContainAI" >&2
                        echo "[ERROR] SSH port $existing_ssh_port is in use. Remove the container manually or use a different name." >&2
                        return 1
                    fi
                fi
                if [[ "$quiet_flag" != "true" ]]; then
                    echo "[WARN] SSH port $existing_ssh_port is in use by another process" >&2
                    echo "Recreating container with new port allocation..."
                fi
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
            if [[ "$fresh_image_fallback" != "${_CONTAINAI_DEFAULT_REPO}:"* ]]; then
                echo "[ERROR] Cannot use --fresh - container '$container_name' was not created by ContainAI" >&2
                echo "Remove the conflicting container manually if needed: docker rm -f '$container_name'" >&2
                return 1
            fi
        fi
        if [[ "$quiet_flag" != "true" ]]; then
            echo "Removing existing container (--fresh)..."
        fi
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
            if [[ "$restart_image_fallback" != "${_CONTAINAI_DEFAULT_REPO}:"* ]]; then
                echo "[ERROR] Cannot restart - container '$container_name' was not created by ContainAI" >&2
                echo "Remove the conflicting container manually if needed: docker rm -f '$container_name'" >&2
                return 1
            fi
        fi
        if [[ "$quiet_flag" != "true" ]]; then
            echo "Stopping existing container..."
        fi
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
                if [[ "$running_image_val" != "${_CONTAINAI_DEFAULT_REPO}:"* ]]; then
                    echo "[ERROR] Container '$container_name' was not created by ContainAI" >&2
                    return 1
                fi
            fi
            # Check volume match using context-aware docker command
            local running_volume
            running_volume=$("${docker_cmd[@]}" inspect --format '{{range .Mounts}}{{if eq .Destination "/mnt/agent-data"}}{{.Name}}{{end}}{{end}}' "$container_name" 2>/dev/null) || running_volume=""
            if [[ "$running_volume" != "$data_volume" ]]; then
                if [[ "$quiet_flag" != "true" ]]; then
                    echo "[WARN] Data volume mismatch:" >&2
                    echo "  Running:   ${running_volume:-<none>}" >&2
                    echo "  Requested: $data_volume" >&2
                fi
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
        exited|created)
            # Check ownership using context-aware docker command (label or image fallback)
            local exited_label_val exited_image_fallback
            exited_label_val=$("${docker_cmd[@]}" inspect --format '{{index .Config.Labels "containai.managed"}}' "$container_name" 2>/dev/null) || exited_label_val=""
            if [[ "$exited_label_val" != "true" ]]; then
                # Fallback: check if image is from our repo (for legacy containers without label)
                exited_image_fallback=$("${docker_cmd[@]}" inspect --format '{{.Config.Image}}' "$container_name" 2>/dev/null) || exited_image_fallback=""
                if [[ "$exited_image_fallback" != "${_CONTAINAI_DEFAULT_REPO}:"* ]]; then
                    echo "[ERROR] Container '$container_name' was not created by ContainAI" >&2
                    return 1
                fi
            fi
            # Check volume match using context-aware docker command
            local exited_volume
            exited_volume=$("${docker_cmd[@]}" inspect --format '{{range .Mounts}}{{if eq .Destination "/mnt/agent-data"}}{{.Name}}{{end}}{{end}}' "$container_name" 2>/dev/null) || exited_volume=""
            if [[ "$exited_volume" != "$data_volume" ]]; then
                if [[ "$quiet_flag" != "true" ]]; then
                    echo "[WARN] Data volume mismatch:" >&2
                    echo "  Running:   ${exited_volume:-<none>}" >&2
                    echo "  Requested: $data_volume" >&2
                fi
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

            # Start stopped container (tini is PID 1 managing sleep infinity)
            if [[ "$quiet_flag" != "true" ]]; then
                echo "Starting stopped container..."
            fi
            local start_output
            if ! start_output=$("${docker_cmd[@]}" start "$container_name" 2>&1); then
                echo "[ERROR] Failed to start container: $start_output" >&2
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
                echo "[ERROR] Container failed to start within ${max_wait} attempts" >&2
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

            # Create new container with sleep infinity as PID 1 (long-lived init)
            # Agent sessions use docker exec; container stays running between sessions
            if [[ "$quiet_flag" != "true" ]]; then
                if [[ -n "$selected_context" ]]; then
                    echo "Creating new container (Sysbox mode, context: $selected_context)..."
                else
                    echo "Creating new container (Sysbox mode)..."
                fi
            fi

            # Validate extra_volumes don't target protected paths (FR-4)
            local vol vol_dest
            for vol in "${extra_volumes[@]}"; do
                # Extract destination from volume spec (format: src:dest or src:dest:opts)
                vol_dest="${vol#*:}"  # Remove source prefix
                vol_dest="${vol_dest%%:*}"  # Remove options suffix
                case "$vol_dest" in
                    /home/agent/workspace|/home/agent/workspace/*)
                        echo "[ERROR] FR-4: --volume cannot target /home/agent/workspace (protected path)" >&2
                        return 1
                        ;;
                    /mnt/agent-data|/mnt/agent-data/*)
                        echo "[ERROR] FR-4: --volume cannot target /mnt/agent-data (protected path)" >&2
                        return 1
                        ;;
                esac
            done

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
            args+=(--runtime=sysbox-runc)
            args+=(--init)  # tini becomes PID 1 to properly reap zombie processes
            args+=(--name "$container_name")
            args+=(--label "$_CONTAINAI_LABEL")
            args+=(--label "containai.workspace=$workspace_resolved")
            args+=(--label "containai.ssh-port=$ssh_port")
            # Store image-tag label when explicitly specified (advanced/debugging feature)
            if [[ -n "$image_tag" ]]; then
                args+=(--label "containai.image-tag=$image_tag")
            fi
            args+=(-p "${ssh_port}:22")  # Map allocated port to container SSH
            args+=(-d)  # Always detached - tini manages sleep infinity as child

            # Cgroup resource limits (configurable via [container] config section)
            # Default: 4g memory, 2 CPUs, 100s stop timeout for systemd graceful shutdown
            local mem_limit="${_CAI_CONTAINER_MEMORY:-4g}"
            local cpu_limit="${_CAI_CONTAINER_CPUS:-2}"
            args+=(--memory="$mem_limit" --memory-swap="$mem_limit")  # memory-swap=memory disables swap
            args+=(--cpus="$cpu_limit")
            args+=(--stop-timeout 100)  # Allow systemd services to shut down gracefully

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

            # Command: sleep infinity (runs as child of tini, container stays running between sessions)
            args+=(sleep infinity)

            # Create the container (inside lock to reserve the port)
            local create_output
            if ! create_output=$(docker "${args[@]}" 2>&1); then
                [[ -n "${lock_fd:-}" ]] && exec {lock_fd}>&-
                echo "[ERROR] Failed to create container: $create_output" >&2
                return 1
            fi

            # Release lock after container is created (port is now reserved by container)
            [[ -n "${lock_fd:-}" ]] && exec {lock_fd}>&-

            # Wait for container to be running
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
                echo "[ERROR] Container failed to start within ${max_wait} attempts" >&2
                return 1
            fi

            # Set up SSH access (wait for sshd, inject key, update known_hosts, write config)
            # Force update for newly created containers (host keys are fresh)
            if ! _cai_setup_container_ssh "$container_name" "$ssh_port" "$selected_context" "true"; then
                echo "[ERROR] SSH setup failed for container" >&2
                return 1
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
    # Use || true for set -e safety - empty result is valid
    labeled=$("${docker_cmd[@]}" ps -a --filter "label=$_CONTAINAI_LABEL" --format "{{.Names}}\t{{.Status}}" 2>/dev/null) || labeled=""
    ancestor_claude=$("${docker_cmd[@]}" ps -a --filter "ancestor=${_CONTAINAI_DEFAULT_REPO}:claude-code" --format "{{.Names}}\t{{.Status}}" 2>/dev/null) || ancestor_claude=""
    ancestor_gemini=$("${docker_cmd[@]}" ps -a --filter "ancestor=${_CONTAINAI_DEFAULT_REPO}:gemini-cli" --format "{{.Names}}\t{{.Status}}" 2>/dev/null) || ancestor_gemini=""

    # Combine and dedupe, adding context as third column
    local combined
    combined=$(printf '%s\n%s\n%s' "$labeled" "$ancestor_claude" "$ancestor_gemini" | sed -e '/^$/d' | sort -t$'\t' -k1,1 -u)
    while IFS=$'\t' read -r name status; do
        if [[ -n "$name" ]]; then
            printf '%s\t%s\t%s\n' "$name" "$status" "$context"
        fi
    done <<< "$combined"
}

# Interactive container stop selection
# Finds all ContainAI containers (by label or ancestor image) and prompts user
# Checks both default context and secure engine context (containai-secure)
# Arguments: --all to stop all without prompting (non-interactive mode)
# Returns: 0 on success, 1 on error (non-interactive without --all, or docker unavailable)
_containai_stop_all() {
    local stop_all_flag=false
    local arg

    for arg in "$@"; do
        case "$arg" in
            --all)
                stop_all_flag=true
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
    # Check both configured context (if different) and default containai-secure
    local configured_context default_secure_context="containai-secure"
    configured_context=$(_containai_resolve_secure_engine_context 2>/dev/null) || configured_context=""

    secure_containers=""

    # Check default containai-secure context
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
    done <<< "$all_containers"

    if [[ "$stop_all_flag" == "true" ]]; then
        echo ""
        echo "Stopping all containers (--all flag)..."
        local idx container_to_stop ctx_to_use
        for idx in "${!names[@]}"; do
            container_to_stop="${names[$idx]}"
            ctx_to_use="${contexts[$idx]}"
            echo "Stopping: $container_to_stop${ctx_to_use:+ [context: $ctx_to_use]}"
            if [[ -n "$ctx_to_use" ]]; then
                docker --context "$ctx_to_use" stop "$container_to_stop" >/dev/null 2>&1 || true
            else
                docker stop "$container_to_stop" >/dev/null 2>&1 || true
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
                echo "[WARN] Invalid selection: $num" >&2
            fi
        done
    fi

    if [[ ${#to_stop_idx[@]} -eq 0 ]]; then
        echo "No containers selected."
        return 0
    fi

    echo ""
    local idx container_to_stop ctx_to_use
    for idx in "${to_stop_idx[@]}"; do
        container_to_stop="${names[$idx]}"
        ctx_to_use="${contexts[$idx]}"
        echo "Stopping: $container_to_stop${ctx_to_use:+ [context: $ctx_to_use]}"
        if [[ -n "$ctx_to_use" ]]; then
            docker --context "$ctx_to_use" stop "$container_to_stop" >/dev/null 2>&1 || true
        else
            docker stop "$container_to_stop" >/dev/null 2>&1 || true
        fi
    done

    echo "Done."
}

return 0
