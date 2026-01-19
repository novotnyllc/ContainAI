#!/usr/bin/env bash
# ==============================================================================
# ContainAI CLI - Main Entry Point
# ==============================================================================
# This file must be sourced, not executed directly.
#
# Usage: source agent-sandbox/containai.sh
# Then: cai / containai are available as shell functions
#
# Subcommands:
#   (default)    Start/attach to sandbox container
#   shell        Open interactive shell in running container
#   import       Sync host configs to data volume
#   export       Export data volume to .tgz archive
#   stop         Stop ContainAI containers
#   help         Show help message
#
# ==============================================================================

# Require bash first (before using BASH_SOURCE)
if [ -z "${BASH_VERSION:-}" ]; then
    echo "[ERROR] containai.sh requires bash" >&2
    return 1 2>/dev/null || exit 1
fi

# Detect direct execution (must be sourced, not executed)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "[ERROR] containai.sh must be sourced, not executed directly" >&2
    echo "Usage: source agent-sandbox/containai.sh" >&2
    exit 1
fi

# Guard against re-sourcing side effects
if [[ -n "${_CONTAINAI_LIB_LOADED:-}" ]]; then
    return 0
fi

# Determine script directory
_CAI_SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ==============================================================================
# Library loading
# ==============================================================================
# Source modular libraries from lib/*.sh

# Check if all lib files exist
_containai_libs_exist() {
    [[ -f "$_CAI_SCRIPT_DIR/lib/core.sh" ]] && \
    [[ -f "$_CAI_SCRIPT_DIR/lib/platform.sh" ]] && \
    [[ -f "$_CAI_SCRIPT_DIR/lib/docker.sh" ]] && \
    [[ -f "$_CAI_SCRIPT_DIR/lib/eci.sh" ]] && \
    [[ -f "$_CAI_SCRIPT_DIR/lib/config.sh" ]] && \
    [[ -f "$_CAI_SCRIPT_DIR/lib/container.sh" ]] && \
    [[ -f "$_CAI_SCRIPT_DIR/lib/import.sh" ]] && \
    [[ -f "$_CAI_SCRIPT_DIR/lib/export.sh" ]]
}

if ! _containai_libs_exist; then
    echo "[ERROR] Required lib/*.sh files not found" >&2
    echo "  Expected at: $_CAI_SCRIPT_DIR/lib/*.sh" >&2
    return 1
fi

# Clean up one-shot helper function to reduce namespace pollution
unset -f _containai_libs_exist

# Source library files with error checking
# Order matters: core.sh first (logging), then platform/docker, then config, then others
# Note: config.sh must come before import.sh (depends on _containai_resolve_excludes)
if ! source "$_CAI_SCRIPT_DIR/lib/core.sh"; then
    echo "[ERROR] Failed to source lib/core.sh" >&2
    return 1
fi

if ! source "$_CAI_SCRIPT_DIR/lib/platform.sh"; then
    echo "[ERROR] Failed to source lib/platform.sh" >&2
    return 1
fi

if ! source "$_CAI_SCRIPT_DIR/lib/docker.sh"; then
    echo "[ERROR] Failed to source lib/docker.sh" >&2
    return 1
fi

if ! source "$_CAI_SCRIPT_DIR/lib/eci.sh"; then
    echo "[ERROR] Failed to source lib/eci.sh" >&2
    return 1
fi

if ! source "$_CAI_SCRIPT_DIR/lib/config.sh"; then
    echo "[ERROR] Failed to source lib/config.sh" >&2
    return 1
fi

if ! source "$_CAI_SCRIPT_DIR/lib/container.sh"; then
    echo "[ERROR] Failed to source lib/container.sh" >&2
    return 1
fi

if ! source "$_CAI_SCRIPT_DIR/lib/import.sh"; then
    echo "[ERROR] Failed to source lib/import.sh" >&2
    return 1
fi

if ! source "$_CAI_SCRIPT_DIR/lib/export.sh"; then
    echo "[ERROR] Failed to source lib/export.sh" >&2
    return 1
fi

# Mark libraries as loaded
_CONTAINAI_LIB_LOADED="1"

# ==============================================================================
# Help functions
# ==============================================================================

_containai_help() {
    cat <<'EOF'
ContainAI - Run Claude Code in a secure Docker sandbox

Usage: containai [subcommand] [options]
       cai [subcommand] [options]

Subcommands:
  (default)     Start/attach to sandbox container
  shell         Open interactive shell in running container
  import        Sync host configs to data volume
  export        Export data volume to .tgz archive
  stop          Stop ContainAI containers
  help          Show this help message

Global Options:
  --data-volume <vol>   Data volume name (overrides config)
  --config <path>       Config file path (overrides auto-discovery)
  --workspace <path>    Workspace path (default: current directory)
  -h, --help            Show help (use with subcommand for subcommand help)

Examples:
  cai                           Start sandbox in current directory
  cai shell                     Open shell in running sandbox
  cai import                    Sync configs to data volume
  cai import --dry-run          Preview import without changes
  cai export                    Export data volume to archive
  cai export -o ~/backup.tgz    Export to specific path
  cai stop                      Stop sandbox containers
  cai stop --all                Stop all containers without prompting

For subcommand-specific help:
  cai <subcommand> --help

Volume Selection:
  Volume is automatically selected based on workspace path from config.
  Use --data-volume to override automatic selection.
EOF
}

_containai_import_help() {
    cat <<'EOF'
ContainAI Import - Sync host configs to data volume

Usage: cai import [options]

Options:
  --data-volume <vol>   Data volume name (overrides config)
  --config <path>       Config file path (overrides auto-discovery)
  --workspace <path>    Workspace path for config resolution
  --dry-run             Preview changes without applying
  --no-excludes         Skip exclude patterns from config
  -h, --help            Show this help message

Examples:
  cai import                    Sync configs to auto-resolved volume
  cai import --dry-run          Preview what would be synced
  cai import --no-excludes      Sync without applying excludes
  cai import --data-volume vol  Sync to specific volume
EOF
}

_containai_export_help() {
    cat <<'EOF'
ContainAI Export - Export data volume to .tgz archive

Usage: cai export [options]

Options:
  -o, --output <path>   Output path (file or directory)
  --data-volume <vol>   Data volume name (overrides config)
  --config <path>       Config file path (overrides auto-discovery)
  --workspace <path>    Workspace path for config resolution
  --no-excludes         Skip exclude patterns from config
  -h, --help            Show this help message

Output Path:
  If not specified, creates containai-export-YYYYMMDD-HHMMSS.tgz in current dir.
  If path is a directory, appends default filename.
  Output directory must exist.

Examples:
  cai export                         Export to current directory
  cai export -o ~/backup.tgz         Export to specific file
  cai export -o ~/backups/           Export to directory with auto-name
  cai export --data-volume vol       Export specific volume
EOF
}

_containai_stop_help() {
    cat <<'EOF'
ContainAI Stop - Stop ContainAI containers

Usage: cai stop [options]

Options:
  --all         Stop all containers without prompting
  -h, --help    Show this help message

Examples:
  cai stop        Interactive selection to stop containers
  cai stop --all  Stop all ContainAI containers
EOF
}

_containai_shell_help() {
    cat <<'EOF'
ContainAI Shell - Open interactive shell in sandbox

Usage: cai shell [options]

Opens a bash shell in the running sandbox container.
If no container exists, creates one first.

Options:
  --data-volume <vol>   Data volume name (overrides config)
  --config <path>       Config file path (overrides auto-discovery)
  --workspace <path>    Workspace path (default: current directory)
  --name <name>         Container name (default: auto-generated)
  --restart             Force recreate container
  --force               Skip sandbox availability check
  -q, --quiet           Suppress verbose output
  -e, --env <VAR=val>   Set environment variable (repeatable)
  -v, --volume <spec>   Extra volume mount (repeatable)
  -h, --help            Show this help message

Examples:
  cai shell                    Open shell in default sandbox
  cai shell --restart          Recreate container and open shell
  cai shell -e DEBUG=1         Open shell with environment variable
EOF
}

# ==============================================================================
# Subcommand handlers
# ==============================================================================

# Import subcommand handler
_containai_import_cmd() {
    local dry_run="false"
    local no_excludes="false"
    local cli_volume=""
    local workspace=""
    local explicit_config=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                dry_run="true"
                shift
                ;;
            --no-excludes)
                no_excludes="true"
                shift
                ;;
            --data-volume)
                if [[ -z "${2-}" ]]; then
                    echo "[ERROR] --data-volume requires a value" >&2
                    return 1
                fi
                cli_volume="$2"
                shift 2
                ;;
            --data-volume=*)
                cli_volume="${1#--data-volume=}"
                if [[ -z "$cli_volume" ]]; then
                    echo "[ERROR] --data-volume requires a value" >&2
                    return 1
                fi
                shift
                ;;
            --config)
                if [[ -z "${2-}" ]]; then
                    echo "[ERROR] --config requires a value" >&2
                    return 1
                fi
                explicit_config="$2"
                explicit_config="${explicit_config/#\~/$HOME}"
                shift 2
                ;;
            --config=*)
                explicit_config="${1#--config=}"
                if [[ -z "$explicit_config" ]]; then
                    echo "[ERROR] --config requires a value" >&2
                    return 1
                fi
                explicit_config="${explicit_config/#\~/$HOME}"
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
                if [[ -z "$workspace" ]]; then
                    echo "[ERROR] --workspace requires a value" >&2
                    return 1
                fi
                workspace="${workspace/#\~/$HOME}"
                shift
                ;;
            -w*)
                workspace="${1#-w}"
                workspace="${workspace/#\~/$HOME}"
                shift
                ;;
            --help|-h)
                _containai_import_help
                return 0
                ;;
            *)
                echo "[ERROR] Unknown option: $1" >&2
                echo "Use 'cai import --help' for usage" >&2
                return 1
                ;;
        esac
    done

    # Resolve workspace
    local resolved_workspace="${workspace:-$PWD}"
    if ! resolved_workspace=$(cd -- "$resolved_workspace" 2>/dev/null && pwd); then
        echo "[ERROR] Workspace path does not exist: ${workspace:-$PWD}" >&2
        return 1
    fi

    # Resolve volume
    local resolved_volume
    if ! resolved_volume=$(_containai_resolve_volume "$cli_volume" "$resolved_workspace" "$explicit_config"); then
        echo "[ERROR] Failed to resolve data volume" >&2
        return 1
    fi

    # Call import function
    _containai_import "$resolved_volume" "$dry_run" "$no_excludes" "$resolved_workspace" "$explicit_config"
}

# Export subcommand handler
_containai_export_cmd() {
    local output_path=""
    local no_excludes="false"
    local cli_volume=""
    local workspace=""
    local explicit_config=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -o|--output)
                if [[ -z "${2-}" ]]; then
                    echo "[ERROR] --output requires a value" >&2
                    return 1
                fi
                output_path="$2"
                output_path="${output_path/#\~/$HOME}"
                shift 2
                ;;
            --output=*)
                output_path="${1#--output=}"
                if [[ -z "$output_path" ]]; then
                    echo "[ERROR] --output requires a value" >&2
                    return 1
                fi
                output_path="${output_path/#\~/$HOME}"
                shift
                ;;
            -o*)
                output_path="${1#-o}"
                output_path="${output_path/#\~/$HOME}"
                shift
                ;;
            --no-excludes)
                no_excludes="true"
                shift
                ;;
            --data-volume)
                if [[ -z "${2-}" ]]; then
                    echo "[ERROR] --data-volume requires a value" >&2
                    return 1
                fi
                cli_volume="$2"
                shift 2
                ;;
            --data-volume=*)
                cli_volume="${1#--data-volume=}"
                if [[ -z "$cli_volume" ]]; then
                    echo "[ERROR] --data-volume requires a value" >&2
                    return 1
                fi
                shift
                ;;
            --config)
                if [[ -z "${2-}" ]]; then
                    echo "[ERROR] --config requires a value" >&2
                    return 1
                fi
                explicit_config="$2"
                explicit_config="${explicit_config/#\~/$HOME}"
                shift 2
                ;;
            --config=*)
                explicit_config="${1#--config=}"
                if [[ -z "$explicit_config" ]]; then
                    echo "[ERROR] --config requires a value" >&2
                    return 1
                fi
                explicit_config="${explicit_config/#\~/$HOME}"
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
                if [[ -z "$workspace" ]]; then
                    echo "[ERROR] --workspace requires a value" >&2
                    return 1
                fi
                workspace="${workspace/#\~/$HOME}"
                shift
                ;;
            -w*)
                workspace="${1#-w}"
                workspace="${workspace/#\~/$HOME}"
                shift
                ;;
            --help|-h)
                _containai_export_help
                return 0
                ;;
            *)
                echo "[ERROR] Unknown option: $1" >&2
                echo "Use 'cai export --help' for usage" >&2
                return 1
                ;;
        esac
    done

    # Resolve workspace
    local resolved_workspace="${workspace:-$PWD}"
    if ! resolved_workspace=$(cd -- "$resolved_workspace" 2>/dev/null && pwd); then
        echo "[ERROR] Workspace path does not exist: ${workspace:-$PWD}" >&2
        return 1
    fi

    # Resolve volume
    local resolved_volume
    if ! resolved_volume=$(_containai_resolve_volume "$cli_volume" "$resolved_workspace" "$explicit_config"); then
        echo "[ERROR] Failed to resolve data volume" >&2
        return 1
    fi

    # Resolve excludes from config (unless --no-excludes)
    local -a export_excludes=()
    if [[ "$no_excludes" != "true" ]]; then
        local exclude_output exclude_line
        if [[ -n "$explicit_config" ]]; then
            if ! exclude_output=$(_containai_resolve_excludes "$resolved_workspace" "$explicit_config"); then
                echo "[ERROR] Failed to resolve excludes from config: $explicit_config" >&2
                return 1
            fi
        else
            # For discovered config, silently ignore errors
            exclude_output=$(_containai_resolve_excludes "$resolved_workspace" "" 2>/dev/null) || exclude_output=""
        fi
        while IFS= read -r exclude_line; do
            if [[ -n "$exclude_line" ]]; then
                export_excludes+=("$exclude_line")
            fi
        done <<< "$exclude_output"
    fi

    # Call export function - pass array name, not array
    _containai_export "$resolved_volume" "$output_path" "export_excludes" "$no_excludes"
}

# Stop subcommand handler
_containai_stop_cmd() {
    local arg
    for arg in "$@"; do
        case "$arg" in
            --help|-h)
                _containai_stop_help
                return 0
                ;;
        esac
    done

    _containai_stop_all "$@"
}

# Shell subcommand handler - delegates to _containai_start_container with --shell
_containai_shell_cmd() {
    local cli_volume=""
    local workspace=""
    local explicit_config=""
    local container_name=""
    local restart_flag=""
    local force_flag=""
    local quiet_flag=""
    local debug_flag=""
    local mount_docker_socket=""
    local please_root_my_host=""
    local -a env_vars=()
    local -a extra_volumes=()

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --data-volume)
                if [[ -z "${2-}" ]]; then
                    echo "[ERROR] --data-volume requires a value" >&2
                    return 1
                fi
                cli_volume="$2"
                shift 2
                ;;
            --data-volume=*)
                cli_volume="${1#--data-volume=}"
                if [[ -z "$cli_volume" ]]; then
                    echo "[ERROR] --data-volume requires a value" >&2
                    return 1
                fi
                shift
                ;;
            --config)
                if [[ -z "${2-}" ]]; then
                    echo "[ERROR] --config requires a value" >&2
                    return 1
                fi
                explicit_config="$2"
                explicit_config="${explicit_config/#\~/$HOME}"
                shift 2
                ;;
            --config=*)
                explicit_config="${1#--config=}"
                if [[ -z "$explicit_config" ]]; then
                    echo "[ERROR] --config requires a value" >&2
                    return 1
                fi
                explicit_config="${explicit_config/#\~/$HOME}"
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
                if [[ -z "$workspace" ]]; then
                    echo "[ERROR] --workspace requires a value" >&2
                    return 1
                fi
                workspace="${workspace/#\~/$HOME}"
                shift
                ;;
            -w*)
                workspace="${1#-w}"
                workspace="${workspace/#\~/$HOME}"
                shift
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
                if [[ -z "$container_name" ]]; then
                    echo "[ERROR] --name requires a value" >&2
                    return 1
                fi
                shift
                ;;
            --restart)
                restart_flag="--restart"
                shift
                ;;
            --force)
                force_flag="--force"
                shift
                ;;
            --quiet|-q)
                quiet_flag="--quiet"
                shift
                ;;
            --debug|-D)
                debug_flag="--debug"
                shift
                ;;
            --mount-docker-socket)
                mount_docker_socket="--mount-docker-socket"
                shift
                ;;
            --please-root-my-host)
                please_root_my_host="--please-root-my-host"
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
            --help|-h)
                _containai_shell_help
                return 0
                ;;
            *)
                echo "[ERROR] Unknown option: $1" >&2
                echo "Use 'cai shell --help' for usage" >&2
                return 1
                ;;
        esac
    done

    # Resolve workspace
    local resolved_workspace="${workspace:-$PWD}"
    if ! resolved_workspace=$(cd -- "$resolved_workspace" 2>/dev/null && pwd); then
        echo "[ERROR] Workspace path does not exist: ${workspace:-$PWD}" >&2
        return 1
    fi

    # Resolve volume
    local resolved_volume
    if ! resolved_volume=$(_containai_resolve_volume "$cli_volume" "$resolved_workspace" "$explicit_config"); then
        echo "[ERROR] Failed to resolve data volume" >&2
        return 1
    fi

    # Build args for _containai_start_container
    local -a start_args=()
    start_args+=(--shell)
    start_args+=(--data-volume "$resolved_volume")
    start_args+=(--workspace "$resolved_workspace")

    # Add volume mismatch warn for implicit volume selection
    if [[ -z "$cli_volume" ]] && [[ -z "$explicit_config" ]]; then
        start_args+=(--volume-mismatch-warn)
    fi

    if [[ -n "$container_name" ]]; then
        start_args+=(--name "$container_name")
    fi
    if [[ -n "$restart_flag" ]]; then
        start_args+=("$restart_flag")
    fi
    if [[ -n "$force_flag" ]]; then
        start_args+=("$force_flag")
    fi
    if [[ -n "$quiet_flag" ]]; then
        start_args+=("$quiet_flag")
    fi
    if [[ -n "$debug_flag" ]]; then
        start_args+=("$debug_flag")
    fi
    if [[ -n "$mount_docker_socket" ]]; then
        start_args+=("$mount_docker_socket")
    fi
    if [[ -n "$please_root_my_host" ]]; then
        start_args+=("$please_root_my_host")
    fi
    local env_var vol
    for env_var in "${env_vars[@]}"; do
        start_args+=(--env "$env_var")
    done
    for vol in "${extra_volumes[@]}"; do
        start_args+=(--volume "$vol")
    done

    _containai_start_container "${start_args[@]}"
}

# Default (run container) handler
_containai_run_cmd() {
    local cli_volume=""
    local workspace=""
    local explicit_config=""
    local container_name=""
    local restart_flag=""
    local force_flag=""
    local detached_flag=""
    local quiet_flag=""
    local debug_flag=""
    local mount_docker_socket=""
    local please_root_my_host=""
    local -a env_vars=()
    local -a extra_volumes=()
    local -a agent_args=()

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --)
                shift
                agent_args=("$@")
                break
                ;;
            --data-volume)
                if [[ -z "${2-}" ]]; then
                    echo "[ERROR] --data-volume requires a value" >&2
                    return 1
                fi
                cli_volume="$2"
                shift 2
                ;;
            --data-volume=*)
                cli_volume="${1#--data-volume=}"
                if [[ -z "$cli_volume" ]]; then
                    echo "[ERROR] --data-volume requires a value" >&2
                    return 1
                fi
                shift
                ;;
            --config)
                if [[ -z "${2-}" ]]; then
                    echo "[ERROR] --config requires a value" >&2
                    return 1
                fi
                explicit_config="$2"
                explicit_config="${explicit_config/#\~/$HOME}"
                shift 2
                ;;
            --config=*)
                explicit_config="${1#--config=}"
                if [[ -z "$explicit_config" ]]; then
                    echo "[ERROR] --config requires a value" >&2
                    return 1
                fi
                explicit_config="${explicit_config/#\~/$HOME}"
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
                if [[ -z "$workspace" ]]; then
                    echo "[ERROR] --workspace requires a value" >&2
                    return 1
                fi
                workspace="${workspace/#\~/$HOME}"
                shift
                ;;
            -w*)
                workspace="${1#-w}"
                workspace="${workspace/#\~/$HOME}"
                shift
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
                if [[ -z "$container_name" ]]; then
                    echo "[ERROR] --name requires a value" >&2
                    return 1
                fi
                shift
                ;;
            --restart)
                restart_flag="--restart"
                shift
                ;;
            --force)
                force_flag="--force"
                shift
                ;;
            --detached|-d)
                detached_flag="--detached"
                shift
                ;;
            --quiet|-q)
                quiet_flag="--quiet"
                shift
                ;;
            --debug|-D)
                debug_flag="--debug"
                shift
                ;;
            --mount-docker-socket)
                mount_docker_socket="--mount-docker-socket"
                shift
                ;;
            --please-root-my-host)
                please_root_my_host="--please-root-my-host"
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
            --help|-h)
                _containai_help
                return 0
                ;;
            *)
                echo "[ERROR] Unknown option: $1" >&2
                echo "Use 'cai --help' for usage" >&2
                return 1
                ;;
        esac
    done

    # Resolve workspace
    local resolved_workspace="${workspace:-$PWD}"
    if ! resolved_workspace=$(cd -- "$resolved_workspace" 2>/dev/null && pwd); then
        echo "[ERROR] Workspace path does not exist: ${workspace:-$PWD}" >&2
        return 1
    fi

    # Resolve volume
    local resolved_volume
    if ! resolved_volume=$(_containai_resolve_volume "$cli_volume" "$resolved_workspace" "$explicit_config"); then
        echo "[ERROR] Failed to resolve data volume" >&2
        return 1
    fi

    # Build args for _containai_start_container
    local -a start_args=()
    start_args+=(--data-volume "$resolved_volume")
    start_args+=(--workspace "$resolved_workspace")

    # Add volume mismatch warn for implicit volume selection
    if [[ -z "$cli_volume" ]] && [[ -z "$explicit_config" ]]; then
        start_args+=(--volume-mismatch-warn)
    fi

    if [[ -n "$container_name" ]]; then
        start_args+=(--name "$container_name")
    fi
    if [[ -n "$restart_flag" ]]; then
        start_args+=("$restart_flag")
    fi
    if [[ -n "$force_flag" ]]; then
        start_args+=("$force_flag")
    fi
    if [[ -n "$detached_flag" ]]; then
        start_args+=("$detached_flag")
    fi
    if [[ -n "$quiet_flag" ]]; then
        start_args+=("$quiet_flag")
    fi
    if [[ -n "$debug_flag" ]]; then
        start_args+=("$debug_flag")
    fi
    if [[ -n "$mount_docker_socket" ]]; then
        start_args+=("$mount_docker_socket")
    fi
    if [[ -n "$please_root_my_host" ]]; then
        start_args+=("$please_root_my_host")
    fi
    local env_var vol
    for env_var in "${env_vars[@]}"; do
        start_args+=(--env "$env_var")
    done
    for vol in "${extra_volumes[@]}"; do
        start_args+=(--volume "$vol")
    done

    # Add agent args after --
    if [[ ${#agent_args[@]} -gt 0 ]]; then
        start_args+=(--)
        start_args+=("${agent_args[@]}")
    fi

    _containai_start_container "${start_args[@]}"
}

# ==============================================================================
# Main CLI function
# ==============================================================================

containai() {
    local subcommand="${1:-}"

    # Handle empty or help first
    if [[ -z "$subcommand" ]]; then
        _containai_run_cmd
        return $?
    fi

    # Route to subcommands
    case "$subcommand" in
        shell)
            shift
            _containai_shell_cmd "$@"
            ;;
        import)
            shift
            _containai_import_cmd "$@"
            ;;
        export)
            shift
            _containai_export_cmd "$@"
            ;;
        stop)
            shift
            _containai_stop_cmd "$@"
            ;;
        help|-h|--help)
            _containai_help
            ;;
        -*)
            # Flags without subcommand go to default run
            _containai_run_cmd "$@"
            ;;
        *)
            # Unknown token - delegate to default run which will handle unknown flags
            # This preserves backward compatibility and allows passing through args
            _containai_run_cmd "$@"
            ;;
    esac
}

# Short alias
cai() { containai "$@"; }

# ==============================================================================
# Convenience aliases
# ==============================================================================

# cai-shell - open shell in sandbox (convenience wrapper)
cai-shell() { containai shell "$@"; }
containai-shell() { containai shell "$@"; }

# caid - run detached (convenience wrapper)
caid() { containai --detached "$@"; }
containaid() { containai --detached "$@"; }

# cai-stop-all - stop containers (convenience wrapper)
cai-stop-all() { containai stop "$@"; }
containai-stop-all() { containai stop "$@"; }

return 0
