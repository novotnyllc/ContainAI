#!/usr/bin/env bash
# ==============================================================================
# Shell aliases for agent-sandbox
# ==============================================================================
# Provides:
#   asb           - Agent Sandbox: start/attach to sandbox container
#   asbd          - Agent Sandbox: start detached sandbox container
#   asbs          - Agent Sandbox: start sandbox with shell (alias: asb-shell)
#   asb-stop-all  - Interactive selection to stop sandbox containers
#
# Usage: source aliases.sh
# ==============================================================================
# Note: No strict mode - this file is sourced into interactive shells

# Constants

_ASB_IMAGE="agent-sandbox:latest"
_ASB_LABEL="asb.sandbox=agent-sandbox"
_ASB_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default volume name (can be overridden via config)
_CONTAINAI_DEFAULT_VOLUME="sandbox-agent-data"

# Volumes that asb creates/ensures (per spec)
_ASB_VOLUMES=(
        "sandbox-agent-data:/mnt/agent-data"
)

# ==============================================================================
# Config loading functions for ContainAI
# ==============================================================================

# Validate Docker volume name pattern
# Pattern: ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$
# Length: 1-255 characters
# Returns: 0=valid, 1=invalid
_containai_validate_volume_name() {
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

# Find config file by walking up from workspace path
# Checks: .containai/config.toml then falls back to XDG_CONFIG_HOME
# Arguments: $1 = workspace path (default: $PWD)
# Outputs: config file path (or empty if not found)
_containai_find_config() {
    local workspace="${1:-$PWD}"
    local dir config_file

    # Resolve workspace to absolute path
    dir=$(cd "$workspace" 2>/dev/null && pwd) || dir="$PWD"

    # Walk up directory tree looking for .containai/config.toml
    while [[ "$dir" != "/" ]]; do
        config_file="$dir/.containai/config.toml"
        if [[ -f "$config_file" ]]; then
            printf '%s' "$config_file"
            return 0
        fi

        # Check for git root (stop walking up after git root)
        if [[ -d "$dir/.git" ]]; then
            break
        fi

        dir=$(dirname "$dir")
    done

    # Check root directory
    if [[ -f "/.containai/config.toml" ]]; then
        printf '%s' "/.containai/config.toml"
        return 0
    fi

    # Fall back to XDG_CONFIG_HOME
    local xdg_config="${XDG_CONFIG_HOME:-$HOME/.config}"
    config_file="$xdg_config/containai/config.toml"
    if [[ -f "$config_file" ]]; then
        printf '%s' "$config_file"
        return 0
    fi

    # Not found
    return 0
}

# Parse config file for workspace matching
# Calls parse-toml.py with workspace matching mode
# Arguments: $1 = config file, $2 = workspace path, $3 = config dir
# Outputs: data_volume value (or empty if not found)
_containai_parse_config_for_workspace() {
    local config_file="$1"
    local workspace="$2"
    local config_dir="$3"
    local script_dir result

    # Check if Python available
    if ! command -v python3 >/dev/null 2>&1; then
        echo "[WARN] Python not found, cannot parse config. Using default." >&2
        return 0
    fi

    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    # Call parse-toml.py in workspace matching mode
    result=$(python3 "$script_dir/parse-toml.py" "$config_file" --workspace "$workspace" --config-dir "$config_dir" 2>/dev/null)

    printf '%s' "$result"
}

# Main volume resolver - determines the data volume to use
# Arguments: $1 = CLI --data-volume value (optional)
#            $2 = workspace path (default: $PWD)
#            $3 = explicit config path (optional)
# Outputs: volume name
# Precedence:
#   1. --data-volume CLI flag (skips config parsing entirely)
#   2. CONTAINAI_DATA_VOLUME env var (skips config parsing entirely)
#   3. Config file [workspace.<path>] section matching workspace
#   4. Config file [agent].data_volume
#   5. Default: sandbox-agent-data
_containai_resolve_volume() {
    local cli_volume="${1:-}"
    local workspace="${2:-$PWD}"
    local explicit_config="${3:-}"
    local config_file config_dir volume

    # 1. CLI flag always wins - SKIP all config parsing
    if [[ -n "$cli_volume" ]]; then
        # Validate volume name
        if ! _containai_validate_volume_name "$cli_volume"; then
            echo "[ERROR] Invalid volume name: $cli_volume" >&2
            return 1
        fi
        printf '%s' "$cli_volume"
        return 0
    fi

    # 2. Environment variable always wins - SKIP all config parsing
    if [[ -n "${CONTAINAI_DATA_VOLUME:-}" ]]; then
        # Validate volume name
        if ! _containai_validate_volume_name "$CONTAINAI_DATA_VOLUME"; then
            echo "[ERROR] Invalid volume name in CONTAINAI_DATA_VOLUME: $CONTAINAI_DATA_VOLUME" >&2
            return 1
        fi
        printf '%s' "$CONTAINAI_DATA_VOLUME"
        return 0
    fi

    # 3. Resolve workspace to absolute path
    workspace=$(cd "$workspace" 2>/dev/null && pwd) || workspace="$PWD"

    # 4. Find config file
    if [[ -n "$explicit_config" ]]; then
        if [[ ! -f "$explicit_config" ]]; then
            echo "[ERROR] Config file not found: $explicit_config" >&2
            return 1
        fi
        config_file="$explicit_config"
        config_dir=$(dirname "$config_file")
    else
        config_file=$(_containai_find_config "$workspace")
        if [[ -n "$config_file" ]]; then
            config_dir=$(dirname "$config_file")
        fi
    fi

    # 5. Parse config with workspace matching
    if [[ -n "$config_file" ]]; then
        volume=$(_containai_parse_config_for_workspace "$config_file" "$workspace" "$config_dir")
        if [[ -n "$volume" ]]; then
            # Validate volume name from config
            if ! _containai_validate_volume_name "$volume"; then
                echo "[ERROR] Invalid volume name in config: $volume" >&2
                return 1
            fi
            printf '%s' "$volume"
            return 0
        fi
    fi

    # 6. Default
    printf '%s' "$_CONTAINAI_DEFAULT_VOLUME"
}


# Generate sanitized container name from git repo/branch or directory
_asb_container_name() {
    local name

    # Guard git usage to avoid "command not found" noise in minimal environments
    if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        local repo_name branch_name
        repo_name="$(basename "$(git rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null)"

        # Check for detached HEAD
        if git symbolic-ref -q HEAD >/dev/null 2>&1; then
            branch_name="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
        else
            # Detached HEAD - use short SHA
            branch_name="detached-$(git rev-parse --short HEAD 2>/dev/null)"
        fi

        name="${repo_name}-${branch_name}"
    else
        # Fall back to current directory name
        name="$(basename "$(pwd)")"
    fi

    # Sanitize: lowercase, replace non-alphanumeric with dash, collapse repeated dashes
    # Use sed 's/--*/-/g' for POSIX portability (BSD/macOS compatible)
    name="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g')"

    # Strip leading/trailing dashes
    name="$(printf '%s' "$name" | sed 's/^-*//;s/-*$//')"

    # Handle empty or dash-only names
    if [[ -z "$name" || "$name" =~ ^-+$ ]]; then
        name="sandbox-$(basename "$(pwd)" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-*//;s/-*$//')"
    fi

    # Truncate to 63 characters (Docker limit)
    name="${name:0:63}"

    # Final cleanup of trailing dashes from truncation
    name="$(printf '%s' "$name" | sed 's/-*$//')"

    # Final fallback if name became empty after all processing
    # Use sandbox-<dirname> pattern, not generic sandbox-container
    # Apply same sanitization as main path for consistency
    if [[ -z "$name" ]]; then
        local dir_fallback
        dir_fallback="$(basename "$(pwd)")"
        # Sanitize: lowercase, replace non-alphanumeric with dash, collapse dashes
        dir_fallback="$(printf '%s' "$dir_fallback" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-*//;s/-*$//')"
        if [[ -n "$dir_fallback" ]]; then
            name="sandbox-$dir_fallback"
            # Truncate to 63 characters (Docker limit)
            name="${name:0:63}"
            name="$(printf '%s' "$name" | sed 's/-*$//')"
        else
            name="sandbox-default"
        fi
    fi

    printf '%s' "$name"
}

# Container isolation detection (conservative - prefer return 2 over false positive/negative)
# Returns: 0=isolated (detected), 1=not isolated (definite), 2=unknown (ambiguous)
_asb_check_isolation() {
    local runtime rootless userns

    runtime=$(docker info --format '{{.DefaultRuntime}}' 2>/dev/null)
    if [[ $? -ne 0 ]] || [[ -z "$runtime" ]]; then
        echo "[WARN] Unable to determine isolation status" >&2
        return 2
    fi

    rootless=$(docker info --format '{{.Rootless}}' 2>/dev/null)
    userns=$(docker info --format '{{.SecurityOptions}}' 2>/dev/null)

    # ECI enabled - sysbox-runc runtime
    if [[ "$runtime" == "sysbox-runc" ]]; then
        return 0
    fi

    # Rootless mode
    if [[ "$rootless" == "true" ]]; then
        return 0
    fi

    # User namespace remapping enabled
    if echo "$userns" | grep -q "userns"; then
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

# Check if docker sandbox is available
# Returns: 0=yes, 1=no (definite), 2=unknown (fail-open with warning)
_asb_check_sandbox() {
    if ! command -v docker >/dev/null 2>&1; then
        echo "[ERROR] Docker is not installed or not in PATH" >&2
        return 1
    fi

    # Check if sandbox command is available by trying to run it
    # Capture both stdout and stderr for proper error analysis
    local ls_output ls_rc
    ls_output="$(docker sandbox ls 2>&1)"
    ls_rc=$?

    if [[ $ls_rc -eq 0 ]]; then
        return 0
    fi

    # Sandbox ls failed - analyze the error to provide actionable feedback
    # Check for feature disabled / requirements not met FIRST (before empty list check)
    # Match broad patterns per spec, but exclude "no sandbox" empty list messages
    if printf '%s' "$ls_output" | grep -qiE "feature.*disabled|not enabled|requirements.*not met|sandbox.*unavailable" && \
       ! printf '%s' "$ls_output" | grep -qiE "no sandboxes"; then
        echo "[ERROR] Docker sandbox feature is not enabled" >&2
        echo "" >&2
        echo "  docker sandbox ls output:" >&2
        printf '%s\n' "$ls_output" | sed 's/^/    /' >&2
        echo "" >&2
        echo "Please enable sandbox in Docker Desktop:" >&2
        echo "  Settings > Features in development > Docker sandbox" >&2
        echo "  See: https://docs.docker.com/desktop/features/sandbox/" >&2
        echo "" >&2
        return 1
    fi

    # Check for "no sandboxes exist" case - only treat as success if exit code was 0
    # (handled above) or if message clearly indicates functional sandbox support
    # With non-zero exit, treat as unknown to be safe
    if printf '%s' "$ls_output" | grep -qiE "no sandboxes found|0 sandboxes|sandbox list is empty"; then
        # Non-zero exit with empty list message - treat as unknown, not success
        echo "[WARN] docker sandbox ls returned empty list with error code" >&2
        echo "  Attempting to proceed - sandbox may be functional." >&2
        echo "" >&2
        return 2
    fi

    # Check for command not found / not available errors (definite "no")
    if printf '%s' "$ls_output" | grep -qiE "not recognized|unknown command|not a docker command|command not found"; then
        echo "[ERROR] Docker sandbox is not available" >&2
        echo "" >&2
        echo "  docker sandbox ls output:" >&2
        printf '%s\n' "$ls_output" | sed 's/^/    /' >&2
        echo "" >&2
        echo "Docker sandbox requires Docker Desktop 4.50+ with sandbox feature enabled." >&2
        echo "Please ensure you have:" >&2
        echo "  1. Docker Desktop 4.50 or later installed" >&2
        echo "  2. Docker sandbox feature enabled in Settings > Features in development" >&2
        echo "  See: https://docs.docker.com/desktop/features/sandbox/" >&2
        echo "" >&2
        return 1
    fi

    # Check for permission denied (separate from daemon not running)
    if printf '%s' "$ls_output" | grep -qiE "permission denied"; then
        echo "[ERROR] Permission denied accessing Docker" >&2
        echo "" >&2
        echo "  docker sandbox ls output:" >&2
        printf '%s\n' "$ls_output" | sed 's/^/    /' >&2
        echo "" >&2
        echo "Please ensure Docker is accessible:" >&2
        echo "  Docker Desktop (macOS/Windows): Ensure Docker Desktop is running and try restarting it" >&2
        echo "  Linux: Add your user to the 'docker' group: sudo usermod -aG docker \$USER" >&2
        echo "         Then log out and back in, or run: newgrp docker" >&2
        echo "" >&2
        return 1
    fi

    # Check for daemon not running (tighter match, excludes permission denied)
    if printf '%s' "$ls_output" | grep -qiE "daemon.*not running|connection refused|Is the docker daemon running"; then
        echo "[ERROR] Docker daemon is not running" >&2
        echo "" >&2
        echo "  docker sandbox ls output:" >&2
        printf '%s\n' "$ls_output" | sed 's/^/    /' >&2
        echo "" >&2
        echo "Please start Docker Desktop and try again." >&2
        echo "" >&2
        return 1
    fi

    # Unknown error - fail OPEN with warning (per spec: don't block on unknown)
    echo "[WARN] Could not verify Docker sandbox availability" >&2
    echo "" >&2
    echo "  docker sandbox ls output:" >&2
    printf '%s\n' "$ls_output" | sed 's/^/    /' >&2
    echo "" >&2
    echo "  Attempting to proceed - sandbox run may fail if not available." >&2
    echo "  Ensure Docker Desktop 4.50+ is installed with sandbox feature enabled." >&2
    echo "  See: https://docs.docker.com/desktop/features/sandbox/" >&2
    echo "" >&2
    return 2  # Unknown - proceed with warning
}

# Preflight checks for sandbox/isolation before container start
# Returns: 0=proceed, 1=block
_asb_preflight_checks() {
    local force_flag="$1"
    local sandbox_rc isolation_rc

    if [[ "$force_flag" == "true" ]]; then
        echo "[WARN] Skipping sandbox availability check (--force)" >&2
        # Handle ASB_REQUIRE_ISOLATION with --force bypass
        if [[ "${ASB_REQUIRE_ISOLATION:-0}" == "1" ]]; then
            echo "*** WARNING: Bypassing isolation requirement with --force" >&2
            echo "*** Running without verified isolation may expose host system" >&2
        fi
        return 0
    fi

    _asb_check_sandbox
    sandbox_rc=$?
    if [[ $sandbox_rc -eq 1 ]]; then
        return 1  # Definite "no" - block
    fi
    # rc=0 (yes) or rc=2 (unknown) - proceed

    # Best-effort isolation detection
    _asb_check_isolation
    isolation_rc=$?

    # Handle ASB_REQUIRE_ISOLATION environment variable
    if [[ "${ASB_REQUIRE_ISOLATION:-0}" == "1" ]]; then
        case $isolation_rc in
            0)
                # Isolated - proceed normally
                ;;
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

# Get the asb.sandbox label value from a container (empty if not found)
_asb_get_container_label() {
    local container_name="$1"
    docker inspect --format '{{ index .Config.Labels "asb.sandbox" }}' "$container_name" 2>/dev/null || echo ""
}

# Get the image name of a container
_asb_get_container_image() {
    local container_name="$1"
    docker inspect --format '{{.Config.Image}}' "$container_name" 2>/dev/null || echo ""
}

# Verify container was created by asb (has our label or uses our image)
# Returns: 0=ours (label or image matches), 1=foreign (no match)
# Falls back to image name verification if labels not supported
_asb_is_our_container() {
    local container_name="$1"
    local label_value
    label_value="$(_asb_get_container_label "$container_name")"

    # Primary check: label match
    if [[ "$label_value" == "agent-sandbox" ]]; then
        return 0
    fi

    # Fallback: if no label, check if container uses our image
    # This handles cases where docker sandbox run doesn't support --label
    # or containers created before label support was added
    if [[ -z "$label_value" || "$label_value" == "<no value>" ]]; then
        local image_name
        image_name="$(_asb_get_container_image "$container_name")"
        if [[ "$image_name" == "$_ASB_IMAGE" ]]; then
            # Image matches - trust it as ours
            return 0
        fi
    fi

    return 1  # Definitely foreign
}

# Check container ownership with appropriate messaging
# Returns: 0=owned, 1=foreign (with error)
_asb_check_container_ownership() {
    local container_name="$1"

    if _asb_is_our_container "$container_name"; then
        return 0
    fi

    # Foreign container
    local actual_label actual_image
    actual_label="$(_asb_get_container_label "$container_name")"
    actual_image="$(_asb_get_container_image "$container_name")"
    # Normalize empty or "<no value>" to "<not set>"
    if [[ -z "$actual_label" || "$actual_label" == "<no value>" ]]; then
        actual_label="<not set>"
    fi
    echo "[ERROR] Container '$container_name' exists but was not created by asb" >&2
    echo "" >&2
    echo "  Expected label 'asb.sandbox': agent-sandbox" >&2
    echo "  Actual label 'asb.sandbox':   ${actual_label:-<not set>}" >&2
    echo "  Expected image:               $_ASB_IMAGE" >&2
    echo "  Actual image:                 ${actual_image:-<unknown>}" >&2
    echo "" >&2
    echo "This is a name collision with a container not managed by asb." >&2
    echo "To recreate as an asb-managed sandbox container, run: asb --restart" >&2
    echo "" >&2
    return 1
}

# Ensure required volumes exist with correct permissions
# Returns non-zero on failure
_asb_ensure_volumes() {
    local volume_name vol_spec



    # Create asb-managed volumes if missing
    for vol_spec in "${_ASB_VOLUMES[@]}"; do
        volume_name="${vol_spec%%:*}"

        if ! docker volume inspect "$volume_name" >/dev/null 2>&1; then
            echo "Creating volume: $volume_name"
            if ! docker volume create "$volume_name" >/dev/null; then
                echo "[ERROR] Failed to create volume $volume_name" >&2
                return 1
            fi
        fi
    done


}

# Print help for asb/asbd
_asb_print_help() {
    local show_detached="$1"
    local show_shell="$2"
    echo "Usage: asb [options] -- [claude-options]"
    echo ""
    echo "Start a Claude Code instance inside a Docker sandbox with access to a host workspace."
    echo ""
    echo "By default, launches Claude Code interactively. Use --shell to get a bash shell instead."
    echo "Claude-specific options can be passed after '--'."
    echo "If no workspace is specified via the \"--workspace\" option, the current working directory is used."
    echo "The workspace is exposed inside the sandbox at the same path as on the host."
    echo ""
    echo "Options:"
    echo "  -D, --debug                 Enable debug logging"
    if [[ "$show_detached" == "true" ]]; then
        echo "  -d, --detached              Create sandbox without running agent interactively"
    fi
    echo "  -e, --env strings           Set environment variables (format: KEY=VALUE)"
    echo "      --mount-docker-socket   Mount the host's Docker socket into the sandbox (DANGEROUS)"
    echo "      --name string           Name for the sandbox (default: <repo>-<branch>)"
    echo "  -q, --quiet                 Suppress verbose output"
    echo "      --restart               Force recreate container even if running"
    if [[ "$show_shell" == "true" ]]; then
        echo "      --shell                 Start with interactive shell instead of agent"
    fi
    echo "      --force                 Skip sandbox availability check (not recommended)"
    echo "  -v, --volume strings        Bind mount a volume or host file or directory into the sandbox"
    echo "                              (format: hostpath:sandboxpath[:readonly|:ro])"
    echo "  -w, --workspace string      Workspace path (default \".\")"
    echo "  -h, --help                  Show this help"
}

# Agent Sandbox - main function
asb() {
    local restart_flag=false
    local force_flag=false
    local container_name=""
    local detached_flag=false
    local shell_flag=false
    local debug_flag=false
    local quiet_flag=false
    local mount_docker_socket=false
    local please_root_my_host=false
    local workspace=""
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
            --restart)
                restart_flag=true
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
            --debug|-D)
                debug_flag=true
                shift
                ;;
            --quiet|-q)
                quiet_flag=true
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
                shift 2
                ;;
            --workspace=*)
                workspace="${1#--workspace=}"
                shift
                ;;
            -w*)
                workspace="${1#-w}"
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
                _asb_print_help true true
                return 0
                ;;
            *)
                echo "[ERROR] Unknown option: $1" >&2
                echo "Use 'asb --help' for usage" >&2
                return 1
                ;;
        esac
    done

    # Safety check for --mount-docker-socket
    if [[ "$mount_docker_socket" == "true" && "$please_root_my_host" != "true" ]]; then
        echo "" >&2
        echo "╔══════════════════════════════════════════════════════════════════════════════╗" >&2
        echo "║                      🚨 ⚠️  DANGER: HOST ROOT ACCESS  ⚠️ 🚨                   ║" >&2
        echo "╠══════════════════════════════════════════════════════════════════════════════╣" >&2
        echo "║                                                                              ║" >&2
        echo "║  Mounting the Docker socket grants FULL ROOT ACCESS to your host system.     ║" >&2
        echo "║                                                                              ║" >&2
        echo "║  Any process in the container can:                                           ║" >&2
        echo "║    • Create privileged containers that escape all isolation                  ║" >&2
        echo "║    • Mount and modify ANY file on the host (including /etc/shadow)           ║" >&2
        echo "║    • Access all other containers, images, volumes, and networks              ║" >&2
        echo "║    • Install rootkits or persistent backdoors on the host                    ║" >&2
        echo "║    • Exfiltrate sensitive data from the host filesystem                      ║" >&2
        echo "║                                                                              ║" >&2
        echo "║  This COMPLETELY DEFEATS the purpose of running in a sandbox.                ║" >&2
        echo "║                                                                              ║" >&2
        echo "║  If you understand and accept these risks, add:                              ║" >&2
        echo "║                                                                              ║" >&2
        echo "║      --please-root-my-host                                                   ║" >&2
        echo "║                                                                              ║" >&2
        echo "╚══════════════════════════════════════════════════════════════════════════════╝" >&2
        echo "" >&2
        return 1
    fi

    # Early prereq check: is docker available?
    # This ensures docker errors get routed through our messaging
    if ! command -v docker >/dev/null 2>&1; then
        echo "[ERROR] Docker is not installed or not in PATH" >&2
        return 1
    fi

    # Get container name (use provided or generate default)
    if [[ -z "$container_name" ]]; then
        container_name="$(_asb_container_name)"
    fi
    if [[ "$quiet_flag" != "true" ]]; then
        echo "Container: $container_name"
    fi

    # Check container state (distinguish not-found from actual errors)
    local container_state container_inspect_output container_inspect_rc
    container_inspect_output="$(docker inspect --format '{{.State.Status}}' "$container_name" 2>&1)"
    container_inspect_rc=$?
    if [[ $container_inspect_rc -eq 0 ]]; then
        container_state="$container_inspect_output"
    elif printf '%s' "$container_inspect_output" | grep -qiE "no such object|not found|error.*no such"; then
        container_state="none"
    else
        # Docker error - route through sandbox check for actionable messaging
        # This handles daemon down, permission denied, etc.
        local sandbox_check_rc
        _asb_check_sandbox
        sandbox_check_rc=$?
        if [[ $sandbox_check_rc -eq 1 ]]; then
            return 1  # Definite failure - sandbox check already printed error
        fi
        # rc=0 (ok) or rc=2 (unknown) - sandbox might work, surface the original error
        echo "$container_inspect_output" >&2
        return 1
    fi

    # Handle --restart flag
    if [[ "$restart_flag" == "true" && "$container_state" != "none" ]]; then
        # Check ownership before removing - prevent accidentally deleting foreign containers
        if ! _asb_is_our_container "$container_name"; then
            # Foreign container - block
            local actual_label actual_image
            actual_label="$(_asb_get_container_label "$container_name")"
            actual_image="$(_asb_get_container_image "$container_name")"
            if [[ -z "$actual_label" || "$actual_label" == "<no value>" ]]; then
                actual_label="<not set>"
            fi
            echo "[ERROR] Cannot restart - container '$container_name' was not created by asb" >&2
            echo "" >&2
            echo "  Expected label 'asb.sandbox': agent-sandbox" >&2
            echo "  Actual label 'asb.sandbox':   $actual_label" >&2
            echo "  Expected image:               $_ASB_IMAGE" >&2
            echo "  Actual image:                 ${actual_image:-<unknown>}" >&2
            echo "" >&2
            echo "To avoid data loss, asb will not delete containers it didn't create." >&2
            echo "Remove the conflicting container manually if needed:" >&2
            echo "  docker rm -f '$container_name'" >&2
            echo "" >&2
            return 1
        fi

        if [[ "$quiet_flag" != "true" ]]; then
            echo "Stopping existing container..."
        fi
        # Let errors surface for stop (only ignore "not running")
        local stop_output
        stop_output="$(docker stop "$container_name" 2>&1)" || {
            if ! printf '%s' "$stop_output" | grep -qiE "is not running"; then
                echo "$stop_output" >&2
            fi
        }
        # Let errors surface for rm (only ignore "not found")
        local rm_output
        rm_output="$(docker rm "$container_name" 2>&1)" || {
            if ! printf '%s' "$rm_output" | grep -qiE "no such container|not found"; then
                echo "$rm_output" >&2
                return 1
            fi
        }
        container_state="none"
    fi

    # Handle stopped container + shell mode: must recreate to use sandbox run
    # (docker start doesn't provide sandbox isolation)
    if [[ "$shell_flag" == "true" ]] && [[ "$container_state" == "exited" || "$container_state" == "created" ]]; then
        if ! _asb_check_container_ownership "$container_name"; then
            return 1
        fi
        if ! _asb_preflight_checks "$force_flag"; then
            return 1
        fi
        if [[ "$quiet_flag" != "true" ]]; then
            echo "Recreating container for shell access..."
        fi
        docker rm "$container_name" >/dev/null 2>&1
        container_state="none"
    fi

    # Check if image exists only when we need to create a new container
    if [[ "$container_state" == "none" ]]; then
        local inspect_output inspect_rc
        inspect_output="$(docker image inspect "$_ASB_IMAGE" 2>&1)"
        inspect_rc=$?
        if [[ $inspect_rc -ne 0 ]]; then
            # Check if it's "not found" vs other errors (daemon down, etc.)
            if printf '%s' "$inspect_output" | grep -qiE "no such image|not found"; then
                echo "[ERROR] Image '$_ASB_IMAGE' not found" >&2
                echo "Please build the image first: ${_ASB_SCRIPT_DIR}/build.sh" >&2
            else
                # Let actual docker error surface
                echo "$inspect_output" >&2
            fi
            return 1
        fi
    fi

    case "$container_state" in
        running)
            # Verify this container was created by asb (has our label or image)
            if ! _asb_check_container_ownership "$container_name"; then
                return 1
            fi
            # Warn if sandbox unavailable (non-blocking for running containers)
            local sandbox_rc
            _asb_check_sandbox
            sandbox_rc=$?
            if [[ $sandbox_rc -eq 1 ]] && [[ "$force_flag" != "true" ]]; then
                # Definite unavailability - warn but proceed since container exists
                echo "[WARN] Sandbox unavailable but attaching to existing container" >&2
                echo "  Use --force to suppress this warning, or --restart to recreate as sandbox" >&2
                echo "" >&2
            fi
            # rc=0 or rc=2: no warning needed (sandbox available or status unknown)
            if [[ "$quiet_flag" != "true" ]]; then
                echo "Attaching to running container..."
            fi
            # NOTE: Using docker exec (not docker sandbox exec) is intentional.
            # Docker Desktop sandboxes are regular containers accessible via standard docker commands.
            # The sandbox provides isolation at creation time; exec/start work normally.
            docker exec -it --user agent -w /home/agent/workspace "$container_name" bash
            ;;
        exited|created)
            # Note: shell mode with stopped containers is handled before this case statement
            # Verify this container was created by asb (has our label or image)
            if ! _asb_check_container_ownership "$container_name"; then
                return 1
            fi
            # Check sandbox availability before starting
            if ! _asb_preflight_checks "$force_flag"; then
                return 1
            fi
            if [[ "$quiet_flag" != "true" ]]; then
                echo "Starting stopped container..."
            fi
            docker start -ai "$container_name"
            ;;
        none)
            # Check sandbox availability before creating new container
            if ! _asb_preflight_checks "$force_flag"; then
                return 1
            fi

            # Ensure volumes exist (asb-managed)
            if ! _asb_ensure_volumes; then
                echo "[ERROR] Volume setup failed. Cannot start container." >&2
                return 1
            fi

            # Build volume arguments (asb-managed volumes)
            local vol_args=() vol_spec
            for vol_spec in "${_ASB_VOLUMES[@]}"; do
                vol_args+=("-v" "$vol_spec")
            done

            # Get sandbox run help to check supported flags
            local sandbox_help sandbox_help_rc
            sandbox_help="$(docker sandbox run --help 2>&1)"
            sandbox_help_rc=$?

            # Check if sandbox run help failed (indicates sandbox unavailable)
            if [[ $sandbox_help_rc -ne 0 ]]; then
                echo "[ERROR] docker sandbox run is not available" >&2
                echo "" >&2
                echo "  docker sandbox run --help output:" >&2
                printf '%s\n' "$sandbox_help" | sed 's/^/    /' >&2
                echo "" >&2
                echo "Please ensure Docker Desktop 4.50+ with sandbox feature is enabled." >&2
                return 1
            fi

            if [[ "$quiet_flag" != "true" ]]; then
                echo "Starting new sandbox container..."
            fi

            # Build docker sandbox run arguments
            local args=()
            args+=(--name "$container_name")

            # Add label if supported
            if printf '%s' "$sandbox_help" | grep -q -- '--label'; then
                args+=(--label "$_ASB_LABEL")
            fi

            # Add volumes
            args+=("${vol_args[@]}")

            # Add extra user volumes
            local vol
            for vol in "${extra_volumes[@]}"; do
                args+=(-v "$vol")
            done

            # Add environment variables
            local env_var
            for env_var in "${env_vars[@]}"; do
                args+=(-e "$env_var")
            done

            # Add optional flags
            if [[ "$shell_flag" == "true" ]]; then
                # Shell mode: always run detached and quiet
                args+=(--detached)
                args+=(--quiet)
            else
                if [[ "$detached_flag" == "true" ]]; then
                    args+=(--detached)
                fi
                if [[ "$quiet_flag" == "true" ]]; then
                    args+=(--quiet)
                fi
            fi
            if [[ "$debug_flag" == "true" ]]; then
                args+=(--debug)
            fi
            if [[ "$mount_docker_socket" == "true" ]]; then
                args+=(--mount-docker-socket)
            fi
            if [[ -n "$workspace" ]]; then
                args+=(--workspace "$workspace")
            fi

            args+=(--template "$_ASB_IMAGE")
            args+=(--credentials none)
            args+=(claude)

            # Add agent arguments if any
            if [[ ${#agent_args[@]} -gt 0 ]]; then
                args+=("${agent_args[@]}")
            fi

            if [[ "$shell_flag" == "true" ]]; then
                # Shell mode: run detached, capture container ID, then exec bash
                local container_id
                container_id=$(docker sandbox run "${args[@]}")
                docker exec -it --user agent -w /home/agent/workspace "$container_id" bash
            else
                docker sandbox run "${args[@]}"
            fi

            ;;
        *)
            echo "[ERROR] Unexpected container state: $container_state" >&2
            return 1
            ;;
    esac
}

# Interactive container stop selection
asb-stop-all() {
    local containers labeled_containers ancestor_containers

    # Find containers by label (preferred, works across rebuilds)
    labeled_containers=$(docker ps -a --filter "label=$_ASB_LABEL" --format "{{.Names}}\t{{.Status}}" 2>/dev/null || true)

    # Also find by ancestor image (catches pre-label containers)
    ancestor_containers=$(docker ps -a --filter "ancestor=$_ASB_IMAGE" --format "{{.Names}}\t{{.Status}}" 2>/dev/null || true)

    # Combine and deduplicate (sort -u on first field)
    containers=$(printf '%s\n%s' "$labeled_containers" "$ancestor_containers" | grep -v '^$' | sort -t$'\t' -k1,1 -u)

    if [[ -z "$containers" ]]; then
        echo "No agent-sandbox containers found."
        return 0
    fi

    echo "Agent Sandbox containers:"
    echo ""

    local i=0
    local names=()
    local name status
    while IFS=$'\t' read -r name status; do
        i=$((i + 1))
        names+=("$name")
        printf "  %d) %s (%s)\n" "$i" "$name" "$status"
    done <<< "$containers"

    echo ""
    echo "Enter numbers to stop (space-separated), 'all', or 'q' to quit:"
    local selection
    read -r selection

    if [[ "$selection" == "q" || "$selection" == "Q" ]]; then
        echo "Cancelled."
        return 0
    fi

    local to_stop=()

    if [[ "$selection" == "all" || "$selection" == "ALL" ]]; then
        to_stop=("${names[@]}")
    else
        local num
        for num in $selection; do
            if [[ "$num" =~ ^[0-9]+$ ]] && [[ "$num" -ge 1 ]] && [[ "$num" -le "${#names[@]}" ]]; then
                to_stop+=("${names[$((num - 1))]}")
            else
                echo "[WARN] Invalid selection: $num" >&2
            fi
        done
    fi

    if [[ ${#to_stop[@]} -eq 0 ]]; then
        echo "No containers selected."
        return 0
    fi

    echo ""
    local container_to_stop
    for container_to_stop in "${to_stop[@]}"; do
        echo "Stopping: $container_to_stop"
        docker stop "$container_to_stop" >/dev/null 2>&1 || true
    done

    echo "Done."
}

# Agent Sandbox Detached - wrapper that always runs detached
asbd() {
    # Check for help flag first
    local arg
    for arg in "$@"; do
        if [[ "$arg" == "--help" || "$arg" == "-h" ]]; then
            _asb_print_help false true
            return 0
        fi
    done
    # Pass all args to asb with --detached
    asb --detached "$@"
}

# Print help for asb-shell/asbs
_asb_shell_print_help() {
    echo "Usage: asb-shell [options]"
    echo ""
    echo "Start a Docker sandbox and open an interactive bash shell."
    echo ""
    echo "Claude Code runs in the background; use 'claude' to interact with it."
    echo "If no workspace is specified via the \"--workspace\" option, the current working directory is used."
    echo "The workspace is exposed inside the sandbox at the same path as on the host."
    echo ""
    echo "Options:"
    echo "  -D, --debug                 Enable debug logging"
    echo "  -e, --env strings           Set environment variables (format: KEY=VALUE)"
    echo "      --mount-docker-socket   Mount the host's Docker socket into the sandbox (DANGEROUS)"
    echo "      --name string           Name for the sandbox (default: <repo>-<branch>)"
    echo "  -q, --quiet                 Suppress verbose output"
    echo "      --restart               Force recreate container even if running"
    echo "      --force                 Skip sandbox availability check (not recommended)"
    echo "  -v, --volume strings        Bind mount a volume or host file or directory into the sandbox"
    echo "                              (format: hostpath:sandboxpath[:readonly|:ro])"
    echo "  -w, --workspace string      Workspace path (default \".\")"
    echo "  -h, --help                  Show this help"
}

# Agent Sandbox Shell - start sandbox with interactive shell
asb-shell() {
    # Check for help flag first
    local arg
    for arg in "$@"; do
        if [[ "$arg" == "--help" || "$arg" == "-h" ]]; then
            _asb_shell_print_help
            return 0
        fi
    done
    # Pass all args to asb with --shell
    asb --shell "$@"
}

# Alias: asbs = asb-shell
asbs() {
    asb-shell "$@"
}

# Return 0 when sourced, exit 1 when executed directly
return 0 2>/dev/null || { echo "This script should be sourced, not executed: source aliases.sh" >&2; exit 1; }
