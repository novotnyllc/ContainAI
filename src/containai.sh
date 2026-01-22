#!/usr/bin/env bash
# ==============================================================================
# ContainAI CLI - Main Entry Point
# ==============================================================================
# This file must be sourced, not executed directly.
#
# Usage: source src/containai.sh (or agent-sandbox/containai.sh for backward compatibility)
# Then: cai / containai are available as shell functions
#
# Subcommands:
#   run          Start/attach to sandbox container (default if omitted)
#   shell        Open interactive shell in running container
#   doctor       Check system capabilities and show diagnostics
#   setup        Install Sysbox Secure Engine (WSL2/macOS)
#   validate     Validate Secure Engine configuration
#   sandbox      (Deprecated - use 'cai stop && cai --restart')
#   import       Sync host configs to data volume
#   export       Export data volume to .tgz archive
#   stop         Stop ContainAI containers
#   version      Show current version
#   update       Update ContainAI installation
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
    echo "Usage: source src/containai.sh" >&2
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
    [[ -f "$_CAI_SCRIPT_DIR/lib/doctor.sh" ]] && \
    [[ -f "$_CAI_SCRIPT_DIR/lib/config.sh" ]] && \
    [[ -f "$_CAI_SCRIPT_DIR/lib/container.sh" ]] && \
    [[ -f "$_CAI_SCRIPT_DIR/lib/import.sh" ]] && \
    [[ -f "$_CAI_SCRIPT_DIR/lib/export.sh" ]] && \
    [[ -f "$_CAI_SCRIPT_DIR/lib/setup.sh" ]] && \
    [[ -f "$_CAI_SCRIPT_DIR/lib/env.sh" ]] && \
    [[ -f "$_CAI_SCRIPT_DIR/lib/version.sh" ]]
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

if ! source "$_CAI_SCRIPT_DIR/lib/doctor.sh"; then
    echo "[ERROR] Failed to source lib/doctor.sh" >&2
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

if ! source "$_CAI_SCRIPT_DIR/lib/setup.sh"; then
    echo "[ERROR] Failed to source lib/setup.sh" >&2
    return 1
fi

if ! source "$_CAI_SCRIPT_DIR/lib/env.sh"; then
    echo "[ERROR] Failed to source lib/env.sh" >&2
    return 1
fi

if ! source "$_CAI_SCRIPT_DIR/lib/version.sh"; then
    echo "[ERROR] Failed to source lib/version.sh" >&2
    return 1
fi

# Mark libraries as loaded
_CONTAINAI_LIB_LOADED="1"

# ==============================================================================
# Help functions
# ==============================================================================

_containai_help() {
    cat <<'EOF'
ContainAI - Run AI coding agents in a secure Docker sandbox

Usage: containai [subcommand] [options]
       cai [subcommand] [options]

Subcommands:
  run           Start/attach to sandbox container (default if omitted)
  shell         Open interactive shell in running container
  doctor        Check system capabilities and show diagnostics
  setup         Install Sysbox Secure Engine (WSL2/macOS)
  validate      Validate Secure Engine configuration
  sandbox       (Deprecated - use 'cai stop && cai --restart')
  import        Sync host configs to data volume
  export        Export data volume to .tgz archive
  stop          Stop ContainAI containers
  version       Show current version
  update        Update ContainAI installation
  help          Show this help message

Run Options:
  <path>                Workspace path (positional, alternative to --workspace)
  --agent <name>        Agent to run (claude, gemini; default: claude)
  --credentials <mode>  Credential mode (none; default: none)
  --image-tag <tag>     Override image tag (default: agent-specific)
  --data-volume <vol>   Data volume name (overrides config)
  --config <path>       Config file path (overrides auto-discovery)
  --workspace <path>    Workspace path (default: current directory)
  --name <name>         Container name (default: auto-generated from path hash)
  --fresh               Remove and recreate container (preserves data volume)
  --restart             Force recreate container (alias for --fresh)
  --force               Skip isolation checks (for testing only)
  --detached, -d        Run in background
  --quiet, -q           Suppress verbose output
  -e, --env <VAR=val>   Set environment variable (repeatable)
  -- <args>             Pass arguments to agent

Container Lifecycle:
  Containers use tini (--init) as PID 1 for proper zombie reaping, running sleep infinity.
  Agent sessions attach via docker exec. Container stays running between sessions.
  Same workspace path always maps to same container (deterministic naming via hash).

Global Options:
  -h, --help            Show help (use with subcommand for subcommand help)

Examples:
  cai                               Start Claude container (default)
  cai /path/to/project              Start container for specified workspace
  cai --fresh /path/to/project      Recreate container for workspace
  cai --agent gemini                Start Gemini container
  cai -- --print                    Pass --print to Claude
  cai doctor                        Check system capabilities
  cai shell                         Open shell in running container
  cai stop --all                    Stop all containers

Safe Defaults:
  - Credentials mode defaults to 'none'
  - No Docker socket mounted by default
  - No arbitrary volume mounts (only workspace + data volume for persistence)

Volume Selection:
  Volume is automatically selected based on workspace path from config.
  Use --data-volume to override automatic selection.

Context Selection:
  Context is automatically selected based on Sysbox availability.
  Override with [secure_engine].context_name in config.
EOF
}

_containai_import_help() {
    cat <<'EOF'
ContainAI Import - Sync host configs to data volume

Usage: cai import [options]

Options:
  --data-volume <vol>   Data volume name (overrides config)
  --from <path>         Import source:
                        - Directory: syncs from that directory (default: $HOME)
                        - Archive (.tgz): restores archive to volume (idempotent)
  --config <path>       Config file path (overrides auto-discovery)
  --workspace <path>    Workspace path for config resolution
  --dry-run             Preview changes without applying
  --no-excludes         Skip exclude patterns from config
  -h, --help            Show this help message

Examples:
  cai import                           Sync configs to auto-resolved volume
  cai import --dry-run                 Preview what would be synced
  cai import --no-excludes             Sync without applying excludes
  cai import --data-volume vol         Sync to specific volume
  cai import --from ~/other-configs/   Sync from different directory
  cai import --from backup.tgz         Restore volume from archive
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

_containai_sandbox_help() {
    cat <<'EOF'
ContainAI Sandbox - DEPRECATED

The 'cai sandbox' command has been removed. ContainAI now uses Sysbox
for container isolation instead of Docker Desktop sandboxes.

Migration:
  cai sandbox reset         -> cai stop && cai --restart
  cai sandbox clear-credentials -> Remove data volume: docker volume rm <volume-name>

For container management, use:
  cai stop                  Stop the container
  cai --restart             Recreate with new configuration
  cai doctor                Check Sysbox availability
EOF
}

_containai_shell_help() {
    cat <<'EOF'
ContainAI Shell - Open interactive shell in container

Usage: cai shell [options]

Opens a bash shell in the running container.
If no container exists, creates one first.

Options:
  --data-volume <vol>   Data volume name (overrides config)
  --config <path>       Config file path (overrides auto-discovery)
  --workspace <path>    Workspace path (default: current directory)
  --name <name>         Container name (default: auto-generated)
  --fresh               Remove and recreate container (preserves data volume)
  --restart             Force recreate container (alias for --fresh)
  --force               Skip isolation checks (for testing only)
  -q, --quiet           Suppress verbose output
  -e, --env <VAR=val>   Set environment variable (repeatable)
  -v, --volume <spec>   Extra volume mount (repeatable)
  -h, --help            Show this help message

Examples:
  cai shell                    Open shell in default container
  cai shell --fresh            Recreate container and open shell
  cai shell -e DEBUG=1         Open shell with environment variable
EOF
}

_containai_doctor_help() {
    cat <<'EOF'
ContainAI Doctor - Check system capabilities and diagnostics

Usage: cai doctor [options]

Checks Docker availability and Sysbox isolation configuration.
Reports requirement levels and actionable remediation guidance.

Requirements:
  Sysbox: REQUIRED - cai run requires Sysbox for container isolation

Options:
  --json          Output machine-parseable JSON
  -h, --help      Show this help message

Exit Codes:
  0    Sysbox available (ready to use)
  1    Sysbox NOT available (run 'cai setup' to configure)

Examples:
  cai doctor                    Run all checks, show formatted report
  cai doctor --json             Output JSON for scripts/automation
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
    local from_source=""

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
            --from)
                if [[ -z "${2-}" ]]; then
                    echo "[ERROR] --from requires a value" >&2
                    return 1
                fi
                from_source="$2"
                # Expand ~ only for ~ or ~/ (not ~user which would become $HOMEuser)
                if [[ "$from_source" == "~" ]]; then
                    from_source="$HOME"
                elif [[ "$from_source" == "~/"* ]]; then
                    from_source="$HOME/${from_source:2}"
                fi
                shift 2
                ;;
            --from=*)
                from_source="${1#--from=}"
                if [[ -z "$from_source" ]]; then
                    echo "[ERROR] --from requires a value" >&2
                    return 1
                fi
                # Expand ~ only for ~ or ~/ (not ~user which would become $HOMEuser)
                if [[ "$from_source" == "~" ]]; then
                    from_source="$HOME"
                elif [[ "$from_source" == "~/"* ]]; then
                    from_source="$HOME/${from_source:2}"
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
    if ! resolved_workspace=$(cd -- "$resolved_workspace" 2>/dev/null && pwd -P); then
        echo "[ERROR] Workspace path does not exist: ${workspace:-$PWD}" >&2
        return 1
    fi

    # === CONTEXT SELECTION (mirrors cai run in lib/container.sh) ===
    # Resolve secure engine context from config (for context override)
    local config_context_override=""
    if [[ -n "$explicit_config" ]]; then
        # Explicit config: strict mode - fail on parse errors
        if ! config_context_override=$(_containai_resolve_secure_engine_context "$resolved_workspace" "$explicit_config"); then
            echo "[ERROR] Failed to parse config: $explicit_config" >&2
            return 1
        fi
    else
        # Discovered config: suppress errors gracefully
        config_context_override=$(_containai_resolve_secure_engine_context "$resolved_workspace" "" 2>/dev/null) || config_context_override=""
    fi

    # Auto-select Docker context based on Sysbox availability
    # Use DOCKER_CONTEXT= DOCKER_HOST= prefix for shell function call (pitfall: env -u only works with external commands)
    local selected_context=""
    if selected_context=$(DOCKER_CONTEXT= DOCKER_HOST= _cai_select_context "$config_context_override" ""); then
        : # success - selected_context is "containai-secure" (Sysbox)
    else
        # No isolation available - fallback to default context with warning
        echo "[WARN] No isolation available, using default Docker context" >&2
        selected_context=""
    fi

    # Resolve volume
    local resolved_volume
    if ! resolved_volume=$(_containai_resolve_volume "$cli_volume" "$resolved_workspace" "$explicit_config"); then
        echo "[ERROR] Failed to resolve data volume" >&2
        return 1
    fi

    # Clear restore mode flag from any previous run (avoids session pollution)
    unset _CAI_RESTORE_MODE

    # Call import function with context
    if ! _containai_import "$selected_context" "$resolved_volume" "$dry_run" "$no_excludes" "$resolved_workspace" "$explicit_config" "$from_source"; then
        unset _CAI_RESTORE_MODE
        return 1
    fi

    # Import env vars (after dotfile sync, with same context)
    # Skip for restore mode (tgz import) - restore bypasses all host-derived mutations
    if [[ "${_CAI_RESTORE_MODE:-}" != "1" ]]; then
        _containai_import_env "$selected_context" "$resolved_volume" "$resolved_workspace" "$explicit_config" "$dry_run"
    fi

    # Clear restore mode flag after use
    unset _CAI_RESTORE_MODE
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
    if ! resolved_workspace=$(cd -- "$resolved_workspace" 2>/dev/null && pwd -P); then
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

# Sandbox subcommand - DEPRECATED (show migration message)
_containai_sandbox_cmd() {
    _containai_sandbox_help
    _cai_error "The 'cai sandbox' command has been removed"
    _cai_info "Use 'cai stop && cai --restart' to recreate containers"
    return 1
}

# Doctor subcommand handler
_containai_doctor_cmd() {
    local json_output="false"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json)
                json_output="true"
                shift
                ;;
            --help|-h)
                _containai_doctor_help
                return 0
                ;;
            *)
                echo "[ERROR] Unknown option: $1" >&2
                echo "Use 'cai doctor --help' for usage" >&2
                return 1
                ;;
        esac
    done

    # Run doctor checks
    if [[ "$json_output" == "true" ]]; then
        _cai_doctor_json
    else
        _cai_doctor
    fi
}

# Shell subcommand handler - delegates to _containai_start_container with --shell
_containai_shell_cmd() {
    local cli_volume=""
    local workspace=""
    local explicit_config=""
    local container_name=""
    local restart_flag=""
    local fresh_flag=""
    local force_flag=""
    local quiet_flag=""
    local debug_flag=""
    local mount_docker_socket=""
    local please_root_my_host=""
    local allow_host_credentials=""
    local ack_host_credentials=""
    local allow_host_docker_socket=""
    local ack_host_docker_socket=""
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
            --fresh)
                fresh_flag="--fresh"
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
            --allow-host-credentials)
                allow_host_credentials="--allow-host-credentials"
                shift
                ;;
            --i-understand-this-exposes-host-credentials)
                ack_host_credentials="--i-understand-this-exposes-host-credentials"
                shift
                ;;
            --allow-host-docker-socket)
                allow_host_docker_socket="--allow-host-docker-socket"
                shift
                ;;
            --i-understand-this-grants-root-access)
                ack_host_docker_socket="--i-understand-this-grants-root-access"
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
    if ! resolved_workspace=$(cd -- "$resolved_workspace" 2>/dev/null && pwd -P); then
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
    if [[ -n "$fresh_flag" ]]; then
        start_args+=("$fresh_flag")
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
    if [[ -n "$explicit_config" ]]; then
        start_args+=(--config "$explicit_config")
    fi
    if [[ -n "$mount_docker_socket" ]]; then
        start_args+=("$mount_docker_socket")
    fi
    if [[ -n "$please_root_my_host" ]]; then
        start_args+=("$please_root_my_host")
    fi
    if [[ -n "$allow_host_credentials" ]]; then
        start_args+=("$allow_host_credentials")
    fi
    if [[ -n "$ack_host_credentials" ]]; then
        start_args+=("$ack_host_credentials")
    fi
    if [[ -n "$allow_host_docker_socket" ]]; then
        start_args+=("$allow_host_docker_socket")
    fi
    if [[ -n "$ack_host_docker_socket" ]]; then
        start_args+=("$ack_host_docker_socket")
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
    local agent=""
    local image_tag=""
    local credentials=""
    local acknowledge_credential_risk=""
    local allow_host_credentials=""
    local ack_host_credentials=""
    local allow_host_docker_socket=""
    local ack_host_docker_socket=""
    local restart_flag=""
    local fresh_flag=""
    local force_flag=""
    local detached_flag=""
    local quiet_flag=""
    local debug_flag=""
    local mount_docker_socket=""
    local please_root_my_host=""
    local -a env_vars=()
    local -a agent_args=()

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --)
                shift
                agent_args=("$@")
                break
                ;;
            --agent)
                if [[ -z "${2-}" ]]; then
                    echo "[ERROR] --agent requires a value" >&2
                    return 1
                fi
                agent="$2"
                shift 2
                ;;
            --agent=*)
                agent="${1#--agent=}"
                if [[ -z "$agent" ]]; then
                    echo "[ERROR] --agent requires a value" >&2
                    return 1
                fi
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
                acknowledge_credential_risk="--acknowledge-credential-risk"
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
            --fresh)
                fresh_flag="--fresh"
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
            --allow-host-credentials)
                allow_host_credentials="--allow-host-credentials"
                shift
                ;;
            --i-understand-this-exposes-host-credentials)
                ack_host_credentials="--i-understand-this-exposes-host-credentials"
                shift
                ;;
            --allow-host-docker-socket)
                allow_host_docker_socket="--allow-host-docker-socket"
                shift
                ;;
            --i-understand-this-grants-root-access)
                ack_host_docker_socket="--i-understand-this-grants-root-access"
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
            --volume|-v|--volume=*|-v*)
                # FR-4: Extra volume mounts are not allowed in containai run
                # Only workspace + named data volume are permitted
                echo "[ERROR] --volume is not supported in containai run" >&2
                echo "[INFO] FR-4 restricts mounts to workspace + data volume only" >&2
                echo "[INFO] Use 'containai shell' if you need extra mounts" >&2
                return 1
                ;;
            --help|-h)
                _containai_help
                return 0
                ;;
            *)
                # Check if it's a directory path (positional workspace argument)
                if [[ -z "$workspace" && -d "$1" ]]; then
                    workspace="$1"
                    workspace="${workspace/#\~/$HOME}"
                    shift
                else
                    echo "[ERROR] Unknown option: $1" >&2
                    echo "Use 'cai --help' for usage" >&2
                    return 1
                fi
                ;;
        esac
    done

    # Resolve workspace
    local resolved_workspace="${workspace:-$PWD}"
    if ! resolved_workspace=$(cd -- "$resolved_workspace" 2>/dev/null && pwd -P); then
        echo "[ERROR] Workspace path does not exist: ${workspace:-$PWD}" >&2
        return 1
    fi

    # Resolve volume
    local resolved_volume
    if ! resolved_volume=$(_containai_resolve_volume "$cli_volume" "$resolved_workspace" "$explicit_config"); then
        echo "[ERROR] Failed to resolve data volume" >&2
        return 1
    fi

    # Resolve agent (CLI > env > config > default)
    local resolved_agent
    resolved_agent=$(_containai_resolve_agent "$agent" "$resolved_workspace" "$explicit_config")

    # Resolve credentials (CLI > env > config > default)
    # Note: credentials.mode=host is no longer supported (Sysbox-only mode)
    # The 4th parameter is unused but kept for API compatibility
    local resolved_credentials
    resolved_credentials=$(_containai_resolve_credentials "$credentials" "$resolved_workspace" "$explicit_config" "")

    # Build args for _containai_start_container
    local -a start_args=()
    start_args+=(--data-volume "$resolved_volume")
    start_args+=(--workspace "$resolved_workspace")

    # Pass explicit config if provided (for context resolution)
    if [[ -n "$explicit_config" ]]; then
        start_args+=(--config "$explicit_config")
    fi

    # Add volume mismatch warn for implicit volume selection
    if [[ -z "$cli_volume" ]] && [[ -z "$explicit_config" ]]; then
        start_args+=(--volume-mismatch-warn)
    fi

    if [[ -n "$container_name" ]]; then
        start_args+=(--name "$container_name")
    fi
    # Always pass resolved agent
    start_args+=(--agent "$resolved_agent")
    if [[ -n "$image_tag" ]]; then
        start_args+=(--image-tag "$image_tag")
    fi
    # Always pass resolved credentials
    start_args+=(--credentials "$resolved_credentials")
    if [[ -n "$acknowledge_credential_risk" ]]; then
        start_args+=("$acknowledge_credential_risk")
    fi
    if [[ -n "$restart_flag" ]]; then
        start_args+=("$restart_flag")
    fi
    if [[ -n "$fresh_flag" ]]; then
        start_args+=("$fresh_flag")
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
    if [[ -n "$allow_host_credentials" ]]; then
        start_args+=("$allow_host_credentials")
    fi
    if [[ -n "$ack_host_credentials" ]]; then
        start_args+=("$ack_host_credentials")
    fi
    if [[ -n "$allow_host_docker_socket" ]]; then
        start_args+=("$allow_host_docker_socket")
    fi
    if [[ -n "$ack_host_docker_socket" ]]; then
        start_args+=("$ack_host_docker_socket")
    fi
    local env_var
    for env_var in "${env_vars[@]}"; do
        start_args+=(--env "$env_var")
    done

    # FR-4: No extra volume mounts allowed (only workspace + data volume)
    # --volume is rejected during argument parsing

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
        run)
            shift
            _containai_run_cmd "$@"
            ;;
        shell)
            shift
            _containai_shell_cmd "$@"
            ;;
        doctor)
            shift
            _containai_doctor_cmd "$@"
            ;;
        setup)
            shift
            _cai_setup "$@"
            ;;
        validate)
            shift
            _cai_secure_engine_validate "$@"
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
        sandbox)
            shift
            _containai_sandbox_cmd "$@"
            ;;
        version)
            shift
            _cai_version "$@"
            ;;
        update)
            shift
            _cai_update "$@"
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
