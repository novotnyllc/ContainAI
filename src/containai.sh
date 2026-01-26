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
#   setup        Configure secure container isolation (Linux/WSL2/macOS)
#   validate     Validate Secure Engine configuration
#   docker       Run docker with ContainAI context (defaults to containai-docker if present)
#   sandbox      (Deprecated - use 'cai stop && cai --restart')
#   import       Sync host configs to data volume
#   export       Export data volume to .tgz archive
#   stop         Stop ContainAI containers
#   version      Show current version
#   update       Update ContainAI installation
#   uninstall    Clean removal of system-level components
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
    [[ -f "$_CAI_SCRIPT_DIR/lib/core.sh" ]] \
        && [[ -f "$_CAI_SCRIPT_DIR/lib/platform.sh" ]] \
        && [[ -f "$_CAI_SCRIPT_DIR/lib/docker.sh" ]] \
        && [[ -f "$_CAI_SCRIPT_DIR/lib/doctor.sh" ]] \
        && [[ -f "$_CAI_SCRIPT_DIR/lib/config.sh" ]] \
        && [[ -f "$_CAI_SCRIPT_DIR/lib/container.sh" ]] \
        && [[ -f "$_CAI_SCRIPT_DIR/lib/import.sh" ]] \
        && [[ -f "$_CAI_SCRIPT_DIR/lib/export.sh" ]] \
        && [[ -f "$_CAI_SCRIPT_DIR/lib/setup.sh" ]] \
        && [[ -f "$_CAI_SCRIPT_DIR/lib/ssh.sh" ]] \
        && [[ -f "$_CAI_SCRIPT_DIR/lib/env.sh" ]] \
        && [[ -f "$_CAI_SCRIPT_DIR/lib/version.sh" ]] \
        && [[ -f "$_CAI_SCRIPT_DIR/lib/uninstall.sh" ]] \
        && [[ -f "$_CAI_SCRIPT_DIR/lib/update.sh" ]] \
        && [[ -f "$_CAI_SCRIPT_DIR/lib/links.sh" ]]
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

if ! source "$_CAI_SCRIPT_DIR/lib/ssh.sh"; then
    echo "[ERROR] Failed to source lib/ssh.sh" >&2
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

if ! source "$_CAI_SCRIPT_DIR/lib/uninstall.sh"; then
    echo "[ERROR] Failed to source lib/uninstall.sh" >&2
    return 1
fi

if ! source "$_CAI_SCRIPT_DIR/lib/update.sh"; then
    echo "[ERROR] Failed to source lib/update.sh" >&2
    return 1
fi

if ! source "$_CAI_SCRIPT_DIR/lib/links.sh"; then
    echo "[ERROR] Failed to source lib/links.sh" >&2
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
  setup         Configure secure container isolation (Linux/WSL2/macOS)
  validate      Validate Secure Engine configuration
  docker        Run docker with ContainAI context (defaults to containai-docker if present)
  sandbox       (Deprecated - use 'cai stop && cai --restart')
  import        Sync host configs to data volume
  export        Export data volume to .tgz archive
  stop          Stop ContainAI containers
  ssh           Manage SSH configuration (cleanup stale configs)
  links         Verify and repair container symlinks
  version       Show current version
  update        Update ContainAI installation
  uninstall     Clean removal of system-level components
  help          Show this help message

Run Options:
  <path>                Workspace path (positional, alternative to --workspace)
  --data-volume <vol>   Data volume name (overrides config)
  --config <path>       Config file path (overrides auto-discovery)
  --workspace <path>    Workspace path (default: current directory)
  --container <name>    Container name (default: auto-generated from workspace)
  --image-tag <tag>     Image tag (advanced/debugging, stored as label)
  --memory <size>       Memory limit (e.g., "4g", "8g") - overrides config
  --cpus <count>        CPU limit (e.g., 2, 4) - overrides config
  --fresh               Remove and recreate container (preserves data volume)
  --restart             Force recreate container (alias for --fresh)
  --force               Skip isolation checks (for testing only)
  --detached, -d        Run in background
  --quiet, -q           Suppress verbose output
  --dry-run             Show what would happen without executing (machine-parseable)
  -e, --env <VAR=val>   Set environment variable (repeatable)
  -- <args>             Pass arguments to agent

Container Lifecycle:
  Containers use tini (--init) as PID 1 for proper zombie reaping, running sleep infinity.
  Agent sessions attach via docker exec. Container stays running between sessions.
  Same workspace path always maps to same container (deterministic naming via hash).

Global Options:
  -h, --help            Show help (use with subcommand for subcommand help)

Examples:
  cai                               Start container (default)
  cai /path/to/project              Start container for specified workspace
  cai --fresh /path/to/project      Recreate container for workspace
  cai --dry-run                     Show what would happen (machine-parseable)
  cai -- --print                    Pass --print to agent
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
ContainAI Import - Sync host configs to data volume or hot-reload into running container

Usage: cai import [path] [options]

Hot-Reload Mode (with workspace path or --container):
  When a workspace path or --container is provided, imports configs AND reloads them into
  the running container via SSH. Container must be running.

  What gets synced to volume:
  - Environment variables from host (via [env] config)
  - Git config (user.name, user.email)
  - API tokens/credentials (synced to data volume paths)

  What gets activated in container:
  - Git config is copied to agent's home directory
  - Env vars loaded via shell init hook for future sessions
  - SSH: agent forwarding (ssh -A) preferred; keys also synced to volume
    unless --no-secrets is used

Volume-Only Mode (no workspace path or --container):
  Syncs configs to data volume only. Does not affect running containers.
  Use this to prepare configs before starting a container.

Options:
  <path>                Workspace path (positional) - enables hot-reload mode
  --workspace <path>    Workspace path (alternative to positional)
  --container <name>    Target specific container (derives workspace/volume from labels)
                        Mutually exclusive with --workspace and --data-volume
  --data-volume <vol>   Data volume name (overrides config)
  --from <path>         Import source:
                        - Directory: syncs from that directory (default: $HOME)
                        - Archive (.tgz): restores archive to volume (idempotent)
  --config <path>       Config file path (overrides auto-discovery)
  --dry-run             Preview changes without applying
  --no-excludes         Skip exclude patterns from config
  --no-secrets          Skip syncing agent secret files (OAuth tokens, API keys,
                        SSH private keys). Skips entries marked as secrets.
                        Does NOT affect --credentials flag.
                        Note: Has no effect with --from archive.tgz (restores bypass sync).
                        Note: Symlinked SSH keys (~/.ssh/id_*) are not synced (logged as warning).
  -h, --help            Show this help message

Secret files skipped by --no-secrets (examples):
  - ~/.claude/.credentials.json, ~/.claude.json (Claude OAuth)
  - ~/.codex/auth.json (Codex API key)
  - ~/.gemini/google_accounts.json, oauth_creds.json (Gemini OAuth)
  - ~/.local/share/opencode/auth.json (OpenCode auth)
  - ~/.config/gh/hosts.yml (GitHub CLI OAuth tokens)
  - ~/.ssh/id_* (SSH private keys, dynamically discovered at sync time)
  - ~/.aider.conf.yml, ~/.aider.model.settings.yml (may contain API keys)
  - ~/.continue/config.yaml, config.json (may contain API keys)
  - ~/.cursor/mcp.json, ~/.config/opencode/opencode.json (may contain tokens)

Examples:
  cai import /path/to/workspace        Hot-reload configs into running container
  cai import --container my-project    Hot-reload into named container
  cai import                           Sync configs to auto-resolved volume only
  cai import --dry-run                 Preview what would be synced
  cai import --no-excludes             Sync without applying excludes
  cai import --no-secrets              Sync without agent secrets (tokens, keys)
  cai import --dry-run --no-secrets    Preview which secrets would be skipped
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
  --container <name>    Target specific container (derives volume from labels)
                        Mutually exclusive with --workspace and --data-volume
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
  cai export --container my-project  Export from specific container
  cai export --data-volume vol       Export specific volume
EOF
}

_containai_stop_help() {
    cat <<'EOF'
ContainAI Stop - Stop ContainAI containers

Usage: cai stop [options]

Options:
  --container <name>  Stop specific container by name
  --all               Stop all containers without prompting
  --remove            Also remove containers (not just stop them)
                      When used with --remove, SSH configs are automatically cleaned
  -h, --help          Show this help message

Examples:
  cai stop                      Interactive selection to stop containers
  cai stop --container my-proj  Stop specific container
  cai stop --all                Stop all ContainAI containers
  cai stop --remove             Remove containers (cleans up SSH configs)
  cai stop --all --remove       Remove all ContainAI containers
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
ContainAI Shell - Open interactive shell in container via SSH

Usage: cai shell [path] [options]

Opens a bash shell in the container via SSH.
If no container exists, creates one first.
If container exists but is stopped, starts it first.

SSH provides a real terminal experience with:
  - Proper TTY handling and signal forwarding
  - Agent forwarding (if SSH_AUTH_SOCK is set)
  - VS Code Remote-SSH compatibility

Options:
  <path>                Workspace path (positional, alternative to --workspace)
  --data-volume <vol>   Data volume name (overrides config)
  --config <path>       Config file path (overrides auto-discovery)
  --workspace <path>    Workspace path (default: current directory)
  --container <name>    Container name (default: auto-generated from workspace)
  --image-tag <tag>     Image tag (advanced/debugging, stored as label)
  --memory <size>       Memory limit (e.g., "4g", "8g") - overrides config
  --cpus <count>        CPU limit (e.g., 2, 4) - overrides config
  --fresh               Remove and recreate container (preserves data volume)
  --restart             Alias for --fresh
  --force               Skip isolation checks (for testing only)
  --dry-run             Show what would happen without executing (machine-parseable)
  -q, --quiet           Suppress verbose output
  -h, --help            Show this help message

Connection Handling:
  - Automatic retry on transient failures (connection refused, timeout)
  - Max 3 retries with exponential backoff
  - Auto-regenerates missing SSH config
  - Clear error messages with remediation steps

Exit Codes:
  0    Success (SSH session completed normally)
  1    Container creation failed (run 'cai doctor' to check setup)
  11   Container failed to start
  12   SSH setup failed
  13   SSH connection failed after retries
  14   Host key mismatch could not be auto-recovered
  15   Container exists but not owned by ContainAI
  *    Other codes: exit status from remote shell command

Examples:
  cai shell                    Open shell in container for current directory
  cai shell /path/to/project   Open shell in container for specified workspace
  cai shell --fresh            Recreate container with fresh SSH keys
  cai shell --dry-run          Show what would happen (machine-parseable)
  ssh <container-name>         Direct SSH access (after cai shell setup)
EOF
}

_containai_ssh_help() {
    cat <<'EOF'
ContainAI SSH - Manage SSH configuration for containers

Usage: cai ssh <subcommand> [options]

Subcommands:
  cleanup       Remove stale SSH configs for non-existent containers

Options:
  -h, --help    Show this help message

Examples:
  cai ssh cleanup              Remove stale SSH configs
  cai ssh cleanup --dry-run    Show what would be cleaned without doing it
EOF
}

_containai_ssh_cleanup_help() {
    cat <<'EOF'
ContainAI SSH Cleanup - Remove stale SSH configurations

Usage: cai ssh cleanup [options]

Scans ~/.ssh/containai.d/ for SSH configs and removes those for containers
that no longer exist. Also cleans corresponding known_hosts entries.

Options:
  --dry-run     Show what would be cleaned without doing it
  -h, --help    Show this help message

What gets cleaned:
  - SSH host config files in ~/.ssh/containai.d/*.conf
  - Corresponding known_hosts entries in ~/.config/containai/known_hosts

Examples:
  cai ssh cleanup              Remove stale SSH configs
  cai ssh cleanup --dry-run    Preview what would be removed

Note: This command is safe to run - it only removes configs for containers
that have been deleted. Active container configs are preserved.
EOF
}

_containai_doctor_help() {
    local platform
    platform=$(_cai_detect_platform)

    cat <<'EOF'
ContainAI Doctor - Check system capabilities and diagnostics

Usage: cai doctor [options]

Checks Docker availability and Sysbox isolation configuration.
Reports requirement levels and actionable remediation guidance.

Requirements:
  Sysbox: REQUIRED - cai run requires Sysbox for container isolation
  SSH: REQUIRED - cai shell/run use SSH for container access

Options:
  --fix           Auto-fix issues that can be remediated automatically
  --json          Output machine-parseable JSON
EOF

    # Show --reset-lima option only on macOS
    if [[ "$platform" == "macos" ]]; then
        cat <<'EOF'
  --reset-lima    Delete Lima VM and Docker context (requires confirmation)
EOF
    fi

    cat <<'EOF'
  -h, --help      Show this help message

Exit Codes:
  0    All checks pass (Sysbox available AND SSH configured)
  1    Checks failed (run 'cai setup' to configure)

What --fix can remediate:
  - Missing SSH key (regenerates)
  - Missing SSH config directory (creates)
  - Missing Include directive (adds to ~/.ssh/config)
  - Stale SSH configs (removes orphaned container configs)
  - Wrong file permissions (fixes to 700/600 as appropriate)

What --fix cannot remediate (requires manual action):
  - Sysbox not installed (use 'cai setup')
  - Docker context not configured (use 'cai setup')
  - Kernel version incompatible
  - Docker daemon not running

Examples:
  cai doctor                    Run all checks, show formatted report
  cai doctor --fix              Auto-fix issues and show report
  cai doctor --json             Output JSON for scripts/automation
EOF
}

_containai_links_help() {
    cat <<'EOF'
ContainAI Links - Verify and repair container symlinks

Usage: cai links <subcommand> [options]

Subcommands:
  check         Verify symlinks match link-spec.json
  fix           Repair broken or missing symlinks

Options:
  <path>                Workspace path (positional, alternative to --workspace)
  --workspace <path>    Workspace path (default: current directory)
  --name <name>         Container name (overrides workspace-based lookup)
  --config <path>       Config file path (overrides auto-discovery)
  --quiet, -q           Suppress verbose output
  --dry-run             Show what would be fixed without making changes (fix only)
  -h, --help            Show this help message

How it works:
  Links are verified/repaired inside the container via SSH. The container
  must be running (or will be started for fix operations).

  The link-spec.json is shipped in the container image and defines all
  symlinks that should exist from the container filesystem to the data
  volume at /mnt/agent-data.

Exit Codes:
  0    Success (all links OK, or fix completed)
  1    Issues found (check mode) or errors occurred

Examples:
  cai links check                    Verify symlinks in default container
  cai links check /path/to/project   Verify symlinks for specific workspace
  cai links fix                      Repair broken symlinks
  cai links fix --dry-run            Preview what would be fixed
  cai links fix --name my-container  Repair links in named container
EOF
}

# ==============================================================================
# Subcommand handlers
# ==============================================================================

# Import subcommand handler
# Supports two modes:
# 1. Volume-only mode (no workspace path): syncs configs to data volume
# 2. Hot-reload mode (with workspace path or --container): syncs to volume AND reloads into running container
_containai_import_cmd() {
    local dry_run="false"
    local no_excludes="false"
    local no_secrets="false"
    local cli_volume=""
    local workspace=""
    local explicit_config=""
    local from_source=""
    local hot_reload="false"
    local container_name=""

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
            --no-secrets)
                no_secrets="true"
                shift
                ;;
            --container)
                if [[ -z "${2-}" ]]; then
                    echo "[ERROR] --container requires a value" >&2
                    return 1
                fi
                container_name="$2"
                hot_reload="true"
                shift 2
                ;;
            --container=*)
                container_name="${1#--container=}"
                if [[ -z "$container_name" ]]; then
                    echo "[ERROR] --container requires a value" >&2
                    return 1
                fi
                hot_reload="true"
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
            --workspace | -w)
                if [[ -z "${2-}" ]]; then
                    echo "[ERROR] --workspace requires a value" >&2
                    return 1
                fi
                workspace="$2"
                workspace="${workspace/#\~/$HOME}"
                hot_reload="true"
                shift 2
                ;;
            --workspace=*)
                workspace="${1#--workspace=}"
                if [[ -z "$workspace" ]]; then
                    echo "[ERROR] --workspace requires a value" >&2
                    return 1
                fi
                workspace="${workspace/#\~/$HOME}"
                hot_reload="true"
                shift
                ;;
            -w*)
                workspace="${1#-w}"
                workspace="${workspace/#\~/$HOME}"
                hot_reload="true"
                shift
                ;;
            --help | -h)
                _containai_import_help
                return 0
                ;;
            *)
                # Check if it's a directory path (positional workspace argument for hot-reload)
                if [[ -z "$workspace" && -d "$1" ]]; then
                    workspace="$1"
                    workspace="${workspace/#\~/$HOME}"
                    hot_reload="true"
                    shift
                else
                    echo "[ERROR] Unknown option: $1" >&2
                    echo "Use 'cai import --help' for usage" >&2
                    return 1
                fi
                ;;
        esac
    done

    # Check mutual exclusivity of --container with --workspace and --data-volume
    if [[ -n "$container_name" ]]; then
        if [[ -n "$workspace" ]]; then
            echo "[ERROR] --container and --workspace are mutually exclusive" >&2
            return 1
        fi
        if [[ -n "$cli_volume" ]]; then
            echo "[ERROR] --container and --data-volume are mutually exclusive" >&2
            return 1
        fi
    fi

    # Resolve workspace and volume - from container labels if --container provided
    local resolved_workspace="" resolved_volume="" selected_context=""

    if [[ -n "$container_name" ]]; then
        # --container mode: derive workspace and volume from container labels
        # First, select context to find the container
        local config_context_override=""
        if [[ -n "$explicit_config" ]]; then
            if ! config_context_override=$(_containai_resolve_secure_engine_context "$PWD" "$explicit_config"); then
                echo "[ERROR] Failed to parse config: $explicit_config" >&2
                return 1
            fi
        fi

        if selected_context=$(DOCKER_CONTEXT= DOCKER_HOST= _cai_select_context "$config_context_override" ""); then
            : # success
        else
            echo "[ERROR] No isolation available. Run 'cai doctor' for setup instructions." >&2
            return 1
        fi

        # Build docker command with context
        local -a docker_cmd=(docker)
        if [[ -n "$selected_context" ]]; then
            docker_cmd=(docker --context "$selected_context")
        fi

        # Check container exists
        if ! "${docker_cmd[@]}" inspect "$container_name" >/dev/null 2>&1; then
            echo "[ERROR] Container not found: $container_name" >&2
            return 1
        fi

        # Check if container is managed by ContainAI
        local is_managed
        is_managed=$("${docker_cmd[@]}" inspect --format '{{index .Config.Labels "containai.managed"}}' "$container_name" 2>/dev/null) || is_managed=""
        if [[ "$is_managed" != "true" ]]; then
            echo "[ERROR] Container $container_name exists but is not managed by ContainAI" >&2
            return 1
        fi

        # Derive workspace from container labels
        resolved_workspace=$("${docker_cmd[@]}" inspect --format '{{index .Config.Labels "containai.workspace"}}' "$container_name" 2>/dev/null) || resolved_workspace=""
        if [[ -z "$resolved_workspace" ]]; then
            echo "[ERROR] Container $container_name is missing workspace label" >&2
            return 1
        fi

        # Derive data volume from container labels
        resolved_volume=$("${docker_cmd[@]}" inspect --format '{{index .Config.Labels "containai.data-volume"}}' "$container_name" 2>/dev/null) || resolved_volume=""
        if [[ -z "$resolved_volume" ]]; then
            echo "[ERROR] Container $container_name is missing data-volume label" >&2
            return 1
        fi
    else
        # Standard mode: resolve from workspace path
        local workspace_input
        workspace_input="${workspace:-$PWD}"
        resolved_workspace=$(_cai_normalize_path "$workspace_input")
        # Check if path exists (normalize_path returns as-is for non-existent paths)
        if [[ ! -d "$resolved_workspace" ]]; then
            echo "[ERROR] Workspace path does not exist: $workspace_input" >&2
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
        if selected_context=$(DOCKER_CONTEXT= DOCKER_HOST= _cai_select_context "$config_context_override" ""); then
            : # success - selected_context is isolated context (Sysbox)
        else
            echo "[ERROR] No isolation available. Run 'cai doctor' for setup instructions." >&2
            return 1
        fi

        # Resolve volume
        if ! resolved_volume=$(_containai_resolve_volume "$cli_volume" "$resolved_workspace" "$explicit_config"); then
            echo "[ERROR] Failed to resolve data volume" >&2
            return 1
        fi
    fi

    # For hot-reload mode, validate container is running before proceeding
    local resolved_container_name=""
    if [[ "$hot_reload" == "true" ]]; then
        # Build docker command with context
        local -a docker_cmd=(docker)
        if [[ -n "$selected_context" ]]; then
            docker_cmd=(docker --context "$selected_context")
        fi

        if [[ -n "$container_name" ]]; then
            # --container was provided, use it directly
            resolved_container_name="$container_name"
        else
            # Try to find container by workspace label first (handles --container containers)
            # Label format: containai.workspace=/absolute/path
            # Use -a to include stopped containers for proper error messages
            local label_filter="containai.workspace=$resolved_workspace"
            local found_containers
            found_containers=$("${docker_cmd[@]}" ps -aq --filter "label=$label_filter" 2>/dev/null | head -2)

            if [[ -n "$found_containers" ]]; then
                # Count matches (filter to first line to handle empty case)
                local match_count
                match_count=$(printf '%s\n' "$found_containers" | grep -c . || echo 0)
                if [[ "$match_count" -gt 1 ]]; then
                    echo "[ERROR] Multiple containers found for workspace: $resolved_workspace" >&2
                    echo "" >&2
                    echo "Containers:" >&2
                    "${docker_cmd[@]}" ps -a --filter "label=$label_filter" --format "  {{.Names}} ({{.Status}})" >&2
                    echo "" >&2
                    echo "Use --container to specify which one." >&2
                    return 1
                fi
                # Get container name from ID (take first line only)
                local first_container
                first_container=$(printf '%s\n' "$found_containers" | head -1)
                resolved_container_name=$("${docker_cmd[@]}" inspect --format '{{.Name}}' "$first_container" 2>/dev/null)
                resolved_container_name="${resolved_container_name#/}" # Remove leading /
            else
                # Fallback: try hash-based container name
                if ! resolved_container_name=$(_containai_container_name "$resolved_workspace"); then
                    echo "[ERROR] Failed to generate container name for workspace: $resolved_workspace" >&2
                    return 1
                fi
            fi
        fi

        # Check container exists and is running
        local container_state
        if ! container_state=$("${docker_cmd[@]}" inspect --format '{{.State.Status}}' -- "$resolved_container_name" 2>/dev/null); then
            echo "[ERROR] Container not found for workspace: $resolved_workspace" >&2
            echo "" >&2
            echo "To create a container for this workspace, run:" >&2
            echo "  cai run $resolved_workspace" >&2
            return 1
        fi

        if [[ "$container_state" != "running" ]]; then
            echo "[ERROR] Container '$resolved_container_name' is not running (state: $container_state)" >&2
            echo "" >&2
            echo "Start the container first with:" >&2
            echo "  cai shell $resolved_workspace" >&2
            echo "Or use 'cai import' without a workspace path for volume-only sync." >&2
            return 1
        fi

        if [[ "$dry_run" != "true" ]]; then
            _cai_info "Hot-reload mode: will sync configs and reload into container '$resolved_container_name'"
        fi
    fi

    # Clear restore mode flag from any previous run (avoids session pollution)
    unset _CAI_RESTORE_MODE

    # Call import function with context
    if ! _containai_import "$selected_context" "$resolved_volume" "$dry_run" "$no_excludes" "$resolved_workspace" "$explicit_config" "$from_source" "$no_secrets"; then
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

    # Hot-reload: execute reload commands in container via SSH
    if [[ "$hot_reload" == "true" && "$dry_run" != "true" ]]; then
        if ! _cai_hot_reload_container "$resolved_container_name" "$selected_context"; then
            echo "[ERROR] Hot-reload failed" >&2
            return 1
        fi
    elif [[ "$hot_reload" == "true" && "$dry_run" == "true" ]]; then
        _cai_info "[dry-run] Would reload configs into container: $resolved_container_name"
    fi
}

# Export subcommand handler
_containai_export_cmd() {
    local output_path=""
    local no_excludes="false"
    local cli_volume=""
    local workspace=""
    local explicit_config=""
    local container_name=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -o | --output)
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
            --container)
                if [[ -z "${2-}" ]]; then
                    echo "[ERROR] --container requires a value" >&2
                    return 1
                fi
                container_name="$2"
                shift 2
                ;;
            --container=*)
                container_name="${1#--container=}"
                if [[ -z "$container_name" ]]; then
                    echo "[ERROR] --container requires a value" >&2
                    return 1
                fi
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
            --help | -h)
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

    # Check mutual exclusivity of --container with --workspace and --data-volume
    if [[ -n "$container_name" ]]; then
        if [[ -n "$workspace" ]]; then
            echo "[ERROR] --container and --workspace are mutually exclusive" >&2
            return 1
        fi
        if [[ -n "$cli_volume" ]]; then
            echo "[ERROR] --container and --data-volume are mutually exclusive" >&2
            return 1
        fi
    fi

    # Resolve workspace and volume - from container labels if --container provided
    local resolved_workspace="" resolved_volume=""

    if [[ -n "$container_name" ]]; then
        # --container mode: derive volume from container labels
        # First, select context to find the container
        local config_context_override=""
        if [[ -n "$explicit_config" ]]; then
            if ! config_context_override=$(_containai_resolve_secure_engine_context "$PWD" "$explicit_config"); then
                echo "[ERROR] Failed to parse config: $explicit_config" >&2
                return 1
            fi
        fi

        local selected_context=""
        if selected_context=$(DOCKER_CONTEXT= DOCKER_HOST= _cai_select_context "$config_context_override" ""); then
            : # success
        else
            echo "[ERROR] No isolation available. Run 'cai doctor' for setup instructions." >&2
            return 1
        fi

        # Build docker command with context
        local -a docker_cmd=(docker)
        if [[ -n "$selected_context" ]]; then
            docker_cmd=(docker --context "$selected_context")
        fi

        # Check container exists
        if ! "${docker_cmd[@]}" inspect "$container_name" >/dev/null 2>&1; then
            echo "[ERROR] Container not found: $container_name" >&2
            return 1
        fi

        # Check if container is managed by ContainAI
        local is_managed
        is_managed=$("${docker_cmd[@]}" inspect --format '{{index .Config.Labels "containai.managed"}}' "$container_name" 2>/dev/null) || is_managed=""
        if [[ "$is_managed" != "true" ]]; then
            echo "[ERROR] Container $container_name exists but is not managed by ContainAI" >&2
            return 1
        fi

        # Derive workspace from container labels (for excludes resolution)
        resolved_workspace=$("${docker_cmd[@]}" inspect --format '{{index .Config.Labels "containai.workspace"}}' "$container_name" 2>/dev/null) || resolved_workspace=""
        if [[ -z "$resolved_workspace" ]]; then
            echo "[ERROR] Container $container_name is missing workspace label" >&2
            return 1
        fi

        # Derive data volume from container labels
        resolved_volume=$("${docker_cmd[@]}" inspect --format '{{index .Config.Labels "containai.data-volume"}}' "$container_name" 2>/dev/null) || resolved_volume=""
        if [[ -z "$resolved_volume" ]]; then
            echo "[ERROR] Container $container_name is missing data-volume label" >&2
            return 1
        fi
    else
        # Standard mode: resolve from workspace path
        local workspace_input
        workspace_input="${workspace:-$PWD}"
        resolved_workspace=$(_cai_normalize_path "$workspace_input")
        # Check if path exists (normalize_path returns as-is for non-existent paths)
        if [[ ! -d "$resolved_workspace" ]]; then
            echo "[ERROR] Workspace path does not exist: $workspace_input" >&2
            return 1
        fi

        # Resolve volume
        if ! resolved_volume=$(_containai_resolve_volume "$cli_volume" "$resolved_workspace" "$explicit_config"); then
            echo "[ERROR] Failed to resolve data volume" >&2
            return 1
        fi
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
        done <<<"$exclude_output"
    fi

    # Call export function - pass array name, not array
    _containai_export "$resolved_volume" "$output_path" "export_excludes" "$no_excludes"
}

# Stop subcommand handler
_containai_stop_cmd() {
    local container_name=""
    local remove_flag=false
    local arg

    for arg in "$@"; do
        case "$arg" in
            --help | -h)
                _containai_stop_help
                return 0
                ;;
        esac
    done

    # Parse --container argument
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --container)
                if [[ -z "${2-}" ]]; then
                    echo "[ERROR] --container requires a value" >&2
                    return 1
                fi
                container_name="$2"
                shift 2
                ;;
            --container=*)
                container_name="${1#--container=}"
                if [[ -z "$container_name" ]]; then
                    echo "[ERROR] --container requires a value" >&2
                    return 1
                fi
                shift
                ;;
            --remove)
                remove_flag=true
                shift
                ;;
            --all | --help | -h)
                # These are handled by _containai_stop_all
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    # If --container specified, stop that specific container
    if [[ -n "$container_name" ]]; then
        # Select context to find the container
        local config_context_override=""
        local selected_context=""
        if selected_context=$(DOCKER_CONTEXT= DOCKER_HOST= _cai_select_context "$config_context_override" ""); then
            : # success
        else
            echo "[ERROR] No isolation available. Run 'cai doctor' for setup instructions." >&2
            return 1
        fi

        # Build docker command with context
        local -a docker_cmd=(docker)
        if [[ -n "$selected_context" ]]; then
            docker_cmd=(docker --context "$selected_context")
        fi

        # Check container exists
        if ! "${docker_cmd[@]}" inspect "$container_name" >/dev/null 2>&1; then
            echo "[ERROR] Container not found: $container_name" >&2
            return 1
        fi

        # Check if container is managed by ContainAI
        local is_managed
        is_managed=$("${docker_cmd[@]}" inspect --format '{{index .Config.Labels "containai.managed"}}' "$container_name" 2>/dev/null) || is_managed=""
        if [[ "$is_managed" != "true" ]]; then
            echo "[ERROR] Container $container_name exists but is not managed by ContainAI" >&2
            return 1
        fi

        if [[ "$remove_flag" == "true" ]]; then
            # Get SSH port before removing (for cleanup)
            local ssh_port
            ssh_port=$(_cai_get_container_ssh_port "$container_name" "$selected_context" 2>/dev/null) || ssh_port=""

            echo "Removing: $container_name${selected_context:+ [context: $selected_context]}"
            if "${docker_cmd[@]}" rm -f "$container_name" >/dev/null 2>&1; then
                # Clean up SSH config
                if [[ -n "$ssh_port" ]]; then
                    _cai_cleanup_container_ssh "$container_name" "$ssh_port"
                else
                    _cai_remove_ssh_host_config "$container_name"
                fi
                echo "Done."
            else
                echo "[ERROR] Failed to remove container: $container_name" >&2
                return 1
            fi
        else
            echo "Stopping: $container_name${selected_context:+ [context: $selected_context]}"
            if "${docker_cmd[@]}" stop "$container_name" >/dev/null 2>&1; then
                echo "Done."
            else
                echo "[ERROR] Failed to stop container: $container_name" >&2
                return 1
            fi
        fi
        return 0
    fi

    # No --container specified, delegate to interactive stop all
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
    local fix_mode="false"
    local reset_lima="false"
    local workspace="$PWD"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json)
                json_output="true"
                shift
                ;;
            --fix)
                fix_mode="true"
                shift
                ;;
            --reset-lima)
                # Only accept on macOS; return clear error on other platforms
                if [[ "$(_cai_detect_platform)" != "macos" ]]; then
                    _cai_error "--reset-lima is only available on macOS"
                    return 1
                fi
                reset_lima="true"
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
            --help | -h)
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

    # Handle --reset-lima (macOS only)
    if [[ "$reset_lima" == "true" ]]; then
        _cai_doctor_reset_lima
        return $?
    fi

    # Resolve workspace and parse config to get configured resource limits
    # Use platform-aware normalization for consistency
    local resolved_workspace
    resolved_workspace=$(_cai_normalize_path "$workspace")
    # Check if path exists; fall back to PWD if not
    if [[ ! -d "$resolved_workspace" ]]; then
        resolved_workspace="$PWD"
    fi

    # Try to find and parse config for resource limit display
    local config_file
    config_file=$(_containai_find_config "$resolved_workspace")
    if [[ -n "$config_file" ]]; then
        _containai_parse_config "$config_file" "$resolved_workspace" 2>/dev/null || true
    fi

    # Run doctor checks
    if [[ "$fix_mode" == "true" ]]; then
        _cai_doctor_fix
    elif [[ "$json_output" == "true" ]]; then
        _cai_doctor_json
    else
        _cai_doctor
    fi
}

# SSH subcommand handler - manage SSH configurations
# Supports subcommands: cleanup
_containai_ssh_cmd() {
    local ssh_subcommand="${1:-}"

    # Handle empty or help first
    if [[ -z "$ssh_subcommand" ]]; then
        _containai_ssh_help
        return 0
    fi

    case "$ssh_subcommand" in
        cleanup)
            shift
            _containai_ssh_cleanup_cmd "$@"
            ;;
        help | -h | --help)
            _containai_ssh_help
            return 0
            ;;
        *)
            echo "[ERROR] Unknown ssh subcommand: $ssh_subcommand" >&2
            echo "Use 'cai ssh --help' for usage" >&2
            return 1
            ;;
    esac
}

# SSH cleanup subcommand handler
_containai_ssh_cleanup_cmd() {
    local dry_run="false"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                dry_run="true"
                shift
                ;;
            --help | -h)
                _containai_ssh_cleanup_help
                return 0
                ;;
            *)
                echo "[ERROR] Unknown option: $1" >&2
                echo "Use 'cai ssh cleanup --help' for usage" >&2
                return 1
                ;;
        esac
    done

    # Call the cleanup function from ssh.sh
    _cai_ssh_cleanup "$dry_run"
}

# ==============================================================================
# Links subcommand handlers
# ==============================================================================

# Links subcommand handler - verify and repair container symlinks
# Supports subcommands: check, fix
_containai_links_cmd() {
    local links_subcommand="${1:-}"

    # Handle empty or help first
    if [[ -z "$links_subcommand" ]]; then
        _containai_links_help
        return 0
    fi

    case "$links_subcommand" in
        check)
            shift
            _containai_links_check_cmd "$@"
            ;;
        fix)
            shift
            _containai_links_fix_cmd "$@"
            ;;
        help | -h | --help)
            _containai_links_help
            return 0
            ;;
        *)
            echo "[ERROR] Unknown links subcommand: $links_subcommand" >&2
            echo "Use 'cai links --help' for usage" >&2
            return 1
            ;;
    esac
}

# Links check subcommand handler
_containai_links_check_cmd() {
    local workspace=""
    local explicit_config=""
    local container_name=""
    local quiet_flag="false"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
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
            --quiet | -q)
                quiet_flag="true"
                shift
                ;;
            --help | -h)
                _containai_links_help
                return 0
                ;;
            *)
                # Positional argument: could be workspace path OR container name
                if [[ -z "$workspace" && -z "$container_name" ]]; then
                    local arg="$1"
                    arg="${arg/#\~/$HOME}"
                    if [[ -d "$arg" ]]; then
                        # It's a directory - treat as workspace
                        workspace="$arg"
                    else
                        # Not a directory - treat as container name
                        container_name="$arg"
                    fi
                    shift
                else
                    echo "[ERROR] Unknown option: $1" >&2
                    echo "Use 'cai links check --help' for usage" >&2
                    return 1
                fi
                ;;
        esac
    done

    # Resolve workspace using platform-aware normalization (if not using direct container name)
    local resolved_workspace=""
    if [[ -z "$container_name" ]]; then
        local workspace_input
        workspace_input="${workspace:-$PWD}"
        resolved_workspace=$(_cai_normalize_path "$workspace_input")
        if [[ ! -d "$resolved_workspace" ]]; then
            echo "[ERROR] Workspace path does not exist: $workspace_input" >&2
            return 1
        fi
    fi

    # Resolve context from config (skip if using direct container name without config)
    local config_context_override=""
    if [[ -n "$explicit_config" && -n "$resolved_workspace" ]]; then
        if ! config_context_override=$(_containai_resolve_secure_engine_context "$resolved_workspace" "$explicit_config"); then
            echo "[ERROR] Failed to parse config: $explicit_config" >&2
            return 1
        fi
    elif [[ -n "$resolved_workspace" ]]; then
        config_context_override=$(_containai_resolve_secure_engine_context "$resolved_workspace" "" 2>/dev/null) || config_context_override=""
    fi

    # Auto-select Docker context
    local selected_context=""
    if ! selected_context=$(DOCKER_CONTEXT= DOCKER_HOST= _cai_select_context "$config_context_override" ""); then
        echo "[ERROR] No isolation available. Run 'cai doctor' for setup instructions." >&2
        return 1
    fi

    # Resolve container name
    local resolved_container_name
    if ! resolved_container_name=$(_links_resolve_container "$container_name" "$resolved_workspace" "$selected_context"); then
        return 1
    fi

    # Run check
    _containai_links_check "$resolved_container_name" "$selected_context" "$quiet_flag"
}

# Links fix subcommand handler
_containai_links_fix_cmd() {
    local workspace=""
    local explicit_config=""
    local container_name=""
    local quiet_flag="false"
    local dry_run_flag="false"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
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
            --quiet | -q)
                quiet_flag="true"
                shift
                ;;
            --dry-run)
                dry_run_flag="true"
                shift
                ;;
            --help | -h)
                _containai_links_help
                return 0
                ;;
            *)
                # Positional argument: could be workspace path OR container name
                if [[ -z "$workspace" && -z "$container_name" ]]; then
                    local arg="$1"
                    arg="${arg/#\~/$HOME}"
                    if [[ -d "$arg" ]]; then
                        # It's a directory - treat as workspace
                        workspace="$arg"
                    else
                        # Not a directory - treat as container name
                        container_name="$arg"
                    fi
                    shift
                else
                    echo "[ERROR] Unknown option: $1" >&2
                    echo "Use 'cai links fix --help' for usage" >&2
                    return 1
                fi
                ;;
        esac
    done

    # Resolve workspace using platform-aware normalization (if not using direct container name)
    local resolved_workspace=""
    if [[ -z "$container_name" ]]; then
        local workspace_input
        workspace_input="${workspace:-$PWD}"
        resolved_workspace=$(_cai_normalize_path "$workspace_input")
        if [[ ! -d "$resolved_workspace" ]]; then
            echo "[ERROR] Workspace path does not exist: $workspace_input" >&2
            return 1
        fi
    fi

    # Resolve context from config (skip if using direct container name without config)
    local config_context_override=""
    if [[ -n "$explicit_config" && -n "$resolved_workspace" ]]; then
        if ! config_context_override=$(_containai_resolve_secure_engine_context "$resolved_workspace" "$explicit_config"); then
            echo "[ERROR] Failed to parse config: $explicit_config" >&2
            return 1
        fi
    elif [[ -n "$resolved_workspace" ]]; then
        config_context_override=$(_containai_resolve_secure_engine_context "$resolved_workspace" "" 2>/dev/null) || config_context_override=""
    fi

    # Auto-select Docker context
    local selected_context=""
    if ! selected_context=$(DOCKER_CONTEXT= DOCKER_HOST= _cai_select_context "$config_context_override" ""); then
        echo "[ERROR] No isolation available. Run 'cai doctor' for setup instructions." >&2
        return 1
    fi

    # Resolve container name
    local resolved_container_name
    if ! resolved_container_name=$(_links_resolve_container "$container_name" "$resolved_workspace" "$selected_context"); then
        return 1
    fi

    # Run fix
    _containai_links_fix "$resolved_container_name" "$selected_context" "$quiet_flag" "$dry_run_flag"
}

# ==============================================================================
# Docker pass-through subcommand
# ==============================================================================

_containai_docker_cmd() {
    if ! command -v docker >/dev/null 2>&1; then
        echo "[ERROR] Docker is not installed or not in PATH" >&2
        return 1
    fi

    local context=""
    if _cai_is_container; then
        context=""
    elif docker context inspect "$_CAI_CONTAINAI_DOCKER_CONTEXT" >/dev/null 2>&1; then
        context="$_CAI_CONTAINAI_DOCKER_CONTEXT"
    else
        echo "[ERROR] ContainAI Docker context not found. Run 'cai setup'." >&2
        return 1
    fi

    local arg
    for arg in "$@"; do
        case "$arg" in
            --context|--context=*)
                docker "$@"
                return $?
                ;;
        esac
    done

    local -a docker_base=(docker)
    if [[ -n "$context" ]]; then
        docker_base+=(--context "$context")
    fi

    local -a args=("$@")

    # Ensure docker exec defaults to the agent user for ContainAI-managed containers
    if [[ "${args[0]:-}" == "exec" ]]; then
        local has_user="false"
        local container_name=""
        local i=1 token=""
        local args_len=${#args[@]}

        while ((i < args_len)); do
            token="${args[i]}"
            case "$token" in
                -u|--user)
                    has_user="true"
                    i=$((i + 2))
                    continue
                    ;;
                -u=*|--user=*)
                    has_user="true"
                    i=$((i + 1))
                    continue
                    ;;
                --env=*|--env-file=*|--workdir=*|--detach-keys=*)
                    i=$((i + 1))
                    continue
                    ;;
                -e|--env|--env-file|-w|--workdir|--detach-keys)
                    i=$((i + 2))
                    continue
                    ;;
                --)
                    if ((i + 1 < args_len)); then
                        container_name="${args[i + 1]}"
                    fi
                    break
                    ;;
                -*)
                    i=$((i + 1))
                    continue
                    ;;
                *)
                    container_name="$token"
                    break
                    ;;
            esac
        done

        if [[ "$has_user" != "true" && -n "$container_name" ]]; then
            local managed_label image_name is_containai="false"
            managed_label=$(DOCKER_CONTEXT= DOCKER_HOST= "${docker_base[@]}" inspect --format '{{index .Config.Labels "containai.managed"}}' -- "$container_name" 2>/dev/null) || managed_label=""
            if [[ "$managed_label" == "true" ]]; then
                is_containai="true"
            else
                image_name=$(DOCKER_CONTEXT= DOCKER_HOST= "${docker_base[@]}" inspect --format '{{.Config.Image}}' -- "$container_name" 2>/dev/null) || image_name=""
                if [[ "$image_name" == "${_CONTAINAI_DEFAULT_REPO}:"* ]]; then
                    is_containai="true"
                fi
            fi

            if [[ "$is_containai" == "true" ]]; then
                args=(exec -u agent "${args[@]:1}")
            fi
        fi
    fi

    DOCKER_CONTEXT= DOCKER_HOST= "${docker_base[@]}" "${args[@]}"
}

# Shell subcommand handler - connects to container via SSH
# Uses SSH instead of docker exec for real terminal experience
_containai_shell_cmd() {
    local cli_volume=""
    local workspace=""
    local explicit_config=""
    local container_name=""
    local image_tag=""
    local cli_memory=""
    local cli_cpus=""
    local fresh_flag=false
    local force_flag=false
    local quiet_flag=false
    local debug_flag=false
    local dry_run_flag=false

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
            --container)
                if [[ -z "${2-}" ]]; then
                    echo "[ERROR] --container requires a value" >&2
                    return 1
                fi
                container_name="$2"
                shift 2
                ;;
            --container=*)
                container_name="${1#--container=}"
                if [[ -z "$container_name" ]]; then
                    echo "[ERROR] --container requires a value" >&2
                    return 1
                fi
                shift
                ;;
            --restart | --fresh)
                fresh_flag=true
                shift
                ;;
            --force)
                force_flag=true
                shift
                ;;
            --quiet | -q)
                quiet_flag=true
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
            --memory)
                if [[ -z "${2-}" ]]; then
                    echo "[ERROR] --memory requires a value" >&2
                    return 1
                fi
                cli_memory="$2"
                shift 2
                ;;
            --memory=*)
                cli_memory="${1#--memory=}"
                if [[ -z "$cli_memory" ]]; then
                    echo "[ERROR] --memory requires a value" >&2
                    return 1
                fi
                shift
                ;;
            --cpus)
                if [[ -z "${2-}" ]]; then
                    echo "[ERROR] --cpus requires a value" >&2
                    return 1
                fi
                cli_cpus="$2"
                shift 2
                ;;
            --cpus=*)
                cli_cpus="${1#--cpus=}"
                if [[ -z "$cli_cpus" ]]; then
                    echo "[ERROR] --cpus requires a value" >&2
                    return 1
                fi
                shift
                ;;
            --help | -h)
                _containai_shell_help
                return 0
                ;;
            # Legacy options that are no longer supported (provide helpful error)
            --mount-docker-socket | --please-root-my-host | --allow-host-credentials | \
                --i-understand-this-exposes-host-credentials | --allow-host-docker-socket | \
                --i-understand-this-grants-root-access)
                echo "[ERROR] $1 is no longer supported in cai shell" >&2
                echo "[INFO] cai shell uses SSH - host mounts are not available" >&2
                return 1
                ;;
            --env | -e | --env=* | -e*)
                echo "[ERROR] --env is not supported in cai shell (SSH mode)" >&2
                echo "[INFO] Set environment variables in the container's shell directly" >&2
                return 1
                ;;
            --volume | -v | --volume=* | -v*)
                echo "[ERROR] --volume is not supported in cai shell (SSH mode)" >&2
                echo "[INFO] Volumes must be configured at container creation time" >&2
                return 1
                ;;
            *)
                # Check if it's a directory path (positional workspace argument)
                if [[ -z "$workspace" && -d "$1" ]]; then
                    workspace="$1"
                    workspace="${workspace/#\~/$HOME}"
                    shift
                else
                    echo "[ERROR] Unknown option: $1" >&2
                    echo "Use 'cai shell --help' for usage" >&2
                    return 1
                fi
                ;;
        esac
    done

    # Resolve workspace using platform-aware normalization
    local resolved_workspace workspace_input
    workspace_input="${workspace:-$PWD}"
    resolved_workspace=$(_cai_normalize_path "$workspace_input")
    # Check if path exists (normalize_path returns as-is for non-existent paths)
    if [[ ! -d "$resolved_workspace" ]]; then
        echo "[ERROR] Workspace path does not exist: $workspace_input" >&2
        return 1
    fi

    # Resolve volume (needed for container creation if --fresh)
    local resolved_volume
    if ! resolved_volume=$(_containai_resolve_volume "$cli_volume" "$resolved_workspace" "$explicit_config"); then
        echo "[ERROR] Failed to resolve data volume" >&2
        return 1
    fi

    # === CONFIG PARSING (for context selection) ===
    # Note: Container name resolution moved after context selection to use shared lookup helper
    local config_file=""
    if [[ -n "$explicit_config" ]]; then
        if [[ ! -f "$explicit_config" ]]; then
            echo "[ERROR] Config file not found: $explicit_config" >&2
            return 1
        fi
        config_file="$explicit_config"
        if ! _containai_parse_config "$config_file" "$resolved_workspace" "strict"; then
            echo "[ERROR] Failed to parse config: $explicit_config" >&2
            return 1
        fi
    else
        # Discovered config: suppress errors gracefully
        config_file=$(_containai_find_config "$resolved_workspace")
        if [[ -n "$config_file" ]]; then
            _containai_parse_config "$config_file" "$resolved_workspace" 2>/dev/null || true
        fi
    fi
    local config_context_override="${_CAI_SECURE_ENGINE_CONTEXT:-}"

    # Set CLI resource overrides (global vars read by _containai_start_container)
    _CAI_CLI_MEMORY="$cli_memory"
    _CAI_CLI_CPUS="$cli_cpus"

    # Auto-select Docker context based on isolation availability
    local selected_context debug_mode=""
    if [[ "$debug_flag" == "true" ]]; then
        debug_mode="debug"
    fi
    if ! selected_context=$(_cai_select_context "$config_context_override" "$debug_mode"); then
        if [[ "$force_flag" == "true" ]]; then
            _cai_warn "Sysbox context check failed; attempting to use an existing context without validation."
            if [[ -n "$config_context_override" ]] && docker context inspect "$config_context_override" >/dev/null 2>&1; then
                selected_context="$config_context_override"
            elif docker context inspect "$_CAI_CONTAINAI_DOCKER_CONTEXT" >/dev/null 2>&1; then
                selected_context="$_CAI_CONTAINAI_DOCKER_CONTEXT"
            else
                _cai_error "No isolation context available. Run 'cai setup' to create $_CAI_CONTAINAI_DOCKER_CONTEXT."
                return 1
            fi
        else
            _cai_error "No isolation available. Run 'cai doctor' for setup instructions."
            return 1
        fi
    fi

    # Build docker command prefix
    local -a docker_cmd=(docker)
    if [[ -n "$selected_context" ]]; then
        docker_cmd=(docker --context "$selected_context")
    fi

    # Resolve container name using shared lookup helper
    # Priority: explicit --container > existing container lookup > new name for creation
    # Exit codes from helpers: 0=found, 1=not found, 2=multiple matches (abort)
    local resolved_container_name
    local find_rc
    if [[ -n "$container_name" ]]; then
        # Explicit name provided via --container
        resolved_container_name="$container_name"
    else
        # Try to find existing container for this workspace using shared lookup helper
        # Lookup order: label match -> new naming -> legacy hash naming
        if resolved_container_name=$(_cai_find_workspace_container "$resolved_workspace" "$selected_context"); then
            : # Found existing container (exit code 0)
        else
            find_rc=$?
            # Exit code 2 means multiple containers - abort with error (already printed)
            if [[ $find_rc -eq 2 ]]; then
                return 1
            fi
            # Exit code 1 means not found - get name for new container
            # Use _cai_resolve_container_name for duplicate-aware naming
            if resolved_container_name=$(_cai_resolve_container_name "$resolved_workspace" "$selected_context"); then
                : # Got name for creation
            else
                find_rc=$?
                # Exit code 2 means multiple containers (should not happen but handle it)
                if [[ $find_rc -eq 2 ]]; then
                    return 1
                fi
                echo "[ERROR] Failed to resolve container name for workspace: $resolved_workspace" >&2
                return 1
            fi
        fi
    fi

    # Handle --dry-run flag: delegate to _containai_start_container with --shell --dry-run
    if [[ "$dry_run_flag" == "true" ]]; then
        local -a dry_run_args=()
        dry_run_args+=(--data-volume "$resolved_volume")
        dry_run_args+=(--workspace "$resolved_workspace")
        dry_run_args+=(--shell)
        dry_run_args+=(--dry-run)
        # Always pass resolved name to ensure single-sourced naming
        dry_run_args+=(--name "$resolved_container_name")
        if [[ -n "$image_tag" ]]; then
            dry_run_args+=(--image-tag "$image_tag")
        fi
        if [[ -n "$explicit_config" ]]; then
            dry_run_args+=(--config "$explicit_config")
        fi
        if [[ "$fresh_flag" == "true" ]]; then
            dry_run_args+=(--fresh)
        fi
        if [[ "$force_flag" == "true" ]]; then
            dry_run_args+=(--force)
        fi
        if [[ "$debug_flag" == "true" ]]; then
            dry_run_args+=(--debug)
        fi
        if [[ "$quiet_flag" == "true" ]]; then
            dry_run_args+=(--quiet)
        fi
        _containai_start_container "${dry_run_args[@]}"
        return $?
    fi

    # Handle --fresh flag: remove and recreate container
    if [[ "$fresh_flag" == "true" ]]; then
        # Check if container exists
        if "${docker_cmd[@]}" inspect --type container "$resolved_container_name" >/dev/null 2>&1; then
            # Verify ownership before removing
            local fresh_label_val fresh_image_fallback
            fresh_label_val=$("${docker_cmd[@]}" inspect --format '{{index .Config.Labels "containai.managed"}}' "$resolved_container_name" 2>/dev/null) || fresh_label_val=""
            if [[ "$fresh_label_val" != "true" ]]; then
                fresh_image_fallback=$("${docker_cmd[@]}" inspect --format '{{.Config.Image}}' "$resolved_container_name" 2>/dev/null) || fresh_image_fallback=""
                if [[ "$fresh_image_fallback" != "${_CONTAINAI_DEFAULT_REPO}:"* ]]; then
                    echo "[ERROR] Cannot use --fresh - container '$resolved_container_name' was not created by ContainAI" >&2
                    echo "Remove the conflicting container manually if needed: docker rm -f '$resolved_container_name'" >&2
                    return 1
                fi
            fi

            if [[ "$quiet_flag" != "true" ]]; then
                echo "Removing existing container (--fresh)..."
            fi

            # Get SSH port before removal for cleanup
            local fresh_ssh_port
            fresh_ssh_port=$(_cai_get_container_ssh_port "$resolved_container_name" "$selected_context") || fresh_ssh_port=""

            # Stop and remove container
            local fresh_stop_output fresh_rm_output
            fresh_stop_output=$("${docker_cmd[@]}" stop "$resolved_container_name" 2>&1) || {
                if ! printf '%s' "$fresh_stop_output" | grep -qiE "is not running"; then
                    echo "$fresh_stop_output" >&2
                fi
            }
            fresh_rm_output=$("${docker_cmd[@]}" rm "$resolved_container_name" 2>&1) || {
                if ! printf '%s' "$fresh_rm_output" | grep -qiE "no such container|not found"; then
                    echo "$fresh_rm_output" >&2
                    return 1
                fi
            }

            # Clean up SSH configuration
            if [[ -n "$fresh_ssh_port" ]]; then
                _cai_cleanup_container_ssh "$resolved_container_name" "$fresh_ssh_port"
            fi
        fi

        # Create new container using _containai_start_container with --detached
        # This creates the container without attaching (we'll SSH into it after)
        if [[ "$quiet_flag" != "true" ]]; then
            echo "Creating new container..."
        fi

        local -a create_args=()
        create_args+=(--data-volume "$resolved_volume")
        create_args+=(--workspace "$resolved_workspace")
        create_args+=(--detached)
        # Always pass resolved name to ensure single-sourced naming
        create_args+=(--name "$resolved_container_name")
        if [[ -n "$image_tag" ]]; then
            create_args+=(--image-tag "$image_tag")
        fi
        if [[ -n "$explicit_config" ]]; then
            create_args+=(--config "$explicit_config")
        fi
        if [[ "$force_flag" == "true" ]]; then
            create_args+=(--force)
        fi
        if [[ "$quiet_flag" == "true" ]]; then
            create_args+=(--quiet)
        fi

        if ! _containai_start_container "${create_args[@]}"; then
            echo "[ERROR] Failed to create container" >&2
            return 1
        fi
    fi

    # Check if container exists; if not, create it first
    if ! "${docker_cmd[@]}" inspect --type container "$resolved_container_name" >/dev/null 2>&1; then
        if [[ "$quiet_flag" != "true" ]]; then
            echo "Container not found, creating..."
        fi

        local -a create_args=()
        create_args+=(--data-volume "$resolved_volume")
        create_args+=(--workspace "$resolved_workspace")
        create_args+=(--detached)
        # Always pass resolved name to ensure single-sourced naming
        create_args+=(--name "$resolved_container_name")
        if [[ -n "$image_tag" ]]; then
            create_args+=(--image-tag "$image_tag")
        fi
        if [[ -n "$explicit_config" ]]; then
            create_args+=(--config "$explicit_config")
        fi
        if [[ "$force_flag" == "true" ]]; then
            create_args+=(--force)
        fi
        if [[ "$quiet_flag" == "true" ]]; then
            create_args+=(--quiet)
        fi

        if ! _containai_start_container "${create_args[@]}"; then
            echo "[ERROR] Failed to create container" >&2
            return 1
        fi
    else
        # Container exists - validate ownership and workspace match before connecting
        # Check ownership (label or image fallback)
        local shell_label_val shell_image_val
        shell_label_val=$("${docker_cmd[@]}" inspect --format '{{index .Config.Labels "containai.managed"}}' "$resolved_container_name" 2>/dev/null) || shell_label_val=""
        if [[ "$shell_label_val" != "true" ]]; then
            shell_image_val=$("${docker_cmd[@]}" inspect --format '{{.Config.Image}}' "$resolved_container_name" 2>/dev/null) || shell_image_val=""
            if [[ "$shell_image_val" != "${_CONTAINAI_DEFAULT_REPO}:"* ]]; then
                echo "[ERROR] Container '$resolved_container_name' was not created by ContainAI" >&2
                return 15
            fi
        fi

        # Validate workspace match via FR-4 mount validation
        # This ensures the container's workspace mount matches the resolved workspace
        if ! _containai_validate_fr4_mounts "$selected_context" "$resolved_container_name" "$resolved_workspace" "$resolved_volume" "true"; then
            echo "[ERROR] Container workspace does not match. Use --fresh to recreate." >&2
            return 1
        fi
    fi

    # Connect via SSH
    local quiet_arg=""
    local force_arg=""
    if [[ "$quiet_flag" == "true" ]]; then
        quiet_arg="true"
    fi
    if [[ "$fresh_flag" == "true" ]]; then
        force_arg="true"
    fi

    _cai_ssh_shell "$resolved_container_name" "$selected_context" "$force_arg" "$quiet_arg"
}

# Default (run container) handler
_containai_run_cmd() {
    local cli_volume=""
    local workspace=""
    local explicit_config=""
    local container_name=""
    local image_tag=""
    local cli_memory=""
    local cli_cpus=""
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
    local dry_run_flag=""
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
            --container)
                if [[ -z "${2-}" ]]; then
                    echo "[ERROR] --container requires a value" >&2
                    return 1
                fi
                container_name="$2"
                shift 2
                ;;
            --container=*)
                container_name="${1#--container=}"
                if [[ -z "$container_name" ]]; then
                    echo "[ERROR] --container requires a value" >&2
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
            --detached | -d)
                detached_flag="--detached"
                shift
                ;;
            --quiet | -q)
                quiet_flag="--quiet"
                shift
                ;;
            --debug | -D)
                debug_flag="--debug"
                shift
                ;;
            --dry-run)
                dry_run_flag="--dry-run"
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
            --memory)
                if [[ -z "${2-}" ]]; then
                    echo "[ERROR] --memory requires a value" >&2
                    return 1
                fi
                cli_memory="$2"
                shift 2
                ;;
            --memory=*)
                cli_memory="${1#--memory=}"
                if [[ -z "$cli_memory" ]]; then
                    echo "[ERROR] --memory requires a value" >&2
                    return 1
                fi
                shift
                ;;
            --cpus)
                if [[ -z "${2-}" ]]; then
                    echo "[ERROR] --cpus requires a value" >&2
                    return 1
                fi
                cli_cpus="$2"
                shift 2
                ;;
            --cpus=*)
                cli_cpus="${1#--cpus=}"
                if [[ -z "$cli_cpus" ]]; then
                    echo "[ERROR] --cpus requires a value" >&2
                    return 1
                fi
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
            --volume | -v | --volume=* | -v*)
                # FR-4: Extra volume mounts are not allowed in containai run
                # Only workspace + named data volume are permitted
                echo "[ERROR] --volume is not supported in containai run" >&2
                echo "[INFO] FR-4 restricts mounts to workspace + data volume only" >&2
                echo "[INFO] Use 'containai shell' if you need extra mounts" >&2
                return 1
                ;;
            --help | -h)
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

    # Resolve workspace using platform-aware normalization
    local resolved_workspace workspace_input
    workspace_input="${workspace:-$PWD}"
    resolved_workspace=$(_cai_normalize_path "$workspace_input")
    # Check if path exists (normalize_path returns as-is for non-existent paths)
    if [[ ! -d "$resolved_workspace" ]]; then
        echo "[ERROR] Workspace path does not exist: $workspace_input" >&2
        return 1
    fi

    # Resolve volume
    local resolved_volume
    if ! resolved_volume=$(_containai_resolve_volume "$cli_volume" "$resolved_workspace" "$explicit_config"); then
        echo "[ERROR] Failed to resolve data volume" >&2
        return 1
    fi

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
    if [[ -n "$dry_run_flag" ]]; then
        start_args+=("$dry_run_flag")
    fi
    if [[ -n "$image_tag" ]]; then
        start_args+=(--image-tag "$image_tag")
    fi

    # Set CLI resource overrides (global vars read by _containai_start_container)
    # Clear first to prevent leakage from previous invocations in same shell
    _CAI_CLI_MEMORY="$cli_memory"
    _CAI_CLI_CPUS="$cli_cpus"

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

    # Run rate-limited update check before command dispatch
    # Skip in CI environments to avoid noise/delays in automated pipelines
    # Per spec: CI=true (explicit), GITHUB_ACTIONS (presence), JENKINS_URL (presence)
    # Skip for help/version to avoid latency on informational commands
    if [[ "${CI:-}" != "true" ]] && [[ -z "${GITHUB_ACTIONS:-}" ]] && [[ -z "${JENKINS_URL:-}" ]]; then
        case "$subcommand" in
            help|-h|--help|version|--version|-v) ;;
            *) _cai_update_check ;;
        esac
    fi

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
        docker)
            shift
            _containai_docker_cmd "$@"
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
        ssh)
            shift
            _containai_ssh_cmd "$@"
            ;;
        links)
            shift
            _containai_links_cmd "$@"
            ;;
        sandbox)
            shift
            _containai_sandbox_cmd "$@"
            ;;
        update)
            shift
            _cai_update "$@"
            ;;
        uninstall)
            shift
            _cai_uninstall "$@"
            ;;
        help | -h | --help)
            _containai_help
            ;;
        version | --version | -v)
            shift
            _cai_version "$@"
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
