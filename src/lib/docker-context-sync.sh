#!/usr/bin/env bash
# ==============================================================================
# ContainAI Docker Context Sync Library
# ==============================================================================
# Bidirectional sync between ~/.docker/contexts and ~/.docker-cai/contexts
# with special handling for the containai-docker context which has different
# socket paths on host vs container.
#
# Provides:
#   _cai_sync_docker_contexts_once()       - One-time sync from source to target
#   _cai_create_containai_docker_context() - Create containai-docker context for container
#   _cai_watch_docker_contexts()           - Start continuous file watcher
#   _cai_is_containai_docker_context()     - Check if path is containai-docker context
#   _cai_docker_context_sync_available()   - Check if sync tools are available
#
# Context paths:
#   Host contexts:      ~/.docker/contexts/
#   Container contexts: ~/.docker-cai/contexts/
#
# The containai-docker context is special:
#   - Host version uses SSH socket (ssh://user@host)
#   - Container version needs Unix socket (unix:///var/run/docker.sock)
#   - Therefore it is NOT synced between host and container
#
# Dependencies:
#   - Requires lib/core.sh for logging functions
#   - Requires lib/platform.sh for platform detection
#   - Optional: inotifywait (Linux) or fswatch (macOS) for watching
#
# Usage: source lib/docker-context-sync.sh
# ==============================================================================

# Require bash first (before using BASH_SOURCE)
if [[ -z "${BASH_VERSION:-}" ]]; then
    printf '[ERROR] lib/docker-context-sync.sh requires bash\n' >&2
    return 1 2>/dev/null || exit 1
fi

# Detect direct execution (must be sourced, not executed)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    printf '[ERROR] lib/docker-context-sync.sh must be sourced, not executed directly\n' >&2
    printf 'Usage: source lib/docker-context-sync.sh\n' >&2
    exit 1
fi

# Guard against re-sourcing side effects
if [[ -n "${_CAI_DOCKER_CONTEXT_SYNC_LOADED:-}" ]]; then
    return 0
fi
_CAI_DOCKER_CONTEXT_SYNC_LOADED=1

# ==============================================================================
# Constants
# ==============================================================================

# Standard Docker contexts directory
readonly _CAI_DOCKER_CONTEXTS_DIR="${HOME}/.docker/contexts"

# ContainAI-specific contexts directory (used in containers)
readonly _CAI_DOCKER_CAI_CONTEXTS_DIR="${HOME}/.docker-cai/contexts"

# Name of the special containai-docker context (not synced)
readonly _CAI_CONTAINAI_CONTEXT_NAME="containai-docker"

# ==============================================================================
# Helper Functions
# ==============================================================================

# Check if a context directory path is the containai-docker context
# Arguments: $1 = context directory path (e.g., ~/.docker/contexts/meta/abc123...)
# Returns: 0 if yes (is containai-docker), 1 if no
_cai_is_containai_docker_context() {
    local context_path="$1"
    local meta_file

    # Context metadata is stored in meta.json within the context hash directory
    meta_file="${context_path}/meta.json"

    if [[ ! -f "$meta_file" ]]; then
        return 1
    fi

    # Check if the context name matches containai-docker
    # The meta.json contains {"Name": "context-name", ...}
    if grep -q "\"Name\"[[:space:]]*:[[:space:]]*\"${_CAI_CONTAINAI_CONTEXT_NAME}\"" "$meta_file" 2>/dev/null; then
        return 0
    fi

    return 1
}

# Get the context name from a context directory
# Arguments: $1 = context directory path
# Outputs: Context name on stdout
# Returns: 0 on success, 1 if cannot determine
_cai_get_context_name() {
    local context_path="$1"
    local meta_file="${context_path}/meta.json"

    if [[ ! -f "$meta_file" ]]; then
        return 1
    fi

    # Extract name from JSON - simple grep/sed approach for portability
    # Format: {"Name": "context-name", ...}
    local name
    name=$(grep -o '"Name"[[:space:]]*:[[:space:]]*"[^"]*"' "$meta_file" 2>/dev/null | \
           sed 's/.*"Name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')

    if [[ -z "$name" ]]; then
        return 1
    fi

    printf '%s' "$name"
    return 0
}

# Check if file watcher tools are available
# Returns: 0 if available, 1 if not
# Outputs: Sets _CAI_CONTEXT_WATCHER with available tool name
_cai_docker_context_sync_available() {
    _CAI_CONTEXT_WATCHER=""

    # Check for inotifywait (Linux)
    if command -v inotifywait >/dev/null 2>&1; then
        _CAI_CONTEXT_WATCHER="inotifywait"
        return 0
    fi

    # Check for fswatch (macOS, also available on Linux)
    if command -v fswatch >/dev/null 2>&1; then
        _CAI_CONTEXT_WATCHER="fswatch"
        return 0
    fi

    return 1
}

# ==============================================================================
# Core Sync Functions
# ==============================================================================

# Sync Docker contexts from source to target directory (one-time)
# Arguments:
#   $1 = source directory (e.g., ~/.docker/contexts)
#   $2 = target directory (e.g., ~/.docker-cai/contexts)
#   $3 = direction: "host-to-cai" or "cai-to-host"
# Returns: 0 on success, 1 on error
# Notes:
#   - Syncs all contexts EXCEPT containai-docker
#   - Creates target directories if missing
#   - Syncs both metadata and TLS certificates
_cai_sync_docker_contexts_once() {
    local source_dir="$1"
    local target_dir="$2"
    local direction="$3"

    # Validate arguments
    if [[ -z "$source_dir" || -z "$target_dir" || -z "$direction" ]]; then
        _cai_error "Usage: _cai_sync_docker_contexts_once <source> <target> <direction>"
        return 1
    fi

    if [[ "$direction" != "host-to-cai" && "$direction" != "cai-to-host" ]]; then
        _cai_error "Direction must be 'host-to-cai' or 'cai-to-host'"
        return 1
    fi

    # Source must exist
    if [[ ! -d "$source_dir" ]]; then
        _cai_debug "Source directory does not exist: $source_dir"
        return 0
    fi

    # Create target directory structure if needed
    # Docker contexts are stored in: contexts/meta/<hash>/ and contexts/tls/<hash>/
    mkdir -p "${target_dir}/meta" "${target_dir}/tls" 2>/dev/null || {
        _cai_error "Failed to create target directories: $target_dir"
        return 1
    }

    local synced=0
    local skipped=0
    local errors=0

    # Sync context metadata (contexts/meta/<hash>/)
    if [[ -d "${source_dir}/meta" ]]; then
        local context_hash
        for context_hash in "${source_dir}/meta/"*/; do
            # Skip if not a directory
            [[ ! -d "$context_hash" ]] && continue

            # Get context hash name (basename)
            local hash_name
            hash_name=$(basename "$context_hash")

            # Skip containai-docker context
            if _cai_is_containai_docker_context "$context_hash"; then
                _cai_debug "Skipping containai-docker context (not synced)"
                skipped=$((skipped + 1))
                continue
            fi

            local target_meta="${target_dir}/meta/${hash_name}"

            # Copy context metadata
            if ! cp -a "$context_hash" "${target_dir}/meta/" 2>/dev/null; then
                _cai_warn "Failed to sync context: $hash_name"
                errors=$((errors + 1))
                continue
            fi

            # Also sync TLS certs if they exist for this context
            local source_tls="${source_dir}/tls/${hash_name}"
            if [[ -d "$source_tls" ]]; then
                if ! cp -a "$source_tls" "${target_dir}/tls/" 2>/dev/null; then
                    _cai_warn "Failed to sync TLS certs for context: $hash_name"
                    # Don't count as full error - context still synced
                fi
            fi

            synced=$((synced + 1))
            _cai_debug "Synced context: $hash_name"
        done
    fi

    # Handle deletions: remove contexts in target that don't exist in source
    if [[ -d "${target_dir}/meta" ]]; then
        local target_hash
        for target_hash in "${target_dir}/meta/"*/; do
            [[ ! -d "$target_hash" ]] && continue

            local hash_name
            hash_name=$(basename "$target_hash")

            # Skip containai-docker context
            if _cai_is_containai_docker_context "$target_hash"; then
                continue
            fi

            # Check if source still has this context
            if [[ ! -d "${source_dir}/meta/${hash_name}" ]]; then
                _cai_debug "Removing deleted context from target: $hash_name"
                rm -rf "${target_dir}/meta/${hash_name}" 2>/dev/null || true
                rm -rf "${target_dir}/tls/${hash_name}" 2>/dev/null || true
            fi
        done
    fi

    _cai_info "Context sync ($direction): $synced synced, $skipped skipped, $errors errors"

    [[ $errors -eq 0 ]]
}

# Create the containai-docker context for use inside containers
# This creates a context pointing to the container's local Docker socket
# Arguments: none
# Returns: 0 on success, 1 on error
_cai_create_containai_docker_context() {
    local contexts_dir="$_CAI_DOCKER_CAI_CONTEXTS_DIR"
    local socket_path="unix:///var/run/docker.sock"

    # Ensure contexts directory exists
    mkdir -p "${contexts_dir}/meta" "${contexts_dir}/tls" 2>/dev/null || {
        _cai_error "Failed to create contexts directory: $contexts_dir"
        return 1
    }

    # Generate a hash for the context (Docker uses SHA256, we'll use a simple approach)
    # The hash is used as the directory name under meta/
    local context_hash
    context_hash=$(printf '%s' "$_CAI_CONTAINAI_CONTEXT_NAME" | sha256sum | cut -c1-64)

    local meta_dir="${contexts_dir}/meta/${context_hash}"
    mkdir -p "$meta_dir" 2>/dev/null || {
        _cai_error "Failed to create context meta directory"
        return 1
    }

    # Create meta.json with context configuration
    # This matches Docker's context metadata format
    if ! cat > "${meta_dir}/meta.json" <<EOF
{
    "Name": "${_CAI_CONTAINAI_CONTEXT_NAME}",
    "Metadata": {
        "Description": "ContainAI Docker context (container-local)"
    },
    "Endpoints": {
        "docker": {
            "Host": "${socket_path}",
            "SkipTLSVerify": false
        }
    }
}
EOF
    then
        _cai_error "Failed to write context metadata"
        return 1
    fi

    _cai_info "Created containai-docker context at ${meta_dir}"
    return 0
}

# ==============================================================================
# File Watcher Functions
# ==============================================================================

# Start watching Docker contexts directories for changes
# Performs bidirectional sync when changes are detected
# Arguments:
#   $1 = (optional) "foreground" to run in foreground, otherwise backgrounds
# Returns: 0 on success (or PID if backgrounded), 1 on error
# Notes:
#   - Uses inotifywait on Linux, fswatch on macOS
#   - Watches both ~/.docker/contexts and ~/.docker-cai/contexts
#   - Triggers sync on create/delete/modify events
_cai_watch_docker_contexts() {
    local foreground="${1:-background}"

    # Check if watcher tools are available
    if ! _cai_docker_context_sync_available; then
        _cai_warn "No file watcher available (install inotifywait or fswatch)"
        _cai_warn "  Linux: apt install inotify-tools"
        _cai_warn "  macOS: brew install fswatch"
        return 1
    fi

    # Ensure both directories exist
    mkdir -p "$_CAI_DOCKER_CONTEXTS_DIR" "$_CAI_DOCKER_CAI_CONTEXTS_DIR" 2>/dev/null

    _cai_info "Starting Docker context watcher using $_CAI_CONTEXT_WATCHER"

    if [[ "$_CAI_CONTEXT_WATCHER" == "inotifywait" ]]; then
        _cai_watch_with_inotifywait "$foreground"
    elif [[ "$_CAI_CONTEXT_WATCHER" == "fswatch" ]]; then
        _cai_watch_with_fswatch "$foreground"
    else
        _cai_error "Unknown watcher: $_CAI_CONTEXT_WATCHER"
        return 1
    fi
}

# Internal: Watch using inotifywait (Linux)
_cai_watch_with_inotifywait() {
    local foreground="$1"

    local watch_cmd=(
        inotifywait
        -m                          # Monitor continuously
        -r                          # Recursive
        -e create -e delete -e modify -e moved_to -e moved_from
        --format '%w%f %e'
        "$_CAI_DOCKER_CONTEXTS_DIR"
        "$_CAI_DOCKER_CAI_CONTEXTS_DIR"
    )

    if [[ "$foreground" == "foreground" ]]; then
        "${watch_cmd[@]}" 2>/dev/null | while read -r path event; do
            _cai_handle_context_change "$path" "$event"
        done
    else
        # Run in background
        (
            "${watch_cmd[@]}" 2>/dev/null | while read -r path event; do
                _cai_handle_context_change "$path" "$event"
            done
        ) &
        local pid=$!
        _cai_info "Context watcher started (PID: $pid)"
        printf '%s' "$pid"
    fi
}

# Internal: Watch using fswatch (macOS)
_cai_watch_with_fswatch() {
    local foreground="$1"

    local watch_cmd=(
        fswatch
        -r                          # Recursive
        --event Created --event Removed --event Updated --event Renamed
        "$_CAI_DOCKER_CONTEXTS_DIR"
        "$_CAI_DOCKER_CAI_CONTEXTS_DIR"
    )

    if [[ "$foreground" == "foreground" ]]; then
        "${watch_cmd[@]}" 2>/dev/null | while read -r path; do
            _cai_handle_context_change "$path" "modified"
        done
    else
        # Run in background
        (
            "${watch_cmd[@]}" 2>/dev/null | while read -r path; do
                _cai_handle_context_change "$path" "modified"
            done
        ) &
        local pid=$!
        _cai_info "Context watcher started (PID: $pid)"
        printf '%s' "$pid"
    fi
}

# Internal: Handle a context change event
# Arguments: $1 = path that changed, $2 = event type
_cai_handle_context_change() {
    local path="$1"
    local event="$2"

    _cai_debug "Context change detected: $path ($event)"

    # Determine sync direction based on which directory changed
    if [[ "$path" == "${_CAI_DOCKER_CONTEXTS_DIR}"* ]]; then
        # Host Docker contexts changed -> sync to CAI contexts
        _cai_sync_docker_contexts_once \
            "$_CAI_DOCKER_CONTEXTS_DIR" \
            "$_CAI_DOCKER_CAI_CONTEXTS_DIR" \
            "host-to-cai"
    elif [[ "$path" == "${_CAI_DOCKER_CAI_CONTEXTS_DIR}"* ]]; then
        # CAI contexts changed -> sync to host Docker contexts
        _cai_sync_docker_contexts_once \
            "$_CAI_DOCKER_CAI_CONTEXTS_DIR" \
            "$_CAI_DOCKER_CONTEXTS_DIR" \
            "cai-to-host"
    fi
}

# Stop the Docker context watcher
# Arguments: $1 = PID of watcher process (optional, kills all if not specified)
# Returns: 0 on success
_cai_stop_docker_context_watcher() {
    local pid="${1:-}"

    if [[ -n "$pid" ]]; then
        kill "$pid" 2>/dev/null || true
        _cai_info "Stopped context watcher (PID: $pid)"
    else
        # Kill all inotifywait/fswatch processes watching our directories
        pkill -f "inotifywait.*${_CAI_DOCKER_CONTEXTS_DIR}" 2>/dev/null || true
        pkill -f "fswatch.*${_CAI_DOCKER_CONTEXTS_DIR}" 2>/dev/null || true
        _cai_info "Stopped all context watchers"
    fi

    return 0
}

return 0
