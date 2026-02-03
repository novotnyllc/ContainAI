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
#   sync         (In-container) Move local configs to data volume with symlinks
#   stop         Stop ContainAI containers
#   completion   Generate shell completion scripts (bash, zsh)
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
        && [[ -f "$_CAI_SCRIPT_DIR/lib/links.sh" ]] \
        && [[ -f "$_CAI_SCRIPT_DIR/lib/sync.sh" ]] \
        && [[ -f "$_CAI_SCRIPT_DIR/lib/registry.sh" ]] \
        && [[ -f "$_CAI_SCRIPT_DIR/lib/template.sh" ]] \
        && [[ -f "$_CAI_SCRIPT_DIR/lib/network.sh" ]] \
        && [[ -f "$_CAI_SCRIPT_DIR/lib/docker-context-sync.sh" ]]
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

if ! source "$_CAI_SCRIPT_DIR/lib/network.sh"; then
    echo "[ERROR] Failed to source lib/network.sh" >&2
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

if ! source "$_CAI_SCRIPT_DIR/lib/sync.sh"; then
    echo "[ERROR] Failed to source lib/sync.sh" >&2
    return 1
fi

if ! source "$_CAI_SCRIPT_DIR/lib/registry.sh"; then
    echo "[ERROR] Failed to source lib/registry.sh" >&2
    return 1
fi

if ! source "$_CAI_SCRIPT_DIR/lib/template.sh"; then
    echo "[ERROR] Failed to source lib/template.sh" >&2
    return 1
fi

if ! source "$_CAI_SCRIPT_DIR/lib/docker-context-sync.sh"; then
    echo "[ERROR] Failed to source lib/docker-context-sync.sh" >&2
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
  exec          Run a command in container via SSH
  doctor        Check system capabilities and show diagnostics
  setup         Configure secure container isolation (Linux/WSL2/macOS)
  validate      Validate Secure Engine configuration
  docker        Run docker with ContainAI context (defaults to containai-docker if present)
  sandbox       (Deprecated - use 'cai stop && cai --restart')
  import        Sync host configs to data volume
  export        Export data volume to .tgz archive
  sync          (In-container) Move local configs to data volume with symlinks
  stop          Stop ContainAI containers
  status        Show container status and resource usage
  gc            Garbage collection for stale containers and images
  ssh           Manage SSH configuration (cleanup stale configs)
  links         Verify and repair container symlinks
  config        Manage settings (list/get/set/unset with workspace scope)
  completion    Generate shell completion scripts (bash, zsh)
  version       Show current version
  update        Update ContainAI installation
  refresh       Pull latest base image and optionally rebuild template
              (also available as --refresh)
  uninstall     Clean removal of system-level components
  help          Show this help message

Run Options:
  <path>                Workspace path (positional, alternative to --workspace)
  --data-volume <vol>   Data volume name (overrides config)
  --config <path>       Config file path (overrides auto-discovery)
  --workspace <path>    Workspace path (default: current directory)
  --container <name>    Use or create container with specified name
                        (uses existing if found, creates new if missing;
                        mutually exclusive with --workspace/--data-volume)
  --template <name>     Template name for container build (default: "default")
                        Templates customize the container Dockerfile
  --channel <channel>   Release channel: stable or nightly (default: stable)
                        Sets base image for template build
  --image-tag <tag>     Image tag (advanced/debugging, ignored with --template)
  --memory <size>       Memory limit (e.g., "4g", "8g") - overrides config
  --cpus <count>        CPU limit (e.g., 2, 4) - overrides config
  --fresh               Remove and recreate container (preserves data volume)
  --restart             Force recreate container (alias for --fresh)
  --reset               Reset workspace state (generates new unique volume name)
  --force               Skip isolation checks (for testing only)
  --detached, -d        Run in background
  --quiet, -q           Suppress verbose output
  --verbose             Enable verbose output (status/progress messages)
  --dry-run             Show what would happen without executing (machine-parseable)
  -e, --env <VAR=val>   Set environment variable (repeatable)
  -- <args>             Pass arguments to agent

Container Lifecycle:
  Containers use tini (--init) as PID 1 for proper zombie reaping, running sleep infinity.
  Agent sessions attach via docker exec. Container stays running between sessions.
  Same workspace path always maps to same container (deterministic naming via hash).

Subcommands:
  acp proxy <agent>     Start ACP proxy for editor integration
                        Agents: claude, gemini
                        Example: cai acp proxy claude

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
  cai exec ls -la                   Run a command in container
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
  - SSH: agent forwarding (ssh -A) preferred; keys NOT imported by default
    (add ~/.ssh to [import].additional_paths in containai.toml if needed)

Volume-Only Mode (no workspace path or --container):
  Syncs configs to data volume only. Does not affect running containers.
  Use this to prepare configs before starting a container.

Options:
  <path>                Workspace path (positional) - enables hot-reload mode
  --workspace <path>    Workspace path (alternative to positional)
  --container <name>    Target specific existing container (must already exist)
                        Mutually exclusive with --workspace and --data-volume
  --data-volume <vol>   Data volume name (overrides config)
  --from <path>         Import source:
                        - Directory: syncs from that directory (default: $HOME)
                        - Archive (.tgz): restores archive to volume (idempotent)
  --config <path>       Config file path (overrides auto-discovery)
  --dry-run             Preview changes without applying
  --no-excludes         Skip exclude patterns from config
  --no-secrets          Skip syncing entries marked as secrets (OAuth tokens, API keys).
                        Does NOT affect --credentials flag or additional_paths.
                        Note: Has no effect with --from archive.tgz (restores bypass sync).
                        Note: [import].additional_paths are NOT auto-classified as secrets.
  --verbose             Show verbose output including skipped source files
  -h, --help            Show this help message

Note: ~/.claude/.credentials.json and ~/.codex/auth.json are NOT imported from
your home profile by default (containers should run their own login flows).
Symlinks are created so containers can write their own tokens after login.

Note: ~/.ssh is NOT imported by default. To import SSH keys, add ~/.ssh to
[import].additional_paths in containai.toml. Agent forwarding (ssh -A) is preferred.
Warning: additional_paths are NOT marked as secrets; --no-secrets will NOT skip them.

Secret files skipped by --no-secrets (examples):
  - ~/.claude.json (Claude OAuth - credentials.json NOT imported from profile)
  - ~/.gemini/google_accounts.json, oauth_creds.json (Gemini OAuth)
  - ~/.local/share/opencode/auth.json (OpenCode auth)
  - ~/.config/gh/hosts.yml (GitHub CLI OAuth tokens)
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
  --container <name>    Target specific existing container (must already exist)
                        Mutually exclusive with --workspace and --data-volume
  --data-volume <vol>   Data volume name (overrides config)
  --config <path>       Config file path (overrides auto-discovery)
  --workspace <path>    Workspace path for config resolution
  --no-excludes         Skip exclude patterns from config
  --verbose             Enable verbose output
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
  --container <name>  Stop specific existing container (must already exist)
  --all               Stop all containers without prompting (mutually exclusive with --container and --export)
  --export            Export data volume before stopping (mutually exclusive with --all)
  --remove            Also remove containers (not just stop them)
                      When used with --remove, SSH configs are automatically cleaned
  --force             Skip session warning prompt (proceed without confirmation)
                      Also continue stopping if export fails when --export is used
  --verbose           Enable verbose output
  -h, --help          Show this help message

Session Warning:
  When stopping a specific container (via --container or workspace-resolved),
  active sessions (SSH connections or terminals) are detected and you will be
  prompted to confirm before stopping. Use --force to skip this prompt.
  In non-interactive mode (piped input), the warning is skipped automatically.
  Note: Interactive selection mode and --all do not perform session detection.

Export Before Stop:
  When --export is used, the container's data volume is exported before stopping.
  The order of operations is: export → session check (unless --force) → stop.
  If export fails, the stop is aborted unless --force is used.
  Works with --container, workspace-resolved containers, or interactive selection.

Examples:
  cai stop                      Interactive selection to stop containers
  cai stop --container my-proj  Stop specific container
  cai stop --all                Stop all ContainAI containers
  cai stop --export             Export data volume before stopping
  cai stop --export --force     Export then stop, continue even if export fails
  cai stop --remove             Remove containers (cleans up SSH configs)
  cai stop --all --remove       Remove all ContainAI containers
  cai stop --force              Stop without session warning prompt
EOF
}

_containai_status_help() {
    cat <<'EOF'
ContainAI Status - Show container status and resource usage

Usage: cai status [options]

Options:
  --workspace <path>  Show status for container associated with workspace
  --container <name>  Show status for specific container (must already exist)
  --json              Output in JSON format
  --verbose           Enable verbose output
  -h, --help          Show this help message

Container Resolution:
  Without --workspace or --container, uses current directory to find container.
  The command looks for a running or stopped ContainAI container.

Output Fields:
  Required: container name, status, image
  Best-effort (5s timeout): uptime, sessions, memory, cpu

Examples:
  cai status                      Show status for current workspace container
  cai status --container my-proj  Show status for specific container
  cai status --json               Output in JSON format
  cai status --workspace ~/proj   Show status for specific workspace
EOF
}

_containai_gc_help() {
    cat <<'EOF'
ContainAI GC - Garbage collection for stale containers and images

Usage: cai gc [options]

Options:
  --dry-run           Preview what would be removed without removing
  --force             Skip confirmation prompt
  --age <duration>    Minimum age for pruning (default: 30d)
                      Format: Nd (days), Nh (hours), e.g., 7d, 24h
  --images            Also prune unused ContainAI images
  --verbose           Enable verbose output
  -h, --help          Show this help message

Staleness Metric:
  For stopped containers (status=exited): uses State.FinishedAt
  For never-ran containers (status=created): uses Created timestamp

Protection Rules:
  - Never prunes running containers
  - Never prunes containers with containai.keep=true label
  - Only prunes containers with containai.managed=true label
  - Operates on current Docker context only

Image Pruning (--images):
  Prunes unused images matching these prefixes:
  - containai:* (local builds)
  - ghcr.io/containai/* (official registry)
  Only removes images NOT in use by any container.

Examples:
  cai gc                     Interactive: list candidates and confirm
  cai gc --dry-run           Preview without removing
  cai gc --force             Skip confirmation
  cai gc --age 7d            Prune containers older than 7 days
  cai gc --images            Also prune unused images
  cai gc --force --images    Remove stale containers and images
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
  --container <name>    Use or create container with specified name
                        (uses existing if found, creates new if missing;
                        mutually exclusive with --workspace/--data-volume)
  --template <name>     Template name for container build (default: "default")
                        Templates customize the container Dockerfile
  --channel <channel>   Release channel: stable or nightly (default: stable)
                        Sets base image for template build
  --image-tag <tag>     Image tag (advanced/debugging, ignored with --template)
  --memory <size>       Memory limit (e.g., "4g", "8g") - overrides config
  --cpus <count>        CPU limit (e.g., 2, 4) - overrides config
  --fresh               Remove and recreate container (preserves data volume)
  --restart             Alias for --fresh
  --reset               Reset workspace state (generates new unique volume name,
                        removes container; never uses default volume)
  --force               Skip isolation checks (for testing only)
  --dry-run             Show what would happen without executing (machine-parseable)
  -q, --quiet           Suppress verbose output
  --verbose             Print container and volume names to stderr
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
  cai shell --container foo    Use or create container named 'foo'
  cai shell --fresh            Recreate container with fresh SSH keys
  cai shell --dry-run          Show what would happen (machine-parseable)
  ssh <container-name>         Direct SSH access (after cai shell setup)
EOF
}

_containai_exec_help() {
    cat <<'EOF'
ContainAI Exec - Run a command in container via SSH

Usage: cai exec [options] [--] <command> [args...]

Runs an arbitrary command in the container via SSH.
If no container exists, creates one first.
If container exists but is stopped, starts it first.

The command runs in a login shell (bash -lc) which sources /etc/profile
and one of ~/.bash_profile, ~/.bash_login, or ~/.profile (first found).
Note: ~/.bashrc is NOT sourced by bash login shells unless explicitly sourced.

Options:
  --workspace <path>    Workspace path (default: current directory)
  -w <path>             Short form of --workspace
  --container <name>    Use or create container with specified name
                        (mutually exclusive with --workspace/--data-volume)
  --template <name>     Template name for container build (default: "default")
  --channel <channel>   Release channel: stable or nightly (default: stable)
                        Sets base image for template build
  --data-volume <vol>   Data volume name (overrides config)
  --config <path>       Config file path (overrides auto-discovery)
  --fresh               Remove and recreate container (preserves data volume)
  --force               Skip isolation checks (for testing only)
  -q, --quiet           Suppress verbose output
  --verbose             Enable verbose output
  -h, --help            Show this help message
  --                    Separator between cai options and command

TTY Handling:
  - Automatically allocates a PTY if stdin is a TTY
  - Streams stdout/stderr in real-time
  - Exit code from the command is passed through

Exit Codes:
  0    Command completed successfully
  1    General error (container creation, config parsing, etc.)
  11   Container failed to start
  12   SSH setup failed
  13   SSH connection failed after retries
  14   Host key mismatch could not be auto-recovered
  15   Container exists but not owned by ContainAI
  *    Exit code from the remote command itself

Examples:
  cai exec ls -la                    List files in workspace
  cai exec echo hello                Simple command
  cai exec false                     Returns exit code 1
  cai exec -- --help                 Run "--help" as command (uses -- separator)
  cai exec -w /path/to/project pwd   Exec in specific workspace
  cai exec --container foo ls        Exec in container named 'foo'
EOF
}

_containai_config_help() {
    cat <<'EOF'
ContainAI Config - Manage settings with workspace-aware scope

Usage: cai config <subcommand> [options]

Subcommands:
  list                          Show all settings with source
  get <key>                     Get effective value with source
  set <key> <value>             Set value (workspace if in one, else global)
  unset <key>                   Remove setting

Scoping Options:
  -g, --global                  Force global scope for set/unset
  --workspace <path>            Apply to specific workspace
  --verbose                     Enable verbose output

Workspace-scoped keys (saved per workspace):
  data_volume                   Data volume name

Global keys (saved in user config):
  agent.default                 Default agent (also accepts "agent" as alias)
  ssh.forward_agent             Enable SSH agent forwarding
  ssh.port_range_start          SSH port range start
  ssh.port_range_end            SSH port range end
  import.auto_prompt            Prompt for import on new volume

Source column values:
  cli                           From command-line flag
  env                           From environment variable
  workspace:<path>              From workspace state
  repo-local                    From .containai/config.toml
  user-global                   From ~/.config/containai/config.toml
  default                       Built-in default

Examples:
  cai config list                        Show all settings
  cai config get agent                   Get effective agent (alias for agent.default)
  cai config set agent.default claude    Set global default agent
  cai config set data_volume my-vol      Set data_volume for current workspace
  cai config unset data_volume           Remove workspace data_volume
  cai config unset -g ssh.forward_agent  Remove global ssh.forward_agent
  cai config set --workspace /path data_volume my-vol
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
  --verbose     Enable verbose output
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

_containai_template_help() {
    cat <<'EOF'
ContainAI Template - Manage container templates

Usage: cai template <subcommand> [options]

Subcommands:
  upgrade [name]        Upgrade template(s) to use ARG BASE_IMAGE pattern
                        This enables channel selection (--channel stable|nightly)

Options:
  --dry-run             Show what would change without modifying files
  -h, --help            Show this help message

What 'upgrade' does:
  - Scans template Dockerfiles for hardcoded FROM lines
  - Adds ARG BASE_IMAGE=<current-image> before FROM
  - Rewrites FROM to use ${BASE_IMAGE}
  - Preserves all other template content

Examples:
  cai template upgrade              Upgrade all templates
  cai template upgrade default      Upgrade only the 'default' template
  cai template upgrade --dry-run    Preview changes without modifying
EOF
}

_containai_doctor_help() {
    local platform
    platform=$(_cai_detect_platform)

    cat <<'EOF'
ContainAI Doctor - Check system capabilities and diagnostics

Usage: cai doctor [options]
       cai doctor fix [--all | volume [--all|<name>] | container [--all|<name>] | template [--all|<name>]]

Checks Docker availability and Sysbox isolation configuration.
Reports requirement levels and actionable remediation guidance.

Requirements:
  Sysbox: REQUIRED - cai run requires Sysbox for container isolation
  SSH: REQUIRED - cai shell/run use SSH for container access

Options:
  --json              Output machine-parseable JSON
  --build-templates   Run heavy template validation (actual docker build)
EOF

    # Show --reset-lima option only on macOS
    if [[ "$platform" == "macos" ]]; then
        cat <<'EOF'
  --reset-lima    Delete Lima VM and Docker context (requires confirmation)
EOF
    fi

    cat <<'EOF'
  -h, --help      Show this help message

Subcommands:
  fix             Auto-fix issues (see below for targets)

Fix Targets:
  fix                           Show available fix targets
  fix --all                     Fix everything fixable
  fix volume                    List volumes, offer to fix
  fix volume --all              Fix all volumes
  fix volume <name>             Fix specific volume
  fix container                 List containers, offer to fix
  fix container --all           Fix all containers (including SSH key auth)
  fix container <name>          Fix specific container
  fix template                  Restore default template from repo
  fix template <name>           Restore specific template from repo
  fix template --all            Restore all repo-shipped templates

Exit Codes:
  0    All checks pass (Sysbox, SSH, and templates OK)
  1    Checks failed (run 'cai setup' to configure)

What 'fix' can remediate:
  - Missing SSH key (regenerates)
  - Missing SSH config directory (creates)
  - Missing Include directive (adds to ~/.ssh/config)
  - Stale SSH configs (removes orphaned container configs)
  - Wrong file permissions (fixes to 700/600 as appropriate)
  - Container SSH configuration refresh
  - Missing/corrupted templates (restores from repo)

What 'fix' cannot remediate (requires manual action):
  - Sysbox not installed (use 'cai setup')
  - Docker context not configured (use 'cai setup')
  - Kernel version incompatible
  - Docker daemon not running
EOF

    # Show volume fix info (Linux/WSL2 only)
    if [[ "$platform" != "macos" ]]; then
        cat <<'EOF'

What 'fix volume' can fix (Linux/WSL2 only):
  - Volume ownership corruption (files showing nobody:nogroup)
  - Requires sudo for chown operations
  - Only operates on volumes under /var/lib/containai-docker/volumes
  - Only affects containers with label containai.managed=true
  - Warns if rootfs is tainted (suggests container recreation)
  - Not supported on macOS (volumes are inside Lima VM)
EOF
    else
        cat <<'EOF'

Note: 'fix volume' is only available on Linux/WSL2 (not macOS).
Volumes are inside the Lima VM on macOS.
EOF
    fi

    cat <<'EOF'

Examples:
  cai doctor                        Run all checks, show formatted report
  cai doctor --json                 Output JSON for scripts/automation
  cai doctor fix                    Show available fix targets
  cai doctor fix --all              Fix everything
  cai doctor fix container --all    Fix SSH config for all containers
  cai doctor fix container myname   Fix SSH config for specific container
EOF

    # Show volume fix examples (Linux/WSL2 only)
    if [[ "$platform" != "macos" ]]; then
        cat <<'EOF'
  cai doctor fix volume --all       Repair all managed volumes
  cai doctor fix volume myvolume    Repair specific volume
EOF
    fi
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
  --verbose             Enable verbose output
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

_containai_completion_help() {
    cat <<'EOF'
ContainAI Completion - Generate shell completion scripts

Usage: cai completion <shell>

Shells:
  bash          Output bash completion script
  zsh           Output zsh completion script

Examples:
  cai completion bash                    Print bash completion script
  cai completion zsh                     Print zsh completion script

Installation:
  Bash (add to ~/.bashrc):
    source <(cai completion bash)
    # Or save to a file:
    cai completion bash > ~/.local/share/bash-completion/completions/cai

  Zsh (add to ~/.zshrc):
    source <(cai completion zsh)
    # Or save to a file (ensure fpath includes the directory):
    cai completion zsh > ~/.zfunc/_cai

Notes:
  - Completion scripts are static and can be saved to a file for faster loading
  - Dynamic completion for --container and --data-volume uses cached Docker lookups
  - Docker lookups timeout after 500ms to ensure fast completion
  - Results are cached for 5 seconds to improve responsiveness
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
    local verbose="false"
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
            --verbose)
                verbose="true"
                _cai_set_verbose
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
        # Use multi-context lookup to find container (default, config-specified, secure)
        # Pass PWD as workspace hint for config-based context discovery
        local found_context find_rc
        if found_context=$(_cai_find_container_by_name "$container_name" "$explicit_config" "$PWD"); then
            selected_context="$found_context"
        else
            find_rc=$?
            if [[ $find_rc -eq 2 ]] || [[ $find_rc -eq 3 ]]; then
                return 1  # Error already printed (ambiguity or config parse)
            fi
            echo "[ERROR] Container not found: $container_name" >&2
            return 1
        fi

        # Build docker command with context (always use --context, even for "default")
        local -a docker_cmd=(docker --context "$selected_context")

        # Check if container is managed by ContainAI
        # Use {{with}} template to output empty string for missing labels (avoids <no value>)
        # Clear DOCKER_CONTEXT/DOCKER_HOST to ensure --context takes effect
        local is_managed
        is_managed=$(DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" inspect --type container --format '{{with index .Config.Labels "containai.managed"}}{{.}}{{end}}' -- "$container_name" 2>/dev/null) || is_managed=""
        if [[ "$is_managed" != "true" ]]; then
            echo "[ERROR] Container $container_name exists but is not managed by ContainAI" >&2
            return 1
        fi

        # Derive workspace from container labels
        resolved_workspace=$(DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" inspect --type container --format '{{with index .Config.Labels "containai.workspace"}}{{.}}{{end}}' -- "$container_name" 2>/dev/null) || resolved_workspace=""
        if [[ -z "$resolved_workspace" ]]; then
            echo "[ERROR] Container $container_name is missing workspace label" >&2
            return 1
        fi

        # Derive data volume from container labels
        resolved_volume=$(DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" inspect --type container --format '{{with index .Config.Labels "containai.data-volume"}}{{.}}{{end}}' -- "$container_name" 2>/dev/null) || resolved_volume=""
        if [[ -z "$resolved_volume" ]]; then
            echo "[ERROR] Container $container_name is missing data-volume label" >&2
            return 1
        fi
    else
        # Standard mode: resolve from workspace path
        local workspace_input strict_mode
        workspace_input="${workspace:-$PWD}"

        # First normalize to check if path exists
        local normalized_input
        normalized_input=$(_cai_normalize_path "$workspace_input")
        if [[ ! -d "$normalized_input" ]]; then
            echo "[ERROR] Workspace path does not exist: $workspace_input" >&2
            return 1
        fi

        # Determine if explicit --workspace was provided (strict mode for nesting check)
        if [[ -n "$workspace" ]]; then
            strict_mode="strict"
        else
            strict_mode=""
        fi

        # === CONTEXT SELECTION (before nesting check - need context for docker label lookup) ===
        # Resolve secure engine context from config (for context override)
        # Use normalized_input for initial config resolution
        local config_context_override=""
        if [[ -n "$explicit_config" ]]; then
            # Explicit config: strict mode - fail on parse errors
            if ! config_context_override=$(_containai_resolve_secure_engine_context "$normalized_input" "$explicit_config"); then
                echo "[ERROR] Failed to parse config: $explicit_config" >&2
                return 1
            fi
        else
            # Discovered config: suppress errors gracefully
            config_context_override=$(_containai_resolve_secure_engine_context "$normalized_input" "" 2>/dev/null) || config_context_override=""
        fi

        # Auto-select Docker context based on Sysbox availability
        # Use DOCKER_CONTEXT= DOCKER_HOST= prefix for shell function call (pitfall: env -u only works with external commands)
        if selected_context=$(DOCKER_CONTEXT= DOCKER_HOST= _cai_select_context "$config_context_override" ""); then
            : # success - selected_context is isolated context (Sysbox)
        else
            echo "[ERROR] No isolation available. Run 'cai doctor' for setup instructions." >&2
            return 1
        fi

        # === NESTED WORKSPACE DETECTION ===
        # Check if this path is nested under an existing workspace (config or container label)
        # If explicit --workspace provided with nested path, error
        # If implicit (cwd), use parent workspace with INFO message
        if ! resolved_workspace=$(_containai_resolve_workspace_with_nesting "$normalized_input" "$selected_context" "$strict_mode"); then
            # Error already printed by _containai_resolve_workspace_with_nesting
            return 1
        fi

        # Resolve volume (using resolved_workspace which may be parent)
        if ! resolved_volume=$(_containai_resolve_volume "$cli_volume" "$resolved_workspace" "$explicit_config"); then
            echo "[ERROR] Failed to resolve data volume" >&2
            return 1
        fi
    fi

    # For hot-reload mode, validate container is running before proceeding
    local resolved_container_name=""
    if [[ "$hot_reload" == "true" ]]; then
        # Build docker command with context (always use --context)
        local -a docker_cmd=(docker --context "$selected_context")

        if [[ -n "$container_name" ]]; then
            # --container was provided, use it directly
            resolved_container_name="$container_name"
        else
            # Try to find container by workspace label first (handles --container containers)
            # Label format: containai.workspace=/absolute/path
            # Use -a to include stopped containers for proper error messages
            local label_filter="containai.workspace=$resolved_workspace"
            local found_containers
            found_containers=$(DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" ps -aq --filter "label=$label_filter" 2>/dev/null | head -2)

            if [[ -n "$found_containers" ]]; then
                # Count matches (filter to first line to handle empty case)
                local match_count
                match_count=$(printf '%s\n' "$found_containers" | grep -c . || echo 0)
                if [[ "$match_count" -gt 1 ]]; then
                    echo "[ERROR] Multiple containers found for workspace: $resolved_workspace" >&2
                    echo "" >&2
                    echo "Containers:" >&2
                    DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" ps -a --filter "label=$label_filter" --format "  {{.Names}} ({{.Status}})" >&2
                    echo "" >&2
                    echo "Use --container to specify which one." >&2
                    return 1
                fi
                # Get container name from ID (take first line only)
                local first_container
                first_container=$(printf '%s\n' "$found_containers" | head -1)
                resolved_container_name=$(DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" inspect --format '{{.Name}}' "$first_container" 2>/dev/null)
                resolved_container_name="${resolved_container_name#/}" # Remove leading /
            else
                # Fallback: use shared lookup order (label → new name → legacy hash)
                # Clear DOCKER_CONTEXT/DOCKER_HOST for consistent behavior with rest of function
                local find_rc
                if resolved_container_name=$(DOCKER_CONTEXT= DOCKER_HOST= _cai_find_workspace_container "$resolved_workspace" "$selected_context"); then
                    : # Found
                else
                    find_rc=$?
                    if [[ $find_rc -eq 2 ]]; then
                        # Multiple containers error already printed
                        return 1
                    fi
                    echo "[ERROR] Container not found for workspace: $resolved_workspace" >&2
                    echo "" >&2
                    echo "To create a container for this workspace, run:" >&2
                    echo "  cai run $resolved_workspace" >&2
                    return 1
                fi
            fi
        fi

        # Check container exists and is running
        local container_state
        if ! container_state=$(DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" inspect --type container --format '{{.State.Status}}' -- "$resolved_container_name" 2>/dev/null); then
            if [[ -n "$container_name" ]]; then
                # --container was explicitly provided
                echo "[ERROR] Container not found: $container_name" >&2
            else
                echo "[ERROR] Container not found for workspace: $resolved_workspace" >&2
                echo "" >&2
                echo "To create a container for this workspace, run:" >&2
                echo "  cai run $resolved_workspace" >&2
            fi
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
    if ! _containai_import "$selected_context" "$resolved_volume" "$dry_run" "$no_excludes" "$resolved_workspace" "$explicit_config" "$from_source" "$no_secrets" "$verbose"; then
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
        _cai_dryrun "Would reload configs into container: $resolved_container_name"
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
    local selected_context=""  # Docker context for --container mode

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
            --verbose)
                _cai_set_verbose
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
        # Use multi-context lookup to find container (config-specified, secure, default)
        # Pass PWD as workspace hint for config-based context discovery
        local find_rc
        if ! selected_context=$(_cai_find_container_by_name "$container_name" "$explicit_config" "$PWD"); then
            find_rc=$?
            if [[ $find_rc -eq 2 ]] || [[ $find_rc -eq 3 ]]; then
                return 1  # Error already printed (ambiguity or config parse)
            fi
            echo "[ERROR] Container not found: $container_name" >&2
            return 1
        fi

        # Build docker command with context (always use --context)
        local -a docker_cmd=(docker --context "$selected_context")

        # Check if container is managed by ContainAI
        # Use {{with}} template to output empty string for missing labels (avoids <no value>)
        # Clear DOCKER_CONTEXT/DOCKER_HOST to ensure --context takes effect
        local is_managed
        is_managed=$(DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" inspect --type container --format '{{with index .Config.Labels "containai.managed"}}{{.}}{{end}}' -- "$container_name" 2>/dev/null) || is_managed=""
        if [[ "$is_managed" != "true" ]]; then
            echo "[ERROR] Container $container_name exists but is not managed by ContainAI" >&2
            return 1
        fi

        # Derive workspace from container labels (for excludes resolution)
        resolved_workspace=$(DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" inspect --type container --format '{{with index .Config.Labels "containai.workspace"}}{{.}}{{end}}' -- "$container_name" 2>/dev/null) || resolved_workspace=""
        if [[ -z "$resolved_workspace" ]]; then
            echo "[ERROR] Container $container_name is missing workspace label" >&2
            return 1
        fi

        # Derive data volume from container labels
        resolved_volume=$(DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" inspect --type container --format '{{with index .Config.Labels "containai.data-volume"}}{{.}}{{end}}' -- "$container_name" 2>/dev/null) || resolved_volume=""
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
    # When --container was used, run in the correct context via env prefix
    if [[ -n "$selected_context" ]]; then
        DOCKER_CONTEXT="$selected_context" DOCKER_HOST= _containai_export "$resolved_volume" "$output_path" "export_excludes" "$no_excludes"
    else
        # Default context or no --container specified
        _containai_export "$resolved_volume" "$output_path" "export_excludes" "$no_excludes"
    fi
}

# Stop subcommand handler
_containai_stop_cmd() {
    local container_name=""
    local remove_flag=false
    local all_flag=false
    local force_flag=false
    local export_first=false
    local arg prev
    # Preserve original args for passing to _containai_stop_all
    local -a orig_args=("$@")

    # Pass 1: Check for help early
    for arg in "$@"; do
        case "$arg" in
            --help | -h)
                _containai_stop_help
                return 0
                ;;
        esac
    done

    # Pass 2: Pre-scan to determine mode and extract values
    # This ensures validation is order-independent
    # Track whether we're expecting a value for --container
    local expect_container_value=false
    for arg in "$@"; do
        # First check if we're expecting a value for --container
        if [[ "$expect_container_value" == "true" ]]; then
            if [[ -z "$arg" ]] || [[ "$arg" == -* ]]; then
                echo "[ERROR] --container requires a value" >&2
                return 1
            fi
            container_name="$arg"
            expect_container_value=false
            continue
        fi

        case "$arg" in
            --name | --name=*)
                echo "[ERROR] --name is no longer supported. Use --container instead." >&2
                return 1
                ;;
            --container)
                # Value expected in next iteration
                expect_container_value=true
                ;;
            --container=*)
                container_name="${arg#--container=}"
                if [[ -z "$container_name" ]]; then
                    echo "[ERROR] --container requires a value" >&2
                    return 1
                fi
                ;;
            --all)
                all_flag=true
                ;;
            --remove)
                remove_flag=true
                ;;
            --force)
                force_flag=true
                ;;
            --export)
                export_first=true
                ;;
            --verbose)
                _cai_set_verbose
                ;;
            # Other args handled in pass 3 (validation pass)
        esac
    done
    # Handle trailing --container without value
    if [[ "$expect_container_value" == "true" ]]; then
        echo "[ERROR] --container requires a value" >&2
        return 1
    fi

    # Check mutual exclusivity of --container and --all
    if [[ -n "$container_name" ]] && [[ "$all_flag" == "true" ]]; then
        echo "[ERROR] --container and --all are mutually exclusive" >&2
        return 1
    fi

    # Check mutual exclusivity of --export and --all
    if [[ "$export_first" == "true" ]] && [[ "$all_flag" == "true" ]]; then
        echo "[ERROR] --export and --all are mutually exclusive" >&2
        return 1
    fi

    # Pass 3: Validate all args based on determined mode
    # In --container or --all mode, reject unknown flags and positional args
    if [[ -n "$container_name" ]] || [[ "$all_flag" == "true" ]]; then
        prev=""
        for arg in "$@"; do
            case "$arg" in
                --container | --all | --remove | --force | --export | --verbose | --help | -h)
                    # Known flags
                    ;;
                --container=*)
                    # Known flag with value
                    ;;
                -*)
                    echo "[ERROR] Unknown option: $arg" >&2
                    echo "Use 'cai stop --help' for usage" >&2
                    return 1
                    ;;
                *)
                    # Check if this is the value for --container
                    if [[ "$prev" != "--container" ]]; then
                        echo "[ERROR] Unexpected argument: $arg" >&2
                        echo "Use 'cai stop --help' for usage" >&2
                        return 1
                    fi
                    ;;
            esac
            prev="$arg"
        done
    fi

    # If --container specified, stop that specific container
    if [[ -n "$container_name" ]]; then
        # Use _cai_find_container_by_name to search configured/secure contexts
        # Pass PWD as workspace hint for config-based context discovery
        local selected_context="" find_rc
        if ! selected_context=$(_cai_find_container_by_name "$container_name" "" "$PWD"); then
            find_rc=$?
            if [[ $find_rc -eq 2 ]] || [[ $find_rc -eq 3 ]]; then
                return 1  # Error already printed (ambiguity or config parse)
            fi
            echo "[ERROR] Container not found: $container_name" >&2
            return 1
        fi

        # Build docker command with context (always use --context, clear env vars)
        local -a docker_cmd=(docker --context "$selected_context")

        # Check if container is managed by ContainAI
        # Clear DOCKER_CONTEXT/DOCKER_HOST to ensure --context takes effect
        local is_managed
        is_managed=$(DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" inspect --type container --format '{{index .Config.Labels "containai.managed"}}' -- "$container_name" 2>/dev/null) || is_managed=""
        if [[ "$is_managed" != "true" ]]; then
            echo "[ERROR] Container $container_name exists but is not managed by ContainAI" >&2
            return 1
        fi

        # Export before stop: run export first (if --export), before session check
        if [[ "$export_first" == "true" ]]; then
            _cai_info "Exporting data volume..."
            # Use --container flag only; export resolves context internally
            if ! _containai_export_cmd --container "$container_name"; then
                if [[ "$force_flag" != "true" ]]; then
                    _cai_error "Export failed. Use --force to stop anyway."
                    return 1
                fi
                _cai_warn "Export failed, continuing due to --force"
            fi
        fi

        # Session warning: prompt if sessions detected (unless --force or non-interactive)
        if [[ "$force_flag" != "true" ]] && [[ -t 0 ]]; then
            local session_result
            _cai_detect_sessions "$container_name" "$selected_context" && session_result=$? || session_result=$?
            if [[ "$session_result" -eq 0 ]]; then
                _cai_warn "Container '$container_name' may have active sessions"
                local confirm
                if ! read -rp "Stop anyway? [y/N]: " confirm; then
                    echo "Cancelled." >&2
                    return 0
                fi
                [[ "$confirm" =~ ^[Yy] ]] || return 1
            fi
            # session_result 1 = no sessions, 2 = unknown: proceed
        fi

        if [[ "$remove_flag" == "true" ]]; then
            # Get SSH port before removing (for cleanup)
            local ssh_port
            ssh_port=$(_cai_get_container_ssh_port "$container_name" "$selected_context" 2>/dev/null) || ssh_port=""

            _cai_info "Removing: $container_name [context: $selected_context]"
            if DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" rm -f -- "$container_name" >/dev/null 2>&1; then
                # Clean up per-container network rules AFTER successful removal
                # (container is stopped, so no egress window during stop grace period)
                _cai_cleanup_container_network "$container_name" "$selected_context"
                # Clean up SSH config
                if [[ -n "$ssh_port" ]]; then
                    _cai_cleanup_container_ssh "$container_name" "$ssh_port"
                else
                    _cai_remove_ssh_host_config "$container_name"
                fi
                _cai_ok "Done."
            else
                _cai_error "Failed to remove container: $container_name"
                return 1
            fi
        else
            _cai_info "Stopping: $container_name [context: $selected_context]"
            if DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" stop -- "$container_name" >/dev/null 2>&1; then
                # Clean up per-container network rules AFTER successful stop
                # (container is stopped, no egress window during stop grace period)
                _cai_cleanup_container_network "$container_name" "$selected_context"
                _cai_ok "Done."
            else
                _cai_error "Failed to stop container: $container_name"
                return 1
            fi
        fi
        return 0
    fi

    # No --container specified
    # Check workspace state for container name (spec: fn-36-rb7.12)
    if [[ "$all_flag" != "true" ]]; then
        local ws_container_name
        ws_container_name=$(_containai_read_workspace_key "$PWD" "container_name" 2>/dev/null) || ws_container_name=""
        if [[ -n "$ws_container_name" ]]; then
            # Found container in workspace state, stop it
            local selected_context="" find_rc
            if ! selected_context=$(_cai_find_container_by_name "$ws_container_name" "" "$PWD"); then
                find_rc=$?
                if [[ $find_rc -eq 2 ]] || [[ $find_rc -eq 3 ]]; then
                    return 1  # Error already printed (ambiguity or config parse)
                fi
                # Container in state but not found - likely already removed
                echo "[WARN] Container from workspace state not found: $ws_container_name" >&2
                return 0
            fi

            local -a docker_cmd=(docker --context "$selected_context")
            local is_managed
            is_managed=$(DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" inspect --type container --format '{{index .Config.Labels "containai.managed"}}' -- "$ws_container_name" 2>/dev/null) || is_managed=""
            if [[ "$is_managed" != "true" ]]; then
                echo "[ERROR] Container $ws_container_name exists but is not managed by ContainAI" >&2
                return 1
            fi

            # Verify container belongs to this workspace (prevent stale state issues)
            local container_ws
            container_ws=$(DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" inspect --type container --format '{{index .Config.Labels "containai.workspace"}}' -- "$ws_container_name" 2>/dev/null) || container_ws=""
            local normalized_pwd
            normalized_pwd=$(_cai_normalize_path "$PWD")
            if [[ -n "$container_ws" && "$container_ws" != "$normalized_pwd" ]]; then
                echo "[ERROR] Container '$ws_container_name' belongs to workspace '$container_ws', not current directory." >&2
                echo "        Use 'cai stop --container $ws_container_name' to force, or fix workspace state." >&2
                return 1
            fi

            # Export before stop: run export first (if --export), before session check
            if [[ "$export_first" == "true" ]]; then
                _cai_info "Exporting data volume..."
                # Use --container flag only; export resolves context internally
                if ! _containai_export_cmd --container "$ws_container_name"; then
                    if [[ "$force_flag" != "true" ]]; then
                        _cai_error "Export failed. Use --force to stop anyway."
                        return 1
                    fi
                    _cai_warn "Export failed, continuing due to --force"
                fi
            fi

            # Session warning: prompt if sessions detected (unless --force or non-interactive)
            if [[ "$force_flag" != "true" ]] && [[ -t 0 ]]; then
                local session_result
                _cai_detect_sessions "$ws_container_name" "$selected_context" && session_result=$? || session_result=$?
                if [[ "$session_result" -eq 0 ]]; then
                    _cai_warn "Container '$ws_container_name' may have active sessions"
                    local confirm
                    if ! read -rp "Stop anyway? [y/N]: " confirm; then
                        echo "Cancelled." >&2
                        return 0
                    fi
                    [[ "$confirm" =~ ^[Yy] ]] || return 1
                fi
                # session_result 1 = no sessions, 2 = unknown: proceed
            fi

            if [[ "$remove_flag" == "true" ]]; then
                local ssh_port
                ssh_port=$(_cai_get_container_ssh_port "$ws_container_name" "$selected_context" 2>/dev/null) || ssh_port=""
                _cai_info "Removing: $ws_container_name [context: $selected_context]"
                if DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" rm -f -- "$ws_container_name" >/dev/null 2>&1; then
                    # Clean up per-container network rules AFTER successful removal
                    _cai_cleanup_container_network "$ws_container_name" "$selected_context"
                    if [[ -n "$ssh_port" ]]; then
                        _cai_cleanup_container_ssh "$ws_container_name" "$ssh_port"
                    else
                        _cai_remove_ssh_host_config "$ws_container_name"
                    fi
                    _cai_ok "Done."
                else
                    _cai_error "Failed to remove container: $ws_container_name"
                    return 1
                fi
            else
                _cai_info "Stopping: $ws_container_name [context: $selected_context]"
                if DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" stop -- "$ws_container_name" >/dev/null 2>&1; then
                    # Clean up per-container network rules AFTER successful stop
                    _cai_cleanup_container_network "$ws_container_name" "$selected_context"
                    _cai_ok "Done."
                else
                    _cai_error "Failed to stop container: $ws_container_name"
                    return 1
                fi
            fi
            return 0
        fi
    fi

    # No workspace state or --all flag, delegate to interactive stop all with original args
    _containai_stop_all "${orig_args[@]}"
}

# Status subcommand - show container status and resource usage
_containai_status_cmd() {
    local container_name=""
    local workspace=""
    local json_flag=false
    local arg prev

    # Pass 1: Check for help early
    for arg in "$@"; do
        case "$arg" in
            --help | -h)
                _containai_status_help
                return 0
                ;;
        esac
    done

    # Pass 2: Parse arguments
    local expect_container_value=false
    local expect_workspace_value=false
    for arg in "$@"; do
        # Handle expected values first
        if [[ "$expect_container_value" == "true" ]]; then
            if [[ -z "$arg" ]] || [[ "$arg" == -* ]]; then
                echo "[ERROR] --container requires a value" >&2
                return 1
            fi
            container_name="$arg"
            expect_container_value=false
            continue
        fi
        if [[ "$expect_workspace_value" == "true" ]]; then
            if [[ -z "$arg" ]] || [[ "$arg" == -* ]]; then
                echo "[ERROR] --workspace requires a value" >&2
                return 1
            fi
            workspace="$arg"
            workspace="${workspace/#\~/$HOME}"
            expect_workspace_value=false
            continue
        fi

        case "$arg" in
            --container)
                expect_container_value=true
                ;;
            --container=*)
                container_name="${arg#--container=}"
                if [[ -z "$container_name" ]]; then
                    echo "[ERROR] --container requires a value" >&2
                    return 1
                fi
                ;;
            --workspace)
                expect_workspace_value=true
                ;;
            --workspace=*)
                workspace="${arg#--workspace=}"
                workspace="${workspace/#\~/$HOME}"
                if [[ -z "$workspace" ]]; then
                    echo "[ERROR] --workspace requires a value" >&2
                    return 1
                fi
                ;;
            --json)
                json_flag=true
                ;;
            --verbose)
                _cai_set_verbose
                ;;
            -*)
                echo "[ERROR] Unknown option: $arg" >&2
                echo "Use 'cai status --help' for usage" >&2
                return 1
                ;;
            *)
                echo "[ERROR] Unexpected argument: $arg" >&2
                echo "Use 'cai status --help' for usage" >&2
                return 1
                ;;
        esac
    done

    # Handle trailing expected values
    if [[ "$expect_container_value" == "true" ]]; then
        echo "[ERROR] --container requires a value" >&2
        return 1
    fi
    if [[ "$expect_workspace_value" == "true" ]]; then
        echo "[ERROR] --workspace requires a value" >&2
        return 1
    fi

    # Check mutual exclusivity
    if [[ -n "$container_name" ]] && [[ -n "$workspace" ]]; then
        echo "[ERROR] --container and --workspace are mutually exclusive" >&2
        return 1
    fi

    # Resolve container name if not provided
    local selected_context=""
    # Effective workspace for context resolution (use --workspace if provided, else PWD)
    local effective_ws="${workspace:-$PWD}"
    if [[ -z "$container_name" ]]; then
        # Look up container from workspace state
        local ws_container_name
        ws_container_name=$(_containai_read_workspace_key "$effective_ws" "container_name" 2>/dev/null) || ws_container_name=""
        if [[ -z "$ws_container_name" ]]; then
            echo "[ERROR] No container found for workspace: $effective_ws" >&2
            echo "Use 'cai status --container <name>' to specify a container" >&2
            return 1
        fi
        container_name="$ws_container_name"
    fi

    # Find container and context (use effective workspace for config discovery)
    local find_rc
    if ! selected_context=$(_cai_find_container_by_name "$container_name" "" "$effective_ws"); then
        find_rc=$?
        if [[ $find_rc -eq 2 ]] || [[ $find_rc -eq 3 ]]; then
            return 1  # Error already printed
        fi
        echo "[ERROR] Container not found: $container_name" >&2
        return 1
    fi

    # Build docker command with context
    local -a docker_cmd=(docker --context "$selected_context")

    # Check if container is managed by ContainAI
    local is_managed
    is_managed=$(DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" inspect --type container --format '{{index .Config.Labels "containai.managed"}}' -- "$container_name" 2>/dev/null) || is_managed=""
    if [[ "$is_managed" != "true" ]]; then
        echo "[ERROR] Container $container_name exists but is not managed by ContainAI" >&2
        return 1
    fi

    # Get required container info using docker inspect --format (no Python dependency)
    local status image started_at
    status=$(DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" inspect --type container --format '{{.State.Status}}' -- "$container_name" 2>/dev/null) || {
        echo "[ERROR] Failed to inspect container: $container_name" >&2
        return 1
    }
    image=$(DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" inspect --type container --format '{{.Config.Image}}' -- "$container_name" 2>/dev/null) || image="unknown"
    started_at=$(DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" inspect --type container --format '{{.State.StartedAt}}' -- "$container_name" 2>/dev/null) || started_at=""

    # Best-effort: Calculate uptime
    local uptime=""
    if [[ "$status" == "running" ]] && [[ -n "$started_at" ]] && [[ "$started_at" != "0001-01-01T00:00:00Z" ]]; then
        uptime=$(python3 -c "
from datetime import datetime, timezone
import sys
try:
    started = sys.argv[1]
    # Handle various timestamp formats
    for fmt in ['%Y-%m-%dT%H:%M:%S.%fZ', '%Y-%m-%dT%H:%M:%SZ', '%Y-%m-%dT%H:%M:%S.%f']:
        try:
            if started.endswith('Z'):
                dt = datetime.strptime(started, fmt)
            else:
                dt = datetime.fromisoformat(started.replace('Z', '+00:00'))
            break
        except ValueError:
            continue
    else:
        dt = datetime.fromisoformat(started.replace('Z', '+00:00'))

    now = datetime.now(timezone.utc)
    dt = dt.replace(tzinfo=timezone.utc)
    diff = now - dt
    days = diff.days
    hours, rem = divmod(diff.seconds, 3600)
    minutes = rem // 60

    if days > 0:
        print(f'{days}d {hours}h {minutes}m')
    elif hours > 0:
        print(f'{hours}h {minutes}m')
    else:
        print(f'{minutes}m')
except Exception:
    pass
" "$started_at" 2>/dev/null) || uptime=""
    fi

    # Best-effort: Get resource usage (5s timeout)
    local mem_usage="" mem_limit="" mem_pct="" cpu_pct=""
    if [[ "$status" == "running" ]]; then
        local stats_output
        if stats_output=$(_cai_timeout 5 env DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" stats --no-stream --format '{{.MemUsage}}|{{.CPUPerc}}' -- "$container_name" 2>/dev/null); then
            # Parse output: "1.2GiB / 4.0GiB|5.2%"
            local mem_part cpu_part
            mem_part="${stats_output%%|*}"
            cpu_part="${stats_output##*|}"
            # mem_part: "1.2GiB / 4.0GiB"
            mem_usage="${mem_part%% /*}"
            mem_limit="${mem_part##*/ }"
            # Calculate percentage
            mem_pct=$(python3 -c "
import sys
usage = sys.argv[1]
limit = sys.argv[2]

def parse_mem(s):
    s = s.strip()
    if s.endswith('GiB'):
        return float(s[:-3]) * 1024
    elif s.endswith('MiB'):
        return float(s[:-3])
    elif s.endswith('KiB'):
        return float(s[:-3]) / 1024
    elif s.endswith('B'):
        return float(s[:-1]) / (1024*1024)
    return 0

u = parse_mem(usage)
l = parse_mem(limit)
if l > 0:
    print(f'{u/l*100:.0f}%')
" "$mem_usage" "$mem_limit" 2>/dev/null) || mem_pct=""
            cpu_pct="$cpu_part"
        fi
    fi

    # Best-effort: Get session info (5s timeout) using _cai_detect_sessions
    local ssh_count="" pty_count=""
    if [[ "$status" == "running" ]]; then
        local session_result
        # Use _cai_detect_sessions as spec requires (returns 0=has sessions, 1=no sessions, 2=unknown)
        if _cai_detect_sessions "$container_name" "$selected_context"; then
            session_result=0
        else
            session_result=$?
        fi
        # Only get counts if detection succeeded (0 or 1 means ss is available)
        if [[ "$session_result" -eq 0 || "$session_result" -eq 1 ]]; then
            local session_output
            if session_output=$(_cai_timeout 5 env DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" exec "$container_name" sh -c '
                ssh_count=$(ss -t state established sport = :22 2>/dev/null | tail -n +2 | wc -l)
                pty_count=$(ls /dev/pts/ 2>/dev/null | grep -c "^[0-9]" || echo 0)
                echo "$ssh_count $pty_count"
            ' 2>/dev/null); then
                read -r ssh_count pty_count <<< "$session_output"
            fi
        fi
    fi

    # Output results
    if [[ "$json_flag" == "true" ]]; then
        # JSON output requires python3
        if ! command -v python3 >/dev/null 2>&1; then
            echo "[ERROR] --json requires python3 which is not available" >&2
            return 1
        fi
        python3 -c "
import json
import sys

data = {
    'container': sys.argv[1],
    'status': sys.argv[2],
    'image': sys.argv[3],
    'uptime': sys.argv[4] if sys.argv[4] else None,
    'sessions': {
        'ssh_connections': int(sys.argv[5]) if sys.argv[5] else None,
        'active_terminals': int(sys.argv[6]) if sys.argv[6] else None
    } if sys.argv[5] or sys.argv[6] else None,
    'resources': {
        'memory_usage': sys.argv[7] if sys.argv[7] else None,
        'memory_limit': sys.argv[8] if sys.argv[8] else None,
        'memory_percent': sys.argv[9] if sys.argv[9] else None,
        'cpu_percent': sys.argv[10] if sys.argv[10] else None
    } if sys.argv[7] or sys.argv[10] else None
}

# Remove None values for cleaner output
def clean_none(d):
    if isinstance(d, dict):
        return {k: clean_none(v) for k, v in d.items() if v is not None}
    return d

print(json.dumps(clean_none(data), indent=2))
" "$container_name" "$status" "$image" "$uptime" "$ssh_count" "$pty_count" "$mem_usage" "$mem_limit" "$mem_pct" "$cpu_pct"
    else
        # Human-readable output
        printf 'Container: %s\n' "$container_name"
        printf '  Status: %s\n' "$status"
        if [[ -n "$uptime" ]]; then
            printf '  Uptime: %s\n' "$uptime"
        fi
        printf '  Image: %s\n' "$image"

        if [[ -n "$ssh_count" || -n "$pty_count" ]]; then
            printf '\n  Sessions (best-effort):\n'
            if [[ -n "$ssh_count" ]]; then
                printf '    SSH connections: %s\n' "$ssh_count"
            fi
            if [[ -n "$pty_count" ]]; then
                printf '    Active terminals: %s\n' "$pty_count"
            fi
        fi

        if [[ -n "$mem_usage" || -n "$cpu_pct" ]]; then
            printf '\n  Resource Usage:\n'
            if [[ -n "$mem_usage" ]] && [[ -n "$mem_limit" ]]; then
                if [[ -n "$mem_pct" ]]; then
                    printf '    Memory: %s / %s (%s)\n' "$mem_usage" "$mem_limit" "$mem_pct"
                else
                    printf '    Memory: %s / %s\n' "$mem_usage" "$mem_limit"
                fi
            fi
            if [[ -n "$cpu_pct" ]]; then
                printf '    CPU: %s\n' "$cpu_pct"
            fi
        fi
    fi

    return 0
}

# GC subcommand - garbage collection for stale containers and images
_containai_gc_cmd() {
    local dry_run=false
    local force_flag=false
    local prune_images=false
    local age_str="30d"
    local arg

    # Pass 1: Check for help early
    for arg in "$@"; do
        case "$arg" in
            --help | -h)
                _containai_gc_help
                return 0
                ;;
        esac
    done

    # Pass 2: Parse arguments
    local expect_age_value=false
    for arg in "$@"; do
        if [[ "$expect_age_value" == "true" ]]; then
            if [[ -z "$arg" ]] || [[ "$arg" == -* ]]; then
                echo "[ERROR] --age requires a value (e.g., 30d, 7d, 24h)" >&2
                return 1
            fi
            age_str="$arg"
            expect_age_value=false
            continue
        fi

        case "$arg" in
            --dry-run)
                dry_run=true
                ;;
            --force)
                force_flag=true
                ;;
            --images)
                prune_images=true
                ;;
            --age)
                expect_age_value=true
                ;;
            --age=*)
                age_str="${arg#--age=}"
                if [[ -z "$age_str" ]]; then
                    echo "[ERROR] --age requires a value" >&2
                    return 1
                fi
                ;;
            --verbose)
                _cai_set_verbose
                ;;
            -*)
                echo "[ERROR] Unknown option: $arg" >&2
                echo "Use 'cai gc --help' for usage" >&2
                return 1
                ;;
            *)
                echo "[ERROR] Unexpected argument: $arg" >&2
                echo "Use 'cai gc --help' for usage" >&2
                return 1
                ;;
        esac
    done

    # Handle trailing --age without value
    if [[ "$expect_age_value" == "true" ]]; then
        echo "[ERROR] --age requires a value (e.g., 30d, 7d, 24h)" >&2
        return 1
    fi

    # Parse age to seconds
    local age_seconds
    if ! age_seconds=$(_cai_parse_age_to_seconds "$age_str"); then
        echo "[ERROR] Invalid age format: $age_str (expected Nd or Nh, e.g., 30d, 7d, 24h)" >&2
        return 1
    fi

    # Check docker availability
    if ! _containai_check_docker; then
        return 1
    fi

    # Get current timestamp
    local now_epoch
    now_epoch=$(date +%s)

    # Find GC candidate containers
    # Protection rules:
    # 1. Only containers with containai.managed=true label
    # 2. Never running containers
    # 3. Never containers with containai.keep=true label
    local -a gc_candidates=()
    local -a gc_ages=()
    local -a gc_statuses=()

    # Get all managed containers (exited or created status only)
    local container_list
    container_list=$(docker ps -a --filter "label=containai.managed=true" \
        --format '{{.Names}}|{{.Status}}' 2>/dev/null) || container_list=""

    if [[ -n "$container_list" ]]; then
        while IFS='|' read -r name status_line; do
            [[ -z "$name" ]] && continue

            # Parse status (e.g., "Exited (0) 3 days ago" or "Created")
            local container_status=""
            if [[ "$status_line" =~ ^Exited ]]; then
                container_status="exited"
            elif [[ "$status_line" =~ ^Created ]]; then
                container_status="created"
            else
                # Running or other status - skip
                continue
            fi

            # Check protection: containai.keep=true
            local keep_label
            keep_label=$(docker inspect --format '{{index .Config.Labels "containai.keep"}}' -- "$name" 2>/dev/null) || keep_label=""
            if [[ "$keep_label" == "true" ]]; then
                _cai_info "Skipping protected container: $name (containai.keep=true)"
                continue
            fi

            # Get timestamp based on status
            local timestamp=""
            if [[ "$container_status" == "exited" ]]; then
                # Use FinishedAt for stopped containers
                timestamp=$(docker inspect --format '{{.State.FinishedAt}}' -- "$name" 2>/dev/null) || timestamp=""
            else
                # Use Created for never-ran containers
                timestamp=$(docker inspect --format '{{.Created}}' -- "$name" 2>/dev/null) || timestamp=""
            fi

            # Skip if no valid timestamp
            if [[ -z "$timestamp" ]] || [[ "$timestamp" == "0001-01-01T00:00:00Z" ]]; then
                _cai_info "Skipping container with invalid timestamp: $name"
                continue
            fi

            # Parse timestamp to epoch
            local ts_epoch
            if ! ts_epoch=$(_cai_parse_timestamp_to_epoch "$timestamp"); then
                _cai_info "Skipping container (timestamp parse error): $name"
                continue
            fi

            # Calculate age
            local age_diff=$((now_epoch - ts_epoch))

            # Check if container is old enough
            if [[ $age_diff -ge $age_seconds ]]; then
                gc_candidates+=("$name")
                gc_ages+=("$age_diff")
                gc_statuses+=("$container_status")
            fi
        done <<< "$container_list"
    fi

    # Find GC candidate images (if --images flag)
    local -a image_candidates=()
    if [[ "$prune_images" == "true" ]]; then
        # Get all ContainAI images
        local image_list
        image_list=$(docker images --format '{{.Repository}}:{{.Tag}}|{{.ID}}' 2>/dev/null | \
            grep -E '^(containai:|ghcr\.io/containai/)') || image_list=""

        if [[ -n "$image_list" ]]; then
            # Get list of images in use by any container (running or stopped)
            local used_images
            used_images=$(docker ps -a --format '{{.Image}}' 2>/dev/null | sort -u) || used_images=""

            while IFS='|' read -r image_name image_id; do
                [[ -z "$image_name" ]] && continue
                [[ "$image_name" == *"<none>"* ]] && continue

                # Check if image is in use
                local in_use=false
                while IFS= read -r used_img; do
                    if [[ "$used_img" == "$image_name" ]] || [[ "$used_img" == "$image_id" ]]; then
                        in_use=true
                        break
                    fi
                done <<< "$used_images"

                if [[ "$in_use" == "false" ]]; then
                    image_candidates+=("$image_name")
                fi
            done <<< "$image_list"
        fi
    fi

    # Display results
    if [[ ${#gc_candidates[@]} -eq 0 ]] && [[ ${#image_candidates[@]} -eq 0 ]]; then
        echo "No stale resources found."
        return 0
    fi

    # Inline age formatting (avoids defining global function)
    _cai_gc_format_age() {
        local secs="$1"
        local days=$((secs / 86400))
        local hours=$(( (secs % 86400) / 3600 ))
        if [[ $days -gt 0 ]]; then
            printf '%dd %dh' "$days" "$hours"
        else
            printf '%dh' "$hours"
        fi
    }

    echo "Stale ContainAI resources (age >= $age_str):"
    echo ""

    if [[ ${#gc_candidates[@]} -gt 0 ]]; then
        echo "Containers:"
        local i
        for i in "${!gc_candidates[@]}"; do
            local age_formatted
            age_formatted=$(_cai_gc_format_age "${gc_ages[$i]}")
            printf "  %s (%s, age: %s)\n" "${gc_candidates[$i]}" "${gc_statuses[$i]}" "$age_formatted"
        done
        echo ""
    fi

    if [[ ${#image_candidates[@]} -gt 0 ]]; then
        echo "Unused images:"
        for img in "${image_candidates[@]}"; do
            printf "  %s\n" "$img"
        done
        echo ""
    fi

    # Dry run mode - just show what would be removed
    if [[ "$dry_run" == "true" ]]; then
        echo "[DRY-RUN] Would remove ${#gc_candidates[@]} container(s) and ${#image_candidates[@]} image(s)"
        return 0
    fi

    # Interactive confirmation (unless --force)
    # Use _cai_prompt_confirm for consistent behavior (CAI_YES support, /dev/tty fallback)
    if [[ "$force_flag" != "true" ]]; then
        local total=$((${#gc_candidates[@]} + ${#image_candidates[@]}))
        if ! _cai_prompt_confirm "Remove $total resource(s)?"; then
            echo "Cancelled."
            return 0
        fi
    fi

    # Remove containers
    # Re-check state before removal to prevent race condition where container
    # could have started between listing and deletion
    local removed_containers=0
    local failed_containers=0
    for name in "${gc_candidates[@]}"; do
        # Safety check: verify container is still not running before removal
        local current_state
        current_state=$(docker inspect --format '{{.State.Running}}' -- "$name" 2>/dev/null) || current_state=""
        if [[ "$current_state" == "true" ]]; then
            _cai_warn "Skipping container (now running): $name"
            ((failed_containers++))
            continue
        fi

        # Use docker rm without -f to avoid forcing removal of running containers
        if docker rm -- "$name" >/dev/null 2>&1; then
            _cai_info "Removed container: $name"
            ((removed_containers++))
            # Clean up SSH config
            _cai_remove_ssh_host_config "$name"
        else
            _cai_warn "Failed to remove container: $name"
            ((failed_containers++))
        fi
    done

    # Remove images
    local removed_images=0
    local failed_images=0
    for img in "${image_candidates[@]}"; do
        if docker rmi -- "$img" >/dev/null 2>&1; then
            _cai_info "Removed image: $img"
            ((removed_images++))
        else
            _cai_warn "Failed to remove image: $img (may be in use)"
            ((failed_images++))
        fi
    done

    # Summary
    echo ""
    if [[ $removed_containers -gt 0 ]] || [[ $removed_images -gt 0 ]]; then
        echo "Removed: $removed_containers container(s), $removed_images image(s)"
    fi
    if [[ $failed_containers -gt 0 ]] || [[ $failed_images -gt 0 ]]; then
        echo "Failed: $failed_containers container(s), $failed_images image(s)"
        return 1
    fi

    return 0
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
    # Exempt command: auto-enable verbose (diagnostic tool - output is the point)
    _cai_set_verbose

    local json_output="false"
    local reset_lima="false"
    local build_templates="false"
    local workspace="$PWD"

    # Check for 'fix' subcommand first (before option parsing)
    if [[ "${1:-}" == "fix" ]]; then
        shift
        _cai_doctor_fix_dispatch "$@"
        return $?
    fi

    # Parse arguments for base doctor command
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json)
                json_output="true"
                shift
                ;;
            --build-templates)
                build_templates="true"
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

    # Run doctor checks (default mode is diagnostic, not fix)
    if [[ "$json_output" == "true" ]]; then
        _cai_doctor_json "$build_templates"
    else
        _cai_doctor "$build_templates"
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
            --verbose)
                _cai_set_verbose
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
# Template subcommand handlers
# ==============================================================================

# Template subcommand handler - manage container templates
_containai_template_cmd() {
    local subcommand="${1:-}"

    # Handle empty or help first
    if [[ -z "$subcommand" ]]; then
        _containai_template_help
        return 0
    fi

    case "$subcommand" in
        upgrade)
            shift
            _containai_template_upgrade_cmd "$@"
            ;;
        help | -h | --help)
            _containai_template_help
            return 0
            ;;
        *)
            echo "[ERROR] Unknown template subcommand: $subcommand" >&2
            echo "Use 'cai template --help' for usage" >&2
            return 1
            ;;
    esac
}

# Template upgrade subcommand - upgrade templates to use ARG BASE_IMAGE pattern
_containai_template_upgrade_cmd() {
    local dry_run="false"
    local template_name=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                dry_run="true"
                shift
                ;;
            -h | --help)
                _containai_template_help
                return 0
                ;;
            -*)
                echo "[ERROR] Unknown option: $1" >&2
                return 1
                ;;
            *)
                if [[ -n "$template_name" ]]; then
                    echo "[ERROR] Only one template name allowed" >&2
                    return 1
                fi
                template_name="$1"
                shift
                ;;
        esac
    done

    # Call the upgrade function
    _cai_template_upgrade "$dry_run" "$template_name"
}

# ==============================================================================
# Config subcommand handlers
# ==============================================================================

# Config subcommand handler - manage settings with workspace-aware scope
_containai_config_cmd() {
    local config_subcommand="${1:-}"
    local workspace=""
    local global_scope="false"
    local explicit_workspace=""

    # Handle empty or help first
    if [[ -z "$config_subcommand" ]]; then
        _containai_config_help
        return 0
    fi

    case "$config_subcommand" in
        list)
            shift
            _containai_config_list_cmd "$@"
            ;;
        get)
            shift
            _containai_config_get_cmd "$@"
            ;;
        set)
            shift
            _containai_config_set_cmd "$@"
            ;;
        unset)
            shift
            _containai_config_unset_cmd "$@"
            ;;
        help | -h | --help)
            _containai_config_help
            return 0
            ;;
        *)
            echo "[ERROR] Unknown config subcommand: $config_subcommand" >&2
            echo "Use 'cai config --help' for usage" >&2
            return 1
            ;;
    esac
}

# Config list subcommand - show all settings with sources
_containai_config_list_cmd() {
    local workspace="$PWD"

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
                workspace="${workspace/#\~/$HOME}"
                shift
                ;;
            -w*)
                workspace="${1#-w}"
                workspace="${workspace/#\~/$HOME}"
                shift
                ;;
            --verbose)
                _cai_set_verbose
                shift
                ;;
            --help | -h)
                _containai_config_help
                return 0
                ;;
            *)
                echo "[ERROR] Unknown option: $1" >&2
                return 1
                ;;
        esac
    done

    # Normalize workspace path
    local normalized_workspace
    if ! normalized_workspace=$(_cai_normalize_path "$workspace"); then
        echo "[ERROR] Invalid workspace path: $workspace" >&2
        return 1
    fi

    # Print header
    printf '%-24s %-30s %s\n' "KEY" "VALUE" "SOURCE"
    printf '%s\n' "$(printf '%0.s─' {1..72})"

    # List all config with sources
    local line key value source
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            # Split by tab
            key="${line%%	*}"
            local rest="${line#*	}"
            value="${rest%%	*}"
            source="${rest#*	}"
            printf '%-24s %-30s %s\n' "$key" "$value" "$source"
        fi
    done < <(_containai_list_all_config "$normalized_workspace")
}

# Config get subcommand - get a specific key with source
_containai_config_get_cmd() {
    local workspace="$PWD"
    local key=""

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
                workspace="${workspace/#\~/$HOME}"
                shift
                ;;
            --verbose)
                _cai_set_verbose
                shift
                ;;
            --help | -h)
                _containai_config_help
                return 0
                ;;
            -*)
                echo "[ERROR] Unknown option: $1" >&2
                return 1
                ;;
            *)
                if [[ -z "$key" ]]; then
                    key="$1"
                else
                    echo "[ERROR] Too many arguments" >&2
                    return 1
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$key" ]]; then
        echo "[ERROR] Key required. Usage: cai config get <key>" >&2
        return 1
    fi

    # Normalize workspace path
    local normalized_workspace
    if ! normalized_workspace=$(_cai_normalize_path "$workspace"); then
        echo "[ERROR] Invalid workspace path: $workspace" >&2
        return 1
    fi

    # Get the value with source
    local result value source
    result=$(_containai_resolve_with_source "$key" "$normalized_workspace")
    value="${result%%	*}"
    source="${result#*	}"

    if [[ -z "$value" ]]; then
        _cai_info "Key '$key' is not set"
        return 0
    fi

    printf '%s\t%s\n' "$value" "$source"
}

# Config set subcommand - set a key value
_containai_config_set_cmd() {
    local workspace="$PWD"
    local global_scope="false"
    local explicit_workspace=""
    local key=""
    local value=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --global | -g)
                global_scope="true"
                shift
                ;;
            --workspace | -w)
                if [[ -z "${2-}" ]]; then
                    echo "[ERROR] --workspace requires a value" >&2
                    return 1
                fi
                explicit_workspace="$2"
                explicit_workspace="${explicit_workspace/#\~/$HOME}"
                shift 2
                ;;
            --workspace=*)
                explicit_workspace="${1#--workspace=}"
                explicit_workspace="${explicit_workspace/#\~/$HOME}"
                shift
                ;;
            --verbose)
                _cai_set_verbose
                shift
                ;;
            --help | -h)
                _containai_config_help
                return 0
                ;;
            -*)
                echo "[ERROR] Unknown option: $1" >&2
                return 1
                ;;
            *)
                if [[ -z "$key" ]]; then
                    key="$1"
                elif [[ -z "$value" ]]; then
                    value="$1"
                else
                    echo "[ERROR] Too many arguments" >&2
                    return 1
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$key" ]] || [[ -z "$value" ]]; then
        echo "[ERROR] Key and value required. Usage: cai config set <key> <value>" >&2
        return 1
    fi

    # Normalize "agent" alias to "agent.default" (runtime only reads agent.default)
    if [[ "$key" == "agent" ]]; then
        key="agent.default"
    fi

    # Determine target workspace
    local target_workspace
    if [[ -n "$explicit_workspace" ]]; then
        if ! target_workspace=$(_cai_normalize_path "$explicit_workspace"); then
            echo "[ERROR] Invalid workspace path: $explicit_workspace" >&2
            return 1
        fi
    else
        if ! target_workspace=$(_cai_normalize_path "$workspace"); then
            echo "[ERROR] Invalid workspace path: $workspace" >&2
            return 1
        fi
    fi

    # Check if this is a workspace-scoped key
    local is_workspace_key=""
    local k
    for k in $_CAI_WORKSPACE_KEYS; do
        if [[ "$key" == "$k" ]]; then
            is_workspace_key="true"
            break
        fi
    done

    # Reject -g for workspace-scoped keys (would write a value that's never read)
    if [[ "$global_scope" == "true" ]] && [[ "$is_workspace_key" == "true" ]]; then
        echo "[ERROR] Cannot use -g/--global with workspace-scoped key '$key'" >&2
        echo "        Use 'cai config set --workspace <path> $key <value>' instead" >&2
        return 1
    fi

    # Determine scope
    if [[ "$global_scope" == "true" ]]; then
        # Force global scope (only for non-workspace keys)
        if ! _containai_set_global_key "$key" "$value"; then
            return 1
        fi
        echo "[OK] Set $key = $value (user-global)"
    elif [[ "$is_workspace_key" == "true" ]]; then
        # Workspace-scoped key - use longest-prefix matching when --workspace not provided
        local final_workspace="$target_workspace"
        if [[ -z "$explicit_workspace" ]]; then
            # Find best matching workspace from existing config (nested detection)
            # Load user config JSON and pipe to _containai_find_matching_workspace
            local user_config_file matched_ws config_json
            user_config_file=$(_containai_user_config_path)
            if [[ -f "$user_config_file" ]] && command -v python3 >/dev/null 2>&1; then
                local script_dir
                if script_dir="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; then
                    if config_json=$(python3 "$script_dir/lib/../parse-toml.py" --file "$user_config_file" --json 2>/dev/null); then
                        matched_ws=$(printf '%s' "$config_json" | _containai_find_matching_workspace "$target_workspace" 2>/dev/null) || true
                        if [[ -n "$matched_ws" ]]; then
                            final_workspace="$matched_ws"
                        fi
                    fi
                fi
            fi
        fi
        if ! _containai_write_workspace_state "$final_workspace" "$key" "$value"; then
            return 1
        fi
        echo "[OK] Set $key = $value (workspace:$final_workspace)"
    else
        # Global key
        if ! _containai_set_global_key "$key" "$value"; then
            return 1
        fi
        echo "[OK] Set $key = $value (user-global)"
    fi

    return 0
}

# Config unset subcommand - remove a key
_containai_config_unset_cmd() {
    local workspace="$PWD"
    local global_scope="false"
    local explicit_workspace=""
    local key=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --global | -g)
                global_scope="true"
                shift
                ;;
            --workspace | -w)
                if [[ -z "${2-}" ]]; then
                    echo "[ERROR] --workspace requires a value" >&2
                    return 1
                fi
                explicit_workspace="$2"
                explicit_workspace="${explicit_workspace/#\~/$HOME}"
                shift 2
                ;;
            --workspace=*)
                explicit_workspace="${1#--workspace=}"
                explicit_workspace="${explicit_workspace/#\~/$HOME}"
                shift
                ;;
            --verbose)
                _cai_set_verbose
                shift
                ;;
            --help | -h)
                _containai_config_help
                return 0
                ;;
            -*)
                echo "[ERROR] Unknown option: $1" >&2
                return 1
                ;;
            *)
                if [[ -z "$key" ]]; then
                    key="$1"
                else
                    echo "[ERROR] Too many arguments" >&2
                    return 1
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$key" ]]; then
        echo "[ERROR] Key required. Usage: cai config unset <key>" >&2
        return 1
    fi

    # Normalize "agent" alias to "agent.default" (runtime only reads agent.default)
    if [[ "$key" == "agent" ]]; then
        key="agent.default"
    fi

    # Determine target workspace
    local target_workspace
    if [[ -n "$explicit_workspace" ]]; then
        if ! target_workspace=$(_cai_normalize_path "$explicit_workspace"); then
            echo "[ERROR] Invalid workspace path: $explicit_workspace" >&2
            return 1
        fi
    else
        if ! target_workspace=$(_cai_normalize_path "$workspace"); then
            echo "[ERROR] Invalid workspace path: $workspace" >&2
            return 1
        fi
    fi

    # Check if this is a workspace-scoped key
    local is_workspace_key=""
    local k
    for k in $_CAI_WORKSPACE_KEYS; do
        if [[ "$key" == "$k" ]]; then
            is_workspace_key="true"
            break
        fi
    done

    # Determine scope
    if [[ "$global_scope" == "true" ]]; then
        # Force global scope
        if ! _containai_unset_global_key "$key"; then
            return 1
        fi
        echo "[OK] Unset $key (user-global)"
    elif [[ "$is_workspace_key" == "true" ]]; then
        # Workspace-scoped key - use longest-prefix matching when --workspace not provided
        local final_workspace="$target_workspace"
        if [[ -z "$explicit_workspace" ]]; then
            # Find best matching workspace from existing config (nested detection)
            # Load user config JSON and pipe to _containai_find_matching_workspace
            local user_config_file matched_ws config_json
            user_config_file=$(_containai_user_config_path)
            if [[ -f "$user_config_file" ]] && command -v python3 >/dev/null 2>&1; then
                local script_dir
                if script_dir="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; then
                    if config_json=$(python3 "$script_dir/lib/../parse-toml.py" --file "$user_config_file" --json 2>/dev/null); then
                        matched_ws=$(printf '%s' "$config_json" | _containai_find_matching_workspace "$target_workspace" 2>/dev/null) || true
                        if [[ -n "$matched_ws" ]]; then
                            final_workspace="$matched_ws"
                        fi
                    fi
                fi
            fi
        fi
        if ! _containai_unset_workspace_key "$final_workspace" "$key"; then
            return 1
        fi
        echo "[OK] Unset $key (workspace:$final_workspace)"
    else
        # Global key
        if ! _containai_unset_global_key "$key"; then
            return 1
        fi
        echo "[OK] Unset $key (user-global)"
    fi

    return 0
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
                _cai_set_quiet
                shift
                ;;
            --verbose)
                _cai_set_verbose
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
                _cai_set_quiet
                shift
                ;;
            --verbose)
                _cai_set_verbose
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

    # Auto-repair context if endpoint is wrong (e.g., after Docker Desktop updates)
    # Silent repair - cai docker is a pass-through and shouldn't be verbose
    _cai_auto_repair_containai_context "false" || true

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

# ==============================================================================
# ACP Proxy Entry Point
# ==============================================================================

# ACP subcommand handler - dispatches to ACP proxy subcommands
# Arguments: subcommand and args (e.g., "proxy claude")
# Returns: exit code from proxy binary
_containai_acp_cmd() {
    local subcmd="${1:-}"

    if [[ -z "$subcmd" ]]; then
        printf '%s\n' "Usage: cai acp proxy <agent>" >&2
        printf '%s\n' "       cai acp proxy claude" >&2
        return 1
    fi

    case "$subcmd" in
        proxy)
            shift
            _containai_acp_proxy "$@"
            ;;
        *)
            printf '%s\n' "Unknown acp subcommand: $subcmd" >&2
            printf '%s\n' "Usage: cai acp proxy <agent>" >&2
            return 1
            ;;
    esac
}

# ACP proxy wrapper - launches native binary for ACP protocol handling
# Arguments: $@ = arguments passed to acp-proxy proxy command
# Environment:
#   CAI_ACP_TEST_MODE=1      Allow any agent name (for testing)
#   CAI_ACP_DIRECT_SPAWN=1   Bypass containers, spawn agent directly (for testing)
# Returns: exit code from proxy binary
_containai_acp_proxy() {
    # Binary location: src/bin/acp-proxy (avoids conflict with src/acp-proxy/ source dir)
    local proxy_bin="${_CAI_SCRIPT_DIR}/bin/acp-proxy"

    # Must be a regular file and executable
    if [[ ! -f "$proxy_bin" || ! -x "$proxy_bin" ]]; then
        printf '%s\n' "ACP proxy binary not found at $proxy_bin." >&2
        printf '%s\n' "Build and install with: ${_CAI_SCRIPT_DIR}/acp-proxy/build.sh --install" >&2
        return 1
    fi

    # Pass all arguments directly to the binary's proxy subcommand
    # The binary handles agent validation and --help
    exec "$proxy_bin" proxy "$@"
}

# Shell subcommand handler - connects to container via SSH
# Uses SSH instead of docker exec for real terminal experience
_containai_shell_cmd() {
    local cli_volume=""
    local workspace=""
    local explicit_config=""
    local container_name=""
    local image_tag=""
    local cli_template=""
    local cli_memory=""
    local cli_cpus=""
    local fresh_flag=false
    local reset_flag=false
    local force_flag=false
    local quiet_flag=false
    local verbose_flag=false
    local debug_flag=false
    local dry_run_flag=false
    # Reset channel override (global for registry.sh)
    _CAI_CHANNEL_OVERRIDE=""

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
            --reset)
                reset_flag=true
                shift
                ;;
            --force)
                force_flag=true
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
            --channel)
                if [[ -z "${2-}" ]]; then
                    echo "[ERROR] --channel requires a value" >&2
                    return 1
                fi
                _CAI_CHANNEL_OVERRIDE="$2"
                shift 2
                ;;
            --channel=*)
                _CAI_CHANNEL_OVERRIDE="${1#--channel=}"
                if [[ -z "$_CAI_CHANNEL_OVERRIDE" ]]; then
                    echo "[ERROR] --channel requires a value" >&2
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
                _cai_error "$1 is no longer supported in cai shell"
                _cai_warn "cai shell uses SSH - host mounts are not available"
                return 1
                ;;
            --env | -e | --env=* | -e*)
                _cai_error "--env is not supported in cai shell (SSH mode)"
                _cai_warn "Set environment variables in the container's shell directly"
                return 1
                ;;
            --volume | -v | --volume=* | -v*)
                _cai_error "--volume is not supported in cai shell (SSH mode)"
                _cai_warn "Volumes must be configured at container creation time"
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

    # Set CLI resource overrides (global vars read by _containai_start_container)
    _CAI_CLI_MEMORY="$cli_memory"
    _CAI_CLI_CPUS="$cli_cpus"

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

    # Check mutual exclusivity of --reset and --fresh
    if [[ "$reset_flag" == "true" && "$fresh_flag" == "true" ]]; then
        _cai_error "--reset and --fresh are mutually exclusive"
        _cai_warn "--fresh recreates container with same volume; --reset generates new volume"
        return 1
    fi

    # Check mutual exclusivity of --reset with --container and --data-volume
    if [[ "$reset_flag" == "true" ]]; then
        if [[ -n "$container_name" ]]; then
            echo "[ERROR] --reset and --container are mutually exclusive" >&2
            return 1
        fi
        if [[ -n "$cli_volume" ]]; then
            _cai_error "--reset and --data-volume are mutually exclusive"
            _cai_warn "--reset generates a new unique volume name; use --data-volume alone to specify a volume"
            return 1
        fi
    fi

    # Variables to resolve
    local resolved_workspace=""
    local resolved_volume=""
    local resolved_container_name=""
    local selected_context=""

    # === EARLY BRANCH: --container mode ===
    # When --container is provided, use container if exists or create if missing
    # This is the unified "use-or-create" semantic for shell/run/exec commands
    if [[ -n "$container_name" ]]; then
        # Try to find existing container
        # Use _cai_find_container_by_name for consistent context search (config/secure first)
        # Pass PWD as workspace hint for config-based context discovery
        local find_rc container_exists="false"
        if selected_context=$(_cai_find_container_by_name "$container_name" "$explicit_config" "$PWD"); then
            container_exists="true"
        else
            find_rc=$?
            if [[ $find_rc -eq 2 ]]; then
                return 1  # Error already printed (ambiguity)
            elif [[ $find_rc -eq 3 ]]; then
                return 1  # Error already printed (config parse)
            fi
            # find_rc=1 means container not found - we'll create it
        fi

        if [[ "$container_exists" == "true" ]]; then
            # Container exists - derive workspace/volume from labels
            # Build docker command prefix (always use --context)
            local -a docker_cmd=(docker --context "$selected_context")

            # Verify container is managed by ContainAI (label or image fallback for legacy containers)
            # Use {{with}} template to output empty string for missing labels (avoids <no value>)
            # Clear DOCKER_CONTEXT/DOCKER_HOST to ensure --context takes effect
            local is_managed container_image
            is_managed=$(DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" inspect --type container --format '{{with index .Config.Labels "containai.managed"}}{{.}}{{end}}' -- "$container_name" 2>/dev/null) || is_managed=""
            if [[ "$is_managed" != "true" ]]; then
                # Fallback: check if image is from our repo (for legacy containers without label)
                container_image=$(DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" inspect --type container --format '{{.Config.Image}}' -- "$container_name" 2>/dev/null) || container_image=""
                if [[ "$container_image" != "${_CONTAINAI_DEFAULT_REPO}:"* ]]; then
                    echo "[ERROR] Container $container_name exists but is not managed by ContainAI" >&2
                    echo "[HINT] Remove the conflicting container or use a different name" >&2
                    return 1
                fi
            fi

            # Derive workspace from container labels
            resolved_workspace=$(DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" inspect --type container --format '{{with index .Config.Labels "containai.workspace"}}{{.}}{{end}}' -- "$container_name" 2>/dev/null) || resolved_workspace=""
            if [[ -z "$resolved_workspace" ]]; then
                echo "[ERROR] Container $container_name is missing workspace label" >&2
                return 1
            fi

            # Derive data volume from container labels
            resolved_volume=$(DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" inspect --type container --format '{{with index .Config.Labels "containai.data-volume"}}{{.}}{{end}}' -- "$container_name" 2>/dev/null) || resolved_volume=""
            if [[ -z "$resolved_volume" ]]; then
                echo "[ERROR] Container $container_name is missing data-volume label" >&2
                return 1
            fi

            resolved_container_name="$container_name"
            # Note: workspace state will be saved after successful validation later
        else
            # Container doesn't exist - will create it with the specified name
            # Use workspace from PWD (or cli_volume if provided, but that's blocked by mutual exclusivity)
            local workspace_input
            workspace_input="${workspace:-$PWD}"
            resolved_workspace=$(_cai_normalize_path "$workspace_input")
            if [[ ! -d "$resolved_workspace" ]]; then
                echo "[ERROR] Workspace path does not exist: $workspace_input" >&2
                return 1
            fi

            # Resolve volume for the new container
            if ! resolved_volume=$(_containai_resolve_volume "$cli_volume" "$resolved_workspace" "$explicit_config"); then
                echo "[ERROR] Failed to resolve data volume" >&2
                return 1
            fi

            # Select context for new container
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
                config_file=$(_containai_find_config "$resolved_workspace")
                if [[ -n "$config_file" ]]; then
                    _containai_parse_config "$config_file" "$resolved_workspace" 2>/dev/null || true
                fi
            fi
            local config_context_override="${_CAI_SECURE_ENGINE_CONTEXT:-}"

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

            resolved_container_name="$container_name"
            # Note: workspace state will be saved after successful create later
        fi
    else
        # === STANDARD MODE: Resolve from workspace ===
        # Resolve workspace using platform-aware normalization
        local workspace_input strict_mode
        workspace_input="${workspace:-$PWD}"

        # First normalize to check if path exists
        local normalized_input
        normalized_input=$(_cai_normalize_path "$workspace_input")
        if [[ ! -d "$normalized_input" ]]; then
            echo "[ERROR] Workspace path does not exist: $workspace_input" >&2
            return 1
        fi

        # Determine if explicit --workspace was provided (strict mode for nesting check)
        if [[ -n "$workspace" ]]; then
            strict_mode="strict"
        else
            strict_mode=""
        fi

        # === CONFIG PARSING (early - need context for docker label lookup in nesting check) ===
        local config_file=""
        if [[ -n "$explicit_config" ]]; then
            if [[ ! -f "$explicit_config" ]]; then
                echo "[ERROR] Config file not found: $explicit_config" >&2
                return 1
            fi
            config_file="$explicit_config"
            if ! _containai_parse_config "$config_file" "$normalized_input" "strict"; then
                echo "[ERROR] Failed to parse config: $explicit_config" >&2
                return 1
            fi
        else
            # Discovered config: suppress errors gracefully
            config_file=$(_containai_find_config "$normalized_input")
            if [[ -n "$config_file" ]]; then
                _containai_parse_config "$config_file" "$normalized_input" 2>/dev/null || true
            fi
        fi
        local config_context_override="${_CAI_SECURE_ENGINE_CONTEXT:-}"

        # Auto-select Docker context (needed for nesting check docker label lookup)
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

        # === NESTED WORKSPACE DETECTION ===
        # Check if this path is nested under an existing workspace (config or container label)
        # If explicit --workspace provided with nested path, error
        # If implicit (cwd), use parent workspace with INFO message
        if ! resolved_workspace=$(_containai_resolve_workspace_with_nesting "$normalized_input" "$selected_context" "$strict_mode"); then
            # Error already printed by _containai_resolve_workspace_with_nesting
            return 1
        fi

        # Handle --reset flag: generate new volume name (but don't persist yet)
        # State persistence is deferred until after validation succeeds
        # This ensures we don't mutate state if validation fails
        local reset_pending=false
        if [[ "$reset_flag" == "true" ]]; then
            _cai_info "Resetting workspace state..."

            # Generate NEW unique volume name (never falls back to default)
            if ! resolved_volume=$(_containai_generate_volume_name "$resolved_workspace"); then
                echo "[ERROR] Failed to generate new volume name" >&2
                return 1
            fi

            # Mark that we need to persist state after validation
            # Skip if dry-run (dry-run should never mutate state)
            if [[ "$dry_run_flag" != "true" ]]; then
                reset_pending=true
            fi
        else
            # Resolve volume normally (needed for container creation if --fresh)
            if ! resolved_volume=$(_containai_resolve_volume "$cli_volume" "$resolved_workspace" "$explicit_config"); then
                echo "[ERROR] Failed to resolve data volume" >&2
                return 1
            fi
        fi
        # Note: config_file and selected_context were already set above during nested workspace detection

        # Now that config validation and context selection succeeded, persist --reset state
        # This is deferred from above to avoid mutating state if validation fails
        if [[ "$reset_pending" == "true" ]]; then
            # Write new volume name to workspace state
            if ! _containai_write_workspace_state "$resolved_workspace" "data_volume" "$resolved_volume"; then
                echo "[ERROR] Failed to write workspace state" >&2
                return 1
            fi

            # Update created_at timestamp
            local reset_timestamp
            reset_timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
            _containai_write_workspace_state "$resolved_workspace" "created_at" "$reset_timestamp" 2>/dev/null || true

            # Clear container_name from workspace state (will be regenerated on create)
            _containai_write_workspace_state "$resolved_workspace" "container_name" "" 2>/dev/null || true
        fi

        # Build docker command prefix (always use --context)
        local -a docker_cmd=(docker --context "$selected_context")

        # Resolve container name using shared lookup helper
        # Priority: existing container lookup > new name for creation
        # Exit codes from helpers: 0=found, 1=not found, 2=multiple matches (abort)
        local find_rc
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

    # Build docker command prefix (always use --context)
    local -a docker_cmd=(docker --context "$selected_context")

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
        if [[ -n "$cli_template" ]]; then
            dry_run_args+=(--template "$cli_template")
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
        if [[ "$verbose_flag" == "true" ]]; then
            dry_run_args+=(--verbose)
        fi
        # Pass context to ensure dry-run reports correct context
        if [[ -n "$selected_context" ]]; then
            dry_run_args+=(--docker-context "$selected_context")
        fi
        _containai_start_container "${dry_run_args[@]}"
        return $?
    fi

    # Handle --fresh or --reset flag: remove and recreate container
    # Note: --reset has already regenerated workspace state values above
    if [[ "$fresh_flag" == "true" || "$reset_flag" == "true" ]]; then
        # Log at start of block (regardless of whether container exists)
        # --reset already logged "Resetting workspace state..." above
        if [[ "$fresh_flag" == "true" ]]; then
            _cai_info "Recreating container..."
        fi

        # Signal recreation in progress - other SSH sessions will wait gracefully
        _cai_set_recreating "$resolved_container_name"

        # Check if container exists
        if DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" inspect --type container -- "$resolved_container_name" >/dev/null 2>&1; then
            # Verify ownership before removing
            local fresh_label_val fresh_image_fallback
            fresh_label_val=$(DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" inspect --type container --format '{{index .Config.Labels "containai.managed"}}' -- "$resolved_container_name" 2>/dev/null) || fresh_label_val=""
            if [[ "$fresh_label_val" != "true" ]]; then
                fresh_image_fallback=$(DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" inspect --type container --format '{{.Config.Image}}' -- "$resolved_container_name" 2>/dev/null) || fresh_image_fallback=""
                if [[ "$fresh_image_fallback" != "${_CONTAINAI_DEFAULT_REPO}:"* ]]; then
                    local flag_name="--fresh"
                    [[ "$reset_flag" == "true" ]] && flag_name="--reset"
                    echo "[ERROR] Cannot use $flag_name - container '$resolved_container_name' was not created by ContainAI" >&2
                    echo "Remove the conflicting container manually if needed: docker rm -f '$resolved_container_name'" >&2
                    # Clear recreation flag on early failure
                    _cai_clear_recreating "$resolved_container_name"
                    return 1
                fi
            fi

            # Get SSH port before removal for cleanup
            local fresh_ssh_port
            fresh_ssh_port=$(_cai_get_container_ssh_port "$resolved_container_name" "$selected_context") || fresh_ssh_port=""

            # Stop and remove container
            local fresh_stop_output fresh_rm_output
            fresh_stop_output=$(DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" stop -- "$resolved_container_name" 2>&1) || {
                if ! printf '%s' "$fresh_stop_output" | grep -qiE "is not running"; then
                    echo "$fresh_stop_output" >&2
                fi
            }
            fresh_rm_output=$(DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" rm -- "$resolved_container_name" 2>&1) || {
                if ! printf '%s' "$fresh_rm_output" | grep -qiE "no such container|not found"; then
                    echo "$fresh_rm_output" >&2
                    # Clear recreation flag on failure
                    _cai_clear_recreating "$resolved_container_name"
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
        local -a create_args=()
        create_args+=(--data-volume "$resolved_volume")
        create_args+=(--workspace "$resolved_workspace")
        create_args+=(--detached)
        # Always pass resolved name to ensure single-sourced naming
        create_args+=(--name "$resolved_container_name")
        if [[ -n "$image_tag" ]]; then
            create_args+=(--image-tag "$image_tag")
        fi
        if [[ -n "$cli_template" ]]; then
            create_args+=(--template "$cli_template")
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
        if [[ "$verbose_flag" == "true" ]]; then
            create_args+=(--verbose)
        fi
        # Pass context to ensure container is created in the selected context
        if [[ -n "$selected_context" ]]; then
            create_args+=(--docker-context "$selected_context")
        fi

        if ! _containai_start_container "${create_args[@]}"; then
            echo "[ERROR] Failed to create container" >&2
            # Clear recreation flag on failure to avoid stale flags
            _cai_clear_recreating "$resolved_container_name"
            return 1
        fi

        # Save container name and volume to workspace state after --fresh/--reset recreation
        # For explicit recreation, always persist the volume used
        _containai_write_workspace_state "$resolved_workspace" "container_name" "$resolved_container_name" 2>/dev/null || true
        # Persist volume: CLI override always, --reset always (explicit new volume), or non-env first use
        if [[ -n "$cli_volume" ]] || [[ "$reset_flag" == "true" ]]; then
            _containai_write_workspace_state "$resolved_workspace" "data_volume" "$resolved_volume" 2>/dev/null || true
        elif [[ -z "${CONTAINAI_DATA_VOLUME:-}" ]]; then
            # --fresh without env override - persist to maintain state
            _containai_write_workspace_state "$resolved_workspace" "data_volume" "$resolved_volume" 2>/dev/null || true
        fi
    fi

    # Check if container exists; if not, create it first
    if ! DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" inspect --type container -- "$resolved_container_name" >/dev/null 2>&1; then
        _cai_info "Container not found, creating..."

        local -a create_args=()
        create_args+=(--data-volume "$resolved_volume")
        create_args+=(--workspace "$resolved_workspace")
        create_args+=(--detached)
        # Always pass resolved name to ensure single-sourced naming
        create_args+=(--name "$resolved_container_name")
        if [[ -n "$image_tag" ]]; then
            create_args+=(--image-tag "$image_tag")
        fi
        if [[ -n "$cli_template" ]]; then
            create_args+=(--template "$cli_template")
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
        if [[ "$verbose_flag" == "true" ]]; then
            create_args+=(--verbose)
        fi
        # Pass context to ensure container is created in the selected context
        if [[ -n "$selected_context" ]]; then
            create_args+=(--docker-context "$selected_context")
        fi

        if ! _containai_start_container "${create_args[@]}"; then
            echo "[ERROR] Failed to create container" >&2
            return 1
        fi

        # Save container name and volume to workspace state on successful creation
        _containai_write_workspace_state "$resolved_workspace" "container_name" "$resolved_container_name" 2>/dev/null || true
        # Save volume: CLI override always, or first-use (no existing state)
        # Do NOT persist env-derived volumes to avoid "sticky" behavior
        if [[ -n "$cli_volume" ]]; then
            _containai_write_workspace_state "$resolved_workspace" "data_volume" "$resolved_volume" 2>/dev/null || true
        else
            local existing_ws_vol
            existing_ws_vol=$(_containai_read_workspace_key "$resolved_workspace" "data_volume" 2>/dev/null) || existing_ws_vol=""
            if [[ -z "$existing_ws_vol" ]] && [[ -z "${CONTAINAI_DATA_VOLUME:-}" ]]; then
                # First use and NOT from env var - persist to establish state
                _containai_write_workspace_state "$resolved_workspace" "data_volume" "$resolved_volume" 2>/dev/null || true
            fi
        fi
    else
        # Container exists - validate ownership and workspace match before connecting
        # Check ownership (label or image fallback)
        local shell_label_val shell_image_val
        shell_label_val=$(DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" inspect --type container --format '{{index .Config.Labels "containai.managed"}}' -- "$resolved_container_name" 2>/dev/null) || shell_label_val=""
        if [[ "$shell_label_val" != "true" ]]; then
            shell_image_val=$(DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" inspect --type container --format '{{.Config.Image}}' -- "$resolved_container_name" 2>/dev/null) || shell_image_val=""
            if [[ "$shell_image_val" != "${_CONTAINAI_DEFAULT_REPO}:"* ]]; then
                echo "[ERROR] Container '$resolved_container_name' was not created by ContainAI" >&2
                return 15
            fi
        fi

        # Template mismatch check for existing containers (when --template specified)
        if [[ -n "$cli_template" ]]; then
            # Validate template name
            if ! _cai_validate_template_name "$cli_template"; then
                _cai_error "Invalid template name: $cli_template"
                _cai_warn "Template names must be lowercase alphanumeric with dashes/underscores/dots"
                return 1
            fi
            # Get container's template label
            local container_template
            container_template=$(DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" inspect --type container --format '{{with index .Config.Labels "ai.containai.template"}}{{.}}{{end}}' -- "$resolved_container_name" 2>/dev/null) || container_template=""
            if [[ -z "$container_template" ]]; then
                # Missing label = pre-existing container; allow only if --template default
                if [[ "$cli_template" != "default" ]]; then
                    _cai_error "Container was created before templates. Use --fresh to rebuild with template."
                    _cai_warn "Container: $resolved_container_name"
                    _cai_warn "Requested template: $cli_template"
                    return 1
                fi
            elif [[ "$container_template" != "$cli_template" ]]; then
                # Label mismatch
                _cai_error "Container exists with template '$container_template'. Use --fresh to rebuild."
                _cai_warn "Container: $resolved_container_name"
                _cai_warn "Requested template: $cli_template"
                _cai_warn "Existing template: $container_template"
                return 1
            fi
        fi

        # Check if --data-volume was provided with a different volume than the container's current volume
        # This error helps users understand why the command fails (spec: fn-36-rb7.12)
        if [[ -n "$cli_volume" ]]; then
            local actual_volume
            actual_volume=$(DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" inspect --type container --format '{{range .Mounts}}{{if eq .Destination "/mnt/agent-data"}}{{.Name}}{{end}}{{end}}' -- "$resolved_container_name" 2>/dev/null) || actual_volume=""
            if [[ -n "$actual_volume" && "$actual_volume" != "$resolved_volume" ]]; then
                echo "[ERROR] Container '$resolved_container_name' already uses volume '$actual_volume'." >&2
                echo "        Use --fresh to recreate with new volume, or remove container first." >&2
                return 1
            fi
        fi

        # Validate workspace match via FR-4 mount validation
        # This ensures the container's workspace mount matches the resolved workspace
        if ! _containai_validate_fr4_mounts "$selected_context" "$resolved_container_name" "$resolved_workspace" "$resolved_volume" "true"; then
            echo "[ERROR] Container workspace does not match. Use --fresh to recreate." >&2
            return 1
        fi

        # Save container name and volume to workspace state on successful use
        # Skip if --fresh flag was used (handled separately above with state writes)
        if [[ "$fresh_flag" != "true" ]]; then
            _containai_write_workspace_state "$resolved_workspace" "container_name" "$resolved_container_name" 2>/dev/null || true
            # Save volume if CLI override was provided
            if [[ -n "$cli_volume" ]]; then
                _containai_write_workspace_state "$resolved_workspace" "data_volume" "$resolved_volume" 2>/dev/null || true
            else
                # Sync actual mounted volume to workspace state if missing
                # This self-heals state for existing containers
                local existing_ws_volume
                existing_ws_volume=$(_containai_read_workspace_key "$resolved_workspace" "data_volume" 2>/dev/null) || existing_ws_volume=""
                # Only self-heal if no env override (env values shouldn't become "sticky")
                if [[ -z "$existing_ws_volume" ]] && [[ -z "${CONTAINAI_DATA_VOLUME:-}" ]]; then
                    local actual_volume
                    actual_volume=$(DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" inspect --type container --format '{{range .Mounts}}{{if eq .Destination "/mnt/agent-data"}}{{.Name}}{{end}}{{end}}' -- "$resolved_container_name" 2>/dev/null) || actual_volume=""
                    if [[ -n "$actual_volume" ]]; then
                        _containai_write_workspace_state "$resolved_workspace" "data_volume" "$actual_volume" 2>/dev/null || true
                    fi
                fi
            fi
        elif [[ -n "$cli_volume" ]]; then
            # If --fresh was used with a CLI override, persist the override
            _containai_write_workspace_state "$resolved_workspace" "data_volume" "$resolved_volume" 2>/dev/null || true
        fi

        # Print container/volume info if verbose (uses _cai_info which checks verbose state)
        # Only print here when container existed before this call
        # Skip if --fresh was set (start_container already printed) or container was just created
        if [[ "$verbose_flag" == "true" && "$fresh_flag" != "true" ]]; then
            # Get actual mounted volume from container (source of truth for what's really mounted)
            # Inspect .Mounts to find the volume at /mnt/agent-data - this is the real mounted volume
            local actual_volume
            actual_volume=$(DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" inspect --type container --format '{{range .Mounts}}{{if eq .Destination "/mnt/agent-data"}}{{.Name}}{{end}}{{end}}' -- "$resolved_container_name" 2>/dev/null) || actual_volume=""
            _cai_info "Container: $resolved_container_name"
            _cai_info "Volume: ${actual_volume:-$resolved_volume}"
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

# Exec subcommand handler - runs arbitrary commands in container via SSH
# Uses _cai_ssh_run with --login-shell for proper environment sourcing
_containai_exec_cmd() {
    local cli_volume=""
    local workspace=""
    local explicit_config=""
    local container_name=""
    local cli_template=""
    local fresh_flag=false
    local force_flag=false
    local quiet_flag=false
    local verbose_flag=false
    local debug_flag=false
    local -a exec_cmd=()
    # Reset channel override (global for registry.sh)
    _CAI_CHANNEL_OVERRIDE=""

    # Parse arguments - stop at first non-option or after --
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
            --channel)
                if [[ -z "${2-}" ]]; then
                    echo "[ERROR] --channel requires a value" >&2
                    return 1
                fi
                _CAI_CHANNEL_OVERRIDE="$2"
                shift 2
                ;;
            --channel=*)
                _CAI_CHANNEL_OVERRIDE="${1#--channel=}"
                if [[ -z "$_CAI_CHANNEL_OVERRIDE" ]]; then
                    echo "[ERROR] --channel requires a value" >&2
                    return 1
                fi
                shift
                ;;
            --fresh)
                fresh_flag=true
                shift
                ;;
            --restart)
                # Note: --restart is not supported in exec (different semantics from run)
                echo "[ERROR] --restart is not supported in cai exec" >&2
                echo "[HINT] Use --fresh to recreate the container, or 'cai run --restart' to restart the container" >&2
                return 1
                ;;
            --force)
                force_flag=true
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
            --help | -h)
                _containai_exec_help
                return 0
                ;;
            --)
                # Everything after -- is the command
                shift
                exec_cmd=("$@")
                break
                ;;
            -*)
                # Unknown option - could be part of command (e.g., ls -la)
                # Stop parsing and treat rest as command
                exec_cmd=("$@")
                break
                ;;
            *)
                # First non-option argument is start of command
                exec_cmd=("$@")
                break
                ;;
        esac
    done

    # Validate that a command was provided
    if [[ ${#exec_cmd[@]} -eq 0 ]]; then
        echo "[ERROR] No command specified" >&2
        echo "Usage: cai exec [options] [--] <command> [args...]" >&2
        return 1
    fi

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

    # Variables to resolve
    local resolved_workspace=""
    local resolved_volume=""
    local resolved_container_name=""
    local selected_context=""

    # === EARLY BRANCH: --container mode ===
    if [[ -n "$container_name" ]]; then
        # Try to find existing container
        local find_rc container_exists="false"
        if selected_context=$(_cai_find_container_by_name "$container_name" "$explicit_config" "$PWD"); then
            container_exists="true"
        else
            find_rc=$?
            if [[ $find_rc -eq 2 ]]; then
                return 1  # Error already printed (ambiguity)
            elif [[ $find_rc -eq 3 ]]; then
                return 1  # Error already printed (config parse)
            fi
        fi

        if [[ "$container_exists" == "true" ]]; then
            # Container exists - derive workspace/volume from labels
            local -a docker_cmd=(docker --context "$selected_context")

            # Verify container is managed by ContainAI
            local is_managed container_image
            is_managed=$(DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" inspect --type container --format '{{with index .Config.Labels "containai.managed"}}{{.}}{{end}}' -- "$container_name" 2>/dev/null) || is_managed=""
            if [[ "$is_managed" != "true" ]]; then
                container_image=$(DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" inspect --type container --format '{{.Config.Image}}' -- "$container_name" 2>/dev/null) || container_image=""
                if [[ "$container_image" != "${_CONTAINAI_DEFAULT_REPO}:"* ]]; then
                    echo "[ERROR] Container $container_name exists but is not managed by ContainAI" >&2
                    echo "[HINT] Remove the conflicting container or use a different name" >&2
                    return 15
                fi
            fi

            # Derive workspace from container labels
            resolved_workspace=$(DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" inspect --type container --format '{{with index .Config.Labels "containai.workspace"}}{{.}}{{end}}' -- "$container_name" 2>/dev/null) || resolved_workspace=""
            if [[ -z "$resolved_workspace" ]]; then
                echo "[ERROR] Container $container_name is missing workspace label" >&2
                return 1
            fi

            # Derive data volume from container labels
            resolved_volume=$(DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" inspect --type container --format '{{with index .Config.Labels "containai.data-volume"}}{{.}}{{end}}' -- "$container_name" 2>/dev/null) || resolved_volume=""
            if [[ -z "$resolved_volume" ]]; then
                echo "[ERROR] Container $container_name is missing data-volume label" >&2
                return 1
            fi

            resolved_container_name="$container_name"
        else
            # Container doesn't exist - will create it
            local workspace_input
            workspace_input="${workspace:-$PWD}"
            resolved_workspace=$(_cai_normalize_path "$workspace_input")
            if [[ ! -d "$resolved_workspace" ]]; then
                echo "[ERROR] Workspace path does not exist: $workspace_input" >&2
                return 1
            fi

            if ! resolved_volume=$(_containai_resolve_volume "$cli_volume" "$resolved_workspace" "$explicit_config"); then
                echo "[ERROR] Failed to resolve data volume" >&2
                return 1
            fi

            # Select context for new container
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
                config_file=$(_containai_find_config "$resolved_workspace")
                if [[ -n "$config_file" ]]; then
                    _containai_parse_config "$config_file" "$resolved_workspace" 2>/dev/null || true
                fi
            fi
            local config_context_override="${_CAI_SECURE_ENGINE_CONTEXT:-}"

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

            resolved_container_name="$container_name"
        fi
    else
        # === STANDARD MODE: Resolve from workspace ===
        local workspace_input
        workspace_input="${workspace:-$PWD}"
        resolved_workspace=$(_cai_normalize_path "$workspace_input")
        if [[ ! -d "$resolved_workspace" ]]; then
            echo "[ERROR] Workspace path does not exist: $workspace_input" >&2
            return 1
        fi

        # Resolve volume
        if ! resolved_volume=$(_containai_resolve_volume "$cli_volume" "$resolved_workspace" "$explicit_config"); then
            echo "[ERROR] Failed to resolve data volume" >&2
            return 1
        fi

        # === CONFIG PARSING (for context selection) ===
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
            config_file=$(_containai_find_config "$resolved_workspace")
            if [[ -n "$config_file" ]]; then
                _containai_parse_config "$config_file" "$resolved_workspace" 2>/dev/null || true
            fi
        fi
        local config_context_override="${_CAI_SECURE_ENGINE_CONTEXT:-}"

        # Auto-select Docker context
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
        local -a docker_cmd=(docker --context "$selected_context")

        # Resolve container name
        local find_rc
        if resolved_container_name=$(_cai_find_workspace_container "$resolved_workspace" "$selected_context"); then
            : # Found existing container
        else
            find_rc=$?
            if [[ $find_rc -eq 2 ]]; then
                return 1
            fi
            if resolved_container_name=$(_cai_resolve_container_name "$resolved_workspace" "$selected_context"); then
                : # Got name for creation
            else
                find_rc=$?
                if [[ $find_rc -eq 2 ]]; then
                    return 1
                fi
                echo "[ERROR] Failed to resolve container name for workspace: $resolved_workspace" >&2
                return 1
            fi
        fi
    fi

    # Build docker command prefix
    local -a docker_cmd=(docker --context "$selected_context")

    # Handle --fresh flag: remove and recreate container
    if [[ "$fresh_flag" == "true" ]]; then
        _cai_info "Recreating container..."

        # Check if container exists
        if DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" inspect --type container -- "$resolved_container_name" >/dev/null 2>&1; then
            # Verify ownership before removing
            local fresh_label_val fresh_image_fallback
            fresh_label_val=$(DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" inspect --type container --format '{{index .Config.Labels "containai.managed"}}' -- "$resolved_container_name" 2>/dev/null) || fresh_label_val=""
            if [[ "$fresh_label_val" != "true" ]]; then
                fresh_image_fallback=$(DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" inspect --type container --format '{{.Config.Image}}' -- "$resolved_container_name" 2>/dev/null) || fresh_image_fallback=""
                if [[ "$fresh_image_fallback" != "${_CONTAINAI_DEFAULT_REPO}:"* ]]; then
                    echo "[ERROR] Cannot use --fresh - container '$resolved_container_name' was not created by ContainAI" >&2
                    return 1
                fi
            fi

            # Get SSH port before removal for cleanup
            local fresh_ssh_port
            fresh_ssh_port=$(_cai_get_container_ssh_port "$resolved_container_name" "$selected_context") || fresh_ssh_port=""

            # Stop and remove container
            local fresh_stop_output fresh_rm_output
            fresh_stop_output=$(DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" stop -- "$resolved_container_name" 2>&1) || {
                if ! printf '%s' "$fresh_stop_output" | grep -qiE "is not running"; then
                    echo "$fresh_stop_output" >&2
                fi
            }
            fresh_rm_output=$(DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" rm -- "$resolved_container_name" 2>&1) || {
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
        # Pass '-- true' to run a no-op command instead of starting the default agent
        local -a create_args=()
        create_args+=(--data-volume "$resolved_volume")
        create_args+=(--workspace "$resolved_workspace")
        create_args+=(--detached)
        create_args+=(--name "$resolved_container_name")
        if [[ -n "$explicit_config" ]]; then
            create_args+=(--config "$explicit_config")
        fi
        if [[ "$force_flag" == "true" ]]; then
            create_args+=(--force)
        fi
        if [[ "$quiet_flag" == "true" ]]; then
            create_args+=(--quiet)
        fi
        if [[ "$verbose_flag" == "true" ]]; then
            create_args+=(--verbose)
        fi
        if [[ -n "$selected_context" ]]; then
            create_args+=(--docker-context "$selected_context")
        fi
        if [[ -n "$cli_template" ]]; then
            create_args+=(--template "$cli_template")
        fi
        # Run 'true' as no-op to avoid starting default agent
        create_args+=(-- true)

        if ! _containai_start_container "${create_args[@]}"; then
            echo "[ERROR] Failed to create container" >&2
            return 1
        fi

        # Save container name and volume to workspace state after --fresh recreation
        _containai_write_workspace_state "$resolved_workspace" "container_name" "$resolved_container_name" 2>/dev/null || true
        # Persist volume: CLI override always, or non-env (--fresh without env override)
        if [[ -n "$cli_volume" ]] || [[ -z "${CONTAINAI_DATA_VOLUME:-}" ]]; then
            _containai_write_workspace_state "$resolved_workspace" "data_volume" "$resolved_volume" 2>/dev/null || true
        fi
    fi

    # Check if container exists; if not, create it first
    if ! DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" inspect --type container -- "$resolved_container_name" >/dev/null 2>&1; then
        _cai_info "Container not found, creating..."

        # Pass '-- true' to run a no-op command instead of starting the default agent
        local -a create_args=()
        create_args+=(--data-volume "$resolved_volume")
        create_args+=(--workspace "$resolved_workspace")
        create_args+=(--detached)
        create_args+=(--name "$resolved_container_name")
        if [[ -n "$explicit_config" ]]; then
            create_args+=(--config "$explicit_config")
        fi
        if [[ "$force_flag" == "true" ]]; then
            create_args+=(--force)
        fi
        if [[ "$quiet_flag" == "true" ]]; then
            create_args+=(--quiet)
        fi
        if [[ "$verbose_flag" == "true" ]]; then
            create_args+=(--verbose)
        fi
        if [[ -n "$selected_context" ]]; then
            create_args+=(--docker-context "$selected_context")
        fi
        if [[ -n "$cli_template" ]]; then
            create_args+=(--template "$cli_template")
        fi
        # Run 'true' as no-op to avoid starting default agent
        create_args+=(-- true)

        if ! _containai_start_container "${create_args[@]}"; then
            echo "[ERROR] Failed to create container" >&2
            return 1
        fi

        # Save container name and volume to workspace state
        _containai_write_workspace_state "$resolved_workspace" "container_name" "$resolved_container_name" 2>/dev/null || true
        # Persist volume: CLI override always, or first-use (no existing state) without env override
        if [[ -n "$cli_volume" ]]; then
            _containai_write_workspace_state "$resolved_workspace" "data_volume" "$resolved_volume" 2>/dev/null || true
        else
            local existing_ws_vol
            existing_ws_vol=$(_containai_read_workspace_key "$resolved_workspace" "data_volume" 2>/dev/null) || existing_ws_vol=""
            if [[ -z "$existing_ws_vol" ]] && [[ -z "${CONTAINAI_DATA_VOLUME:-}" ]]; then
                _containai_write_workspace_state "$resolved_workspace" "data_volume" "$resolved_volume" 2>/dev/null || true
            fi
        fi
    else
        # Container exists - validate ownership and workspace mounts
        local exec_label_val exec_image_val
        exec_label_val=$(DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" inspect --type container --format '{{index .Config.Labels "containai.managed"}}' -- "$resolved_container_name" 2>/dev/null) || exec_label_val=""
        if [[ "$exec_label_val" != "true" ]]; then
            exec_image_val=$(DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" inspect --type container --format '{{.Config.Image}}' -- "$resolved_container_name" 2>/dev/null) || exec_image_val=""
            if [[ "$exec_image_val" != "${_CONTAINAI_DEFAULT_REPO}:"* ]]; then
                echo "[ERROR] Container '$resolved_container_name' was not created by ContainAI" >&2
                return 15
            fi
        fi

        # Template mismatch check for existing containers (when --template specified)
        if [[ -n "$cli_template" ]]; then
            # Validate template name
            if ! _cai_validate_template_name "$cli_template"; then
                _cai_error "Invalid template name: $cli_template"
                _cai_warn "Template names must be lowercase alphanumeric with dashes/underscores/dots"
                return 1
            fi
            # Get container's template label
            local exec_container_template
            exec_container_template=$(DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" inspect --type container --format '{{with index .Config.Labels "ai.containai.template"}}{{.}}{{end}}' -- "$resolved_container_name" 2>/dev/null) || exec_container_template=""
            if [[ -z "$exec_container_template" ]]; then
                # Missing label = pre-existing container; allow only if --template default
                if [[ "$cli_template" != "default" ]]; then
                    _cai_error "Container was created before templates. Use --fresh to rebuild with template."
                    _cai_warn "Container: $resolved_container_name"
                    _cai_warn "Requested template: $cli_template"
                    return 1
                fi
            elif [[ "$exec_container_template" != "$cli_template" ]]; then
                # Label mismatch
                _cai_error "Container exists with template '$exec_container_template'. Use --fresh to rebuild."
                _cai_warn "Container: $resolved_container_name"
                _cai_warn "Requested template: $cli_template"
                _cai_warn "Existing template: $exec_container_template"
                return 1
            fi
        fi

        # Check if --data-volume was provided with a different volume than the container's current volume
        # This error helps users understand why the command fails (spec: fn-36-rb7.12)
        if [[ -n "$cli_volume" ]]; then
            local actual_volume
            actual_volume=$(DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" inspect --type container --format '{{range .Mounts}}{{if eq .Destination "/mnt/agent-data"}}{{.Name}}{{end}}{{end}}' -- "$resolved_container_name" 2>/dev/null) || actual_volume=""
            if [[ -n "$actual_volume" && "$actual_volume" != "$resolved_volume" ]]; then
                echo "[ERROR] Container '$resolved_container_name' already uses volume '$actual_volume'." >&2
                echo "        Use --fresh to recreate with new volume, or remove container first." >&2
                return 1
            fi
        fi

        # FR-4: Validate container mounts match expected configuration (type + source)
        # This prevents exec from running in a container with mismatched workspace
        if ! _containai_validate_fr4_mounts "$selected_context" "$resolved_container_name" "$resolved_workspace" "$resolved_volume" "false"; then
            echo "[ERROR] Container workspace does not match. Use --fresh to recreate." >&2
            return 1
        fi

        # Check for SSH port conflict on stopped containers and auto-recreate if needed
        # This handles the case where the allocated port is now in use by another process
        local exec_container_state
        exec_container_state=$(DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" inspect --format '{{.State.Status}}' -- "$resolved_container_name" 2>/dev/null) || exec_container_state=""
        if [[ "$exec_container_state" == "exited" || "$exec_container_state" == "created" ]]; then
            local exec_ssh_port exec_port_check_rc
            if exec_ssh_port=$(_cai_get_container_ssh_port "$resolved_container_name" "$selected_context"); then
                if _cai_is_port_available "$exec_ssh_port"; then
                    exec_port_check_rc=0
                else
                    exec_port_check_rc=$?
                fi
                if [[ $exec_port_check_rc -eq 2 ]]; then
                    echo "[ERROR] Cannot verify SSH port availability (ss command failed)" >&2
                    echo "[ERROR] Ensure 'ss' (iproute2) is installed" >&2
                    return 1
                elif [[ $exec_port_check_rc -eq 1 ]]; then
                    # Port is in use - recreate container with new port
                    # Warnings always emit regardless of quiet flag
                    _cai_warn "SSH port $exec_ssh_port is in use by another process"
                    _cai_info "Recreating container with new port allocation..."
                    # Remove the old container
                    if ! DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" rm -f "$resolved_container_name" >/dev/null 2>&1; then
                        echo "[ERROR] Failed to remove container for port reallocation" >&2
                        return 1
                    fi
                    _cai_cleanup_container_ssh "$resolved_container_name" "$exec_ssh_port"
                    # Recreate container
                    local -a recreate_args=()
                    recreate_args+=(--data-volume "$resolved_volume")
                    recreate_args+=(--workspace "$resolved_workspace")
                    recreate_args+=(--detached)
                    recreate_args+=(--name "$resolved_container_name")
                    if [[ -n "$explicit_config" ]]; then
                        recreate_args+=(--config "$explicit_config")
                    fi
                    if [[ -n "$cli_template" ]]; then
                        recreate_args+=(--template "$cli_template")
                    fi
                    if [[ "$force_flag" == "true" ]]; then
                        recreate_args+=(--force)
                    fi
                    if [[ "$quiet_flag" == "true" ]]; then
                        recreate_args+=(--quiet)
                    fi
                    if [[ "$verbose_flag" == "true" ]]; then
                        recreate_args+=(--verbose)
                    fi
                    if [[ -n "$selected_context" ]]; then
                        recreate_args+=(--docker-context "$selected_context")
                    fi
                    recreate_args+=(-- true)
                    if ! _containai_start_container "${recreate_args[@]}"; then
                        echo "[ERROR] Failed to recreate container" >&2
                        return 1
                    fi
                fi
            fi
        fi

        # Save container name and volume to workspace state
        _containai_write_workspace_state "$resolved_workspace" "container_name" "$resolved_container_name" 2>/dev/null || true
        # Save volume if CLI override was provided
        if [[ -n "$cli_volume" ]]; then
            _containai_write_workspace_state "$resolved_workspace" "data_volume" "$resolved_volume" 2>/dev/null || true
        else
            # Sync actual mounted volume to workspace state if missing
            # This self-heals state for existing containers
            local existing_ws_volume
            existing_ws_volume=$(_containai_read_workspace_key "$resolved_workspace" "data_volume" 2>/dev/null) || existing_ws_volume=""
            # Only self-heal if no env override (env values shouldn't become "sticky")
            if [[ -z "$existing_ws_volume" ]] && [[ -z "${CONTAINAI_DATA_VOLUME:-}" ]]; then
                local actual_volume
                actual_volume=$(DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" inspect --type container --format '{{range .Mounts}}{{if eq .Destination "/mnt/agent-data"}}{{.Name}}{{end}}{{end}}' -- "$resolved_container_name" 2>/dev/null) || actual_volume=""
                if [[ -n "$actual_volume" ]]; then
                    _containai_write_workspace_state "$resolved_workspace" "data_volume" "$actual_volume" 2>/dev/null || true
                fi
            fi
        fi
    fi

    # Run command via SSH with login shell
    local quiet_arg=""
    local force_arg=""
    local allocate_tty="false"

    if [[ "$quiet_flag" == "true" ]]; then
        quiet_arg="true"
    fi
    if [[ "$fresh_flag" == "true" ]]; then
        force_arg="true"
    fi

    # Allocate TTY if stdin is a TTY
    if [[ -t 0 ]]; then
        allocate_tty="true"
    fi

    # Run with --login-shell for proper environment sourcing
    _cai_ssh_run "$resolved_container_name" "$selected_context" "$force_arg" "$quiet_arg" "false" "$allocate_tty" --login-shell "${exec_cmd[@]}"
}

# Default (run container) handler
_containai_run_cmd() {
    local cli_volume=""
    local workspace=""
    local explicit_config=""
    local container_name=""
    local image_tag=""
    local cli_template=""
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
    local verbose_flag=""
    local debug_flag=""
    local dry_run_flag=""
    local mount_docker_socket=""
    local please_root_my_host=""
    local -a env_vars=()
    local -a agent_args=()
    # Reset channel override (global for registry.sh)
    _CAI_CHANNEL_OVERRIDE=""

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
                _cai_set_quiet
                shift
                ;;
            --verbose)
                verbose_flag="--verbose"
                _cai_set_verbose
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
            --channel)
                if [[ -z "${2-}" ]]; then
                    echo "[ERROR] --channel requires a value" >&2
                    return 1
                fi
                _CAI_CHANNEL_OVERRIDE="$2"
                shift 2
                ;;
            --channel=*)
                _CAI_CHANNEL_OVERRIDE="${1#--channel=}"
                if [[ -z "$_CAI_CHANNEL_OVERRIDE" ]]; then
                    echo "[ERROR] --channel requires a value" >&2
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
                _cai_error "--volume is not supported in containai run"
                _cai_warn "FR-4 restricts mounts to workspace + data volume only"
                _cai_warn "Use 'containai shell' if you need extra mounts"
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

    # Variables to resolve
    local resolved_workspace=""
    local resolved_volume=""
    local resolved_credentials=""
    local resolved_container_name=""  # Container name resolved in standard mode
    local container_workspace=""  # Workspace to use for state write (may differ from resolved_workspace)
    local run_context=""  # Docker context used for this run (for self-heal inspect)

    # Track if we need to save container name to workspace state after success
    local should_save_container_name="false"

    # Build args for _containai_start_container
    local -a start_args=()

    if [[ -n "$container_name" ]]; then
        # === --container mode: use existing if found, create if missing ===
        # Try to find existing container
        local lookup_rc lookup_context
        # _cai_find_container_by_name returns context on stdout; let stderr flow through
        if lookup_context=$(_cai_find_container_by_name "$container_name" "$explicit_config" "$PWD"); then
            lookup_rc=0
        else
            lookup_rc=$?
        fi

        if [[ $lookup_rc -eq 0 ]]; then
            # Container exists - derive workspace/volume from labels
            local -a docker_cmd=(docker --context "${lookup_context:-default}")

            # Verify container is managed by ContainAI (label or image fallback for legacy containers)
            local is_managed container_image
            is_managed=$(DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" inspect --type container --format '{{with index .Config.Labels "containai.managed"}}{{.}}{{end}}' -- "$container_name" 2>/dev/null) || is_managed=""
            if [[ "$is_managed" != "true" ]]; then
                # Fallback: check if image is from our repo (for legacy containers without label)
                container_image=$(DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" inspect --type container --format '{{.Config.Image}}' -- "$container_name" 2>/dev/null) || container_image=""
                if [[ "$container_image" != "${_CONTAINAI_DEFAULT_REPO}:"* ]]; then
                    echo "[ERROR] Container $container_name exists but is not managed by ContainAI" >&2
                    echo "[HINT] Remove the conflicting container or use a different name" >&2
                    return 1
                fi
            fi

            # Derive workspace from container labels
            resolved_workspace=$(DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" inspect --type container --format '{{with index .Config.Labels "containai.workspace"}}{{.}}{{end}}' -- "$container_name" 2>/dev/null) || resolved_workspace=""
            if [[ -z "$resolved_workspace" ]]; then
                echo "[ERROR] Container $container_name is missing workspace label" >&2
                return 1
            fi

            # Derive data volume from container labels
            resolved_volume=$(DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" inspect --type container --format '{{with index .Config.Labels "containai.data-volume"}}{{.}}{{end}}' -- "$container_name" 2>/dev/null) || resolved_volume=""
            if [[ -z "$resolved_volume" ]]; then
                echo "[ERROR] Container $container_name is missing data-volume label" >&2
                return 1
            fi

            container_workspace="$resolved_workspace"
            should_save_container_name="true"

            # Pass the found context to ensure we use the same context where container exists
            start_args+=(--docker-context "$lookup_context")
            run_context="$lookup_context"
        elif [[ $lookup_rc -eq 2 ]] || [[ $lookup_rc -eq 3 ]]; then
            # Ambiguity or config parse error - helper already printed details
            return 1
        else
            # Container not found - will create it using PWD as workspace
            local workspace_input
            workspace_input="${workspace:-$PWD}"
            resolved_workspace=$(_cai_normalize_path "$workspace_input")
            if [[ ! -d "$resolved_workspace" ]]; then
                echo "[ERROR] Workspace path does not exist: $workspace_input" >&2
                return 1
            fi

            # Resolve volume for the new container
            if ! resolved_volume=$(_containai_resolve_volume "$cli_volume" "$resolved_workspace" "$explicit_config"); then
                echo "[ERROR] Failed to resolve data volume" >&2
                return 1
            fi

            container_workspace="$resolved_workspace"
            should_save_container_name="true"
        fi

        start_args+=(--name "$container_name")
        start_args+=(--data-volume "$resolved_volume")
        start_args+=(--workspace "$resolved_workspace")

        # Pass explicit config if provided (for context resolution)
        if [[ -n "$explicit_config" ]]; then
            start_args+=(--config "$explicit_config")
        fi
    else
        # === Standard mode: resolve from workspace ===
        local workspace_input
        workspace_input="${workspace:-$PWD}"
        resolved_workspace=$(_cai_normalize_path "$workspace_input")
        if [[ ! -d "$resolved_workspace" ]]; then
            echo "[ERROR] Workspace path does not exist: $workspace_input" >&2
            return 1
        fi

        # Resolve volume
        if ! resolved_volume=$(_containai_resolve_volume "$cli_volume" "$resolved_workspace" "$explicit_config"); then
            echo "[ERROR] Failed to resolve data volume" >&2
            return 1
        fi

        container_workspace="$resolved_workspace"

        # === CONFIG PARSING (for context selection) ===
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

        # Auto-select Docker context based on isolation availability
        local run_debug_mode=""
        if [[ -n "$debug_flag" ]]; then
            run_debug_mode="debug"
        fi
        local run_verbose_str="false"
        if [[ -n "$verbose_flag" ]]; then
            run_verbose_str="true"
        fi
        local selected_context=""
        if ! selected_context=$(_cai_select_context "$config_context_override" "$run_debug_mode" "$run_verbose_str"); then
            if [[ -n "$force_flag" ]]; then
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

        # Resolve container name using shared lookup helper
        # Note: resolved_container_name is declared at function scope (line 4183)
        local find_rc
        if resolved_container_name=$(_cai_find_workspace_container "$resolved_workspace" "$selected_context"); then
            : # Found existing container
        else
            find_rc=$?
            if [[ $find_rc -eq 2 ]]; then
                return 1  # Multiple containers - error already printed
            fi
            # Not found - resolve name for creation
            if ! resolved_container_name=$(_cai_resolve_container_name "$resolved_workspace" "$selected_context"); then
                find_rc=$?
                if [[ $find_rc -eq 2 ]]; then
                    return 1
                fi
                echo "[ERROR] Failed to resolve container name for workspace: $resolved_workspace" >&2
                return 1
            fi
        fi

        start_args+=(--name "$resolved_container_name")
        start_args+=(--docker-context "$selected_context")
        start_args+=(--data-volume "$resolved_volume")
        start_args+=(--workspace "$resolved_workspace")
        run_context="$selected_context"

        # Pass explicit config if provided (for context resolution)
        if [[ -n "$explicit_config" ]]; then
            start_args+=(--config "$explicit_config")
        fi

        # Add volume mismatch warn for implicit volume selection
        if [[ -z "$cli_volume" ]] && [[ -z "$explicit_config" ]]; then
            start_args+=(--volume-mismatch-warn)
        fi

        # Mark that we should save workspace state after success
        should_save_container_name="true"
    fi

    # Resolve credentials (CLI > env > config > default)
    resolved_credentials=$(_containai_resolve_credentials "$credentials" "$resolved_workspace" "$explicit_config" "")
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
    if [[ -n "$verbose_flag" ]]; then
        start_args+=("$verbose_flag")
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
    if [[ -n "$cli_template" ]]; then
        start_args+=(--template "$cli_template")
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

    # Run container and save workspace state only on success
    local start_rc
    _containai_start_container "${start_args[@]}"
    start_rc=$?

    # Save container name and volume to workspace state only after successful create/use
    # Skip on dry-run (no actual container created/used)
    # Use container_workspace (which is the container's labeled workspace, not necessarily PWD)
    if [[ $start_rc -eq 0 ]] && [[ -n "$container_workspace" ]] && [[ -z "$dry_run_flag" ]]; then
        if [[ "$should_save_container_name" == "true" ]]; then
            # Determine container name to save (from --container mode or standard mode resolution)
            local save_container_name="${container_name:-$resolved_container_name}"
            if [[ -n "$save_container_name" ]]; then
                _containai_write_workspace_state "$container_workspace" "container_name" "$save_container_name" 2>/dev/null || true
            fi
            # Persist volume: CLI override always, or first-use (no existing state) without env override
            if [[ -n "$cli_volume" ]]; then
                _containai_write_workspace_state "$container_workspace" "data_volume" "$resolved_volume" 2>/dev/null || true
            else
                # Sync actual mounted volume to workspace state if missing
                # This self-heals state for existing containers (mirrors shell/exec behavior)
                local existing_ws_vol
                existing_ws_vol=$(_containai_read_workspace_key "$container_workspace" "data_volume" 2>/dev/null) || existing_ws_vol=""
                # Only self-heal if no env override (env values shouldn't become "sticky")
                if [[ -z "$existing_ws_vol" ]] && [[ -z "${CONTAINAI_DATA_VOLUME:-}" ]]; then
                    if [[ -n "$run_context" ]]; then
                        # Container existed - get actual mounted volume (source of truth)
                        # Use context-aware inspect to avoid reading wrong container in multi-context setups
                        local actual_volume inspect_container_name
                        inspect_container_name="${container_name:-$resolved_container_name}"
                        actual_volume=$(DOCKER_CONTEXT= DOCKER_HOST= docker --context "$run_context" inspect --type container --format '{{range .Mounts}}{{if eq .Destination "/mnt/agent-data"}}{{.Name}}{{end}}{{end}}' -- "$inspect_container_name" 2>/dev/null) || actual_volume=""
                        if [[ -n "$actual_volume" ]]; then
                            _containai_write_workspace_state "$container_workspace" "data_volume" "$actual_volume" 2>/dev/null || true
                        fi
                    else
                        # Container was just created (--container mode, not found) - persist resolved_volume
                        # No self-heal needed; resolved_volume is what was passed to _containai_start_container
                        _containai_write_workspace_state "$container_workspace" "data_volume" "$resolved_volume" 2>/dev/null || true
                    fi
                fi
            fi
        elif [[ -n "$cli_volume" ]]; then
            # CLI volume override - save even if not first use
            _containai_write_workspace_state "$container_workspace" "data_volume" "$resolved_volume" 2>/dev/null || true
        fi
    fi

    return $start_rc
}

# ==============================================================================
# Shell Completion
# ==============================================================================

# Cache for dynamic completions (containers and volumes)
# Format: timestamp:value1,value2,value3
_CAI_COMPLETION_CACHE_CONTAINERS=""
_CAI_COMPLETION_CACHE_VOLUMES=""
_CAI_COMPLETION_CACHE_TTL=5  # seconds

# Portable sub-second timeout for completion
# Falls back to returning empty (skip command) if no timeout available
# Arguments: $1 = timeout in seconds (can be fractional like 0.5), $* = command
# Returns: command exit code, 124 on timeout, or 1 if no timeout command
_cai_completion_timeout() {
    local timeout_sec="${1:-1}"
    shift

    # Try GNU timeout (Linux) or gtimeout (macOS via coreutils)
    if command -v timeout >/dev/null 2>&1; then
        timeout "$timeout_sec" "$@"
        return $?
    elif command -v gtimeout >/dev/null 2>&1; then
        gtimeout "$timeout_sec" "$@"
        return $?
    fi

    # No timeout available - return empty to avoid potential hangs
    # Per spec: >500ms should fall back to no suggestions
    return 1
}

# Get ContainAI containers for completion (with caching)
# Outputs: space-separated container names
# Returns: 0 always (empty output on failure/timeout)
_cai_completion_get_containers() {
    local now cache_time
    now=$(date +%s)

    # Check cache
    if [[ -n "$_CAI_COMPLETION_CACHE_CONTAINERS" ]]; then
        cache_time="${_CAI_COMPLETION_CACHE_CONTAINERS%%:*}"
        if (( now - cache_time < _CAI_COMPLETION_CACHE_TTL )); then
            printf '%s' "${_CAI_COMPLETION_CACHE_CONTAINERS#*:}"
            return 0
        fi
    fi

    # Docker lookup with 500ms timeout using portable helper
    # Clear DOCKER_HOST/DOCKER_CONTEXT to ensure we only hit local containai-docker
    local containers docker_host docker_context
    docker_host="${_CAI_CONTAINAI_DOCKER_SOCKET:-/run/containai-docker/docker.sock}"
    docker_context="${_CAI_CONTAINAI_DOCKER_CONTEXT:-containai-docker}"
    if [[ -S "$docker_host" ]]; then
        # shellcheck disable=SC2016
        containers=$(DOCKER_HOST= DOCKER_CONTEXT= _cai_completion_timeout 0.5 docker --context "$docker_context" ps -a --filter "label=containai.managed=true" --format '{{.Names}}' 2>/dev/null | tr '\n' ' ') || containers=""
    fi

    # Update cache
    _CAI_COMPLETION_CACHE_CONTAINERS="${now}:${containers}"
    printf '%s' "$containers"
}

# Get data volumes for completion (with caching)
# Outputs: space-separated volume names
# Returns: 0 always (empty output on failure/timeout)
_cai_completion_get_volumes() {
    local now cache_time
    now=$(date +%s)

    # Check cache
    if [[ -n "$_CAI_COMPLETION_CACHE_VOLUMES" ]]; then
        cache_time="${_CAI_COMPLETION_CACHE_VOLUMES%%:*}"
        if (( now - cache_time < _CAI_COMPLETION_CACHE_TTL )); then
            printf '%s' "${_CAI_COMPLETION_CACHE_VOLUMES#*:}"
            return 0
        fi
    fi

    # Docker lookup with 500ms timeout using portable helper
    # Clear DOCKER_HOST/DOCKER_CONTEXT to ensure we only hit local containai-docker
    local volumes docker_host docker_context
    docker_host="${_CAI_CONTAINAI_DOCKER_SOCKET:-/run/containai-docker/docker.sock}"
    docker_context="${_CAI_CONTAINAI_DOCKER_CONTEXT:-containai-docker}"
    if [[ -S "$docker_host" ]]; then
        # shellcheck disable=SC2016
        volumes=$(DOCKER_HOST= DOCKER_CONTEXT= _cai_completion_timeout 0.5 docker --context "$docker_context" volume ls --filter "label=containai.managed=true" --format '{{.Name}}' 2>/dev/null | tr '\n' ' ') || volumes=""
    fi

    # Update cache
    _CAI_COMPLETION_CACHE_VOLUMES="${now}:${volumes}"
    printf '%s' "$volumes"
}

# Get template names from templates directory for completion
_cai_completion_get_templates() {
    local templates_dir="${HOME}/.config/containai/templates"
    local templates=""
    if [[ -d "$templates_dir" ]]; then
        # List directories (template names) under templates dir
        templates=$(find "$templates_dir" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; 2>/dev/null | tr '\n' ' ') || templates=""
    fi
    printf '%s' "$templates"
}

# Output bash completion script
_cai_completion_bash() {
    cat <<'BASH_COMPLETION'
# ContainAI bash completion
# Generated by: cai completion bash

_cai_completions() {
    local cur prev words cword
    _init_completion 2>/dev/null || {
        COMPREPLY=()
        cur="${COMP_WORDS[COMP_CWORD]}"
        prev="${COMP_WORDS[COMP_CWORD-1]}"
        words=("${COMP_WORDS[@]}")
        cword=$COMP_CWORD
    }

    # Subcommands
    local subcommands="run shell exec doctor setup validate docker import export sync stop status gc ssh links config template update refresh uninstall completion help version"

    # Global flags (--refresh is an alias for the refresh subcommand)
    local global_flags="-h --help --refresh"

    # Per-subcommand flags
    local run_flags="--data-volume --config -w --workspace --container --template --channel --image-tag --memory --cpus --fresh --restart --reset --force --detached -d --quiet -q --verbose --debug -D --dry-run -e --env --credentials --acknowledge-credential-risk --mount-docker-socket --please-root-my-host --allow-host-credentials --i-understand-this-exposes-host-credentials --allow-host-docker-socket --i-understand-this-grants-root-access -h --help"
    local shell_flags="--data-volume --config --workspace --container --template --channel --image-tag --memory --cpus --fresh --restart --reset --force --dry-run -q --quiet --verbose --debug -D -h --help"
    local exec_flags="--workspace -w --container --template --channel --data-volume --config --fresh --force -q --quiet --verbose --debug -D -h --help"
    local doctor_flags="--json --build-templates --reset-lima --workspace -w -h --help"
    local doctor_fix_subcommands="volume container template"
    local setup_flags="--dry-run --verbose --force -h --help"
    local validate_flags="--verbose --config --workspace -h --help"
    local docker_flags=""
    local import_flags="--dry-run --no-excludes --no-secrets --verbose --container --data-volume --config --workspace --from -h --help"
    local export_flags="-o --output --container --data-volume --config --workspace --no-excludes --verbose -h --help"
    local sync_flags="--dry-run --verbose -h --help"
    local stop_flags="--container --all --remove --force --export --verbose -h --help"
    local status_flags="--json --workspace --container --verbose -h --help"
    local gc_flags="--dry-run --force --age --images --verbose -h --help"
    local ssh_subcommands="cleanup"
    local ssh_cleanup_flags="--dry-run --verbose -h --help"
    local template_subcommands="upgrade"
    local template_flags="--dry-run -h --help"
    local links_subcommands="check fix"
    local links_flags="--workspace --name --config --quiet -q --verbose --dry-run -h --help"
    local config_subcommands="list get set unset"
    local config_flags="-g --global --workspace --verbose -h --help"
    local update_flags="--dry-run --stop-containers --force --lima-recreate --verbose -h --help"
    local refresh_flags="--rebuild --verbose -h --help"
    local uninstall_flags="--dry-run --containers --volumes --force --verbose -h --help"
    local completion_shells="bash zsh"

    # Find the subcommand (first non-flag argument after cai/containai)
    # Also detect --refresh as an alias for refresh subcommand
    local subcmd=""
    local subcmd_idx=0
    local i
    for ((i=1; i < cword; i++)); do
        # Check for --refresh alias first
        if [[ "${words[i]}" == "--refresh" ]]; then
            subcmd="refresh"
            subcmd_idx=$i
            break
        fi
        if [[ "${words[i]}" != -* ]]; then
            subcmd="${words[i]}"
            subcmd_idx=$i
            break
        fi
    done

    # No subcommand yet - complete subcommands
    if [[ -z "$subcmd" ]]; then
        COMPREPLY=($(compgen -W "$subcommands $global_flags" -- "$cur"))
        return
    fi

    # Handle dynamic completions for --container and --data-volume
    case "$prev" in
        --container)
            # Dynamic container completion with caching
            local containers
            containers=$(_cai_completion_get_containers 2>/dev/null) || containers=""
            COMPREPLY=($(compgen -W "$containers" -- "$cur"))
            return
            ;;
        --data-volume)
            # Dynamic volume completion with caching
            local volumes
            volumes=$(_cai_completion_get_volumes 2>/dev/null) || volumes=""
            COMPREPLY=($(compgen -W "$volumes" -- "$cur"))
            return
            ;;
        --workspace|-w|--config|-o|--output)
            # Directory/file completion (with fallback if bash-completion not available)
            if type _filedir &>/dev/null; then
                _filedir
            else
                COMPREPLY=($(compgen -f -- "$cur"))
            fi
            return
            ;;
        --template)
            # Template name completion from templates directory
            local templates templates_dir
            templates_dir="${HOME}/.config/containai/templates"
            if [[ -d "$templates_dir" ]]; then
                templates=$(find "$templates_dir" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; 2>/dev/null | tr '\n' ' ') || templates=""
            else
                templates=""
            fi
            COMPREPLY=($(compgen -W "$templates" -- "$cur"))
            return
            ;;
        --channel)
            # Channel name completion
            COMPREPLY=($(compgen -W "stable nightly" -- "$cur"))
            return
            ;;
        --image-tag|--memory|--cpus|--name|--from|-e|--env|--credentials)
            # Value expected, no completion
            return
            ;;
    esac

    # Complete based on subcommand
    case "$subcmd" in
        run)
            COMPREPLY=($(compgen -W "$run_flags" -- "$cur"))
            ;;
        shell)
            COMPREPLY=($(compgen -W "$shell_flags" -- "$cur"))
            ;;
        exec)
            COMPREPLY=($(compgen -W "$exec_flags" -- "$cur"))
            ;;
        doctor)
            # Check if 'fix' subcommand is present
            local has_fix=""
            for ((i=subcmd_idx+1; i < cword; i++)); do
                if [[ "${words[i]}" == "fix" ]]; then
                    has_fix="true"
                    break
                fi
            done
            if [[ -n "$has_fix" ]]; then
                COMPREPLY=($(compgen -W "$doctor_fix_subcommands --all" -- "$cur"))
            else
                COMPREPLY=($(compgen -W "fix $doctor_flags" -- "$cur"))
            fi
            ;;
        setup)
            COMPREPLY=($(compgen -W "$setup_flags" -- "$cur"))
            ;;
        validate)
            COMPREPLY=($(compgen -W "$validate_flags" -- "$cur"))
            ;;
        docker)
            # Delegate to docker completion with containai-docker context
            # Build docker command line from words after 'docker'
            local docker_context="${_CAI_CONTAINAI_DOCKER_CONTEXT:-containai-docker}"
            local docker_words=()
            local found_docker=""
            for ((i=0; i < ${#words[@]}; i++)); do
                if [[ "$found_docker" == "true" ]]; then
                    docker_words+=("${words[i]}")
                elif [[ "${words[i]}" == "docker" ]]; then
                    found_docker="true"
                fi
            done

            # Check if docker completion is available (Cobra-style __completeNoDesc)
            # Use __completeNoDesc to get plain completion words without tab-separated descriptions
            # Set context via DOCKER_CONTEXT env var for Cobra compatibility
            if command -v docker &>/dev/null; then
                local docker_out docker_candidates
                # Use timeout to avoid hanging if containai-docker context is slow/unreachable
                # Clear DOCKER_HOST to ensure DOCKER_CONTEXT takes effect
                docker_out=$(DOCKER_HOST= DOCKER_CONTEXT="$docker_context" _cai_completion_timeout 0.5 docker __completeNoDesc "${docker_words[@]}" 2>/dev/null) || docker_out=""
                if [[ -n "$docker_out" ]]; then
                    # Docker __completeNoDesc outputs completions one per line, with directive as last line
                    # Filter out the directive line (starts with :) and empty lines
                    docker_candidates=$(printf '%s\n' "$docker_out" | grep -v '^:' | grep -v '^$')
                    # Only return if we have actual completions, otherwise fall through to fallback
                    if [[ -n "$docker_candidates" ]]; then
                        COMPREPLY=($(compgen -W "$docker_candidates" -- "$cur"))
                        return
                    fi
                fi

                # Fallback to __complete (with descriptions) if __completeNoDesc unavailable
                docker_out=$(DOCKER_HOST= DOCKER_CONTEXT="$docker_context" _cai_completion_timeout 0.5 docker __complete "${docker_words[@]}" 2>/dev/null) || docker_out=""
                if [[ -n "$docker_out" ]]; then
                    docker_candidates=$(printf '%s\n' "$docker_out" | grep -v '^:' | grep -v '^$' | awk -F '\t' '{print $1}')
                    if [[ -n "$docker_candidates" ]]; then
                        COMPREPLY=($(compgen -W "$docker_candidates" -- "$cur"))
                        return
                    fi
                fi
            fi

            # Fallback: basic docker subcommands
            local docker_subcommands="attach build commit container cp create diff events exec export history image images import info inspect kill load login logout logs network node pause plugin port ps pull push rename restart rm rmi run save search secret service stack start stats stop swarm system tag top unpause update version volume wait"
            COMPREPLY=($(compgen -W "$docker_subcommands" -- "$cur"))
            ;;
        import)
            COMPREPLY=($(compgen -W "$import_flags" -- "$cur"))
            ;;
        export)
            COMPREPLY=($(compgen -W "$export_flags" -- "$cur"))
            ;;
        sync)
            COMPREPLY=($(compgen -W "$sync_flags" -- "$cur"))
            ;;
        stop)
            COMPREPLY=($(compgen -W "$stop_flags" -- "$cur"))
            ;;
        status)
            COMPREPLY=($(compgen -W "$status_flags" -- "$cur"))
            ;;
        gc)
            COMPREPLY=($(compgen -W "$gc_flags" -- "$cur"))
            ;;
        ssh)
            # Check for cleanup subcommand
            local ssh_sub=""
            for ((i=subcmd_idx+1; i < cword; i++)); do
                if [[ "${words[i]}" == "cleanup" ]]; then
                    ssh_sub="cleanup"
                    break
                fi
            done
            if [[ "$ssh_sub" == "cleanup" ]]; then
                COMPREPLY=($(compgen -W "$ssh_cleanup_flags" -- "$cur"))
            else
                COMPREPLY=($(compgen -W "$ssh_subcommands -h --help" -- "$cur"))
            fi
            ;;
        links)
            # Check for check/fix subcommand
            local links_sub=""
            for ((i=subcmd_idx+1; i < cword; i++)); do
                case "${words[i]}" in
                    check|fix) links_sub="${words[i]}"; break ;;
                esac
            done
            if [[ -n "$links_sub" ]]; then
                COMPREPLY=($(compgen -W "$links_flags" -- "$cur"))
            else
                COMPREPLY=($(compgen -W "$links_subcommands -h --help" -- "$cur"))
            fi
            ;;
        config)
            # Check for list/get/set/unset subcommand
            local config_sub=""
            for ((i=subcmd_idx+1; i < cword; i++)); do
                case "${words[i]}" in
                    list|get|set|unset) config_sub="${words[i]}"; break ;;
                esac
            done
            if [[ -n "$config_sub" ]]; then
                COMPREPLY=($(compgen -W "$config_flags" -- "$cur"))
            else
                COMPREPLY=($(compgen -W "$config_subcommands -h --help" -- "$cur"))
            fi
            ;;
        template)
            # Check for upgrade subcommand
            local template_sub=""
            for ((i=subcmd_idx+1; i < cword; i++)); do
                if [[ "${words[i]}" == "upgrade" ]]; then
                    template_sub="upgrade"
                    break
                fi
            done
            if [[ "$template_sub" == "upgrade" ]]; then
                # Complete with template names or flags
                local templates templates_dir
                templates_dir="${HOME}/.config/containai/templates"
                if [[ -d "$templates_dir" ]]; then
                    templates=$(find "$templates_dir" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; 2>/dev/null | tr '\n' ' ') || templates=""
                else
                    templates=""
                fi
                COMPREPLY=($(compgen -W "$templates $template_flags" -- "$cur"))
            else
                COMPREPLY=($(compgen -W "$template_subcommands -h --help" -- "$cur"))
            fi
            ;;
        update)
            COMPREPLY=($(compgen -W "$update_flags" -- "$cur"))
            ;;
        refresh)
            COMPREPLY=($(compgen -W "$refresh_flags" -- "$cur"))
            ;;
        uninstall)
            COMPREPLY=($(compgen -W "$uninstall_flags" -- "$cur"))
            ;;
        completion)
            COMPREPLY=($(compgen -W "$completion_shells" -- "$cur"))
            ;;
        help|version)
            # No further completion
            ;;
        *)
            COMPREPLY=($(compgen -W "$subcommands" -- "$cur"))
            ;;
    esac
}

# Register completion for both cai and containai
complete -F _cai_completions cai
complete -F _cai_completions containai
BASH_COMPLETION
}

# Output zsh completion script
_cai_completion_zsh() {
    cat <<'ZSH_COMPLETION'
#compdef cai containai
# ContainAI zsh completion
# Generated by: cai completion zsh

# Cache for dynamic completions
typeset -g _cai_completion_cache_containers=""
typeset -g _cai_completion_cache_volumes=""
typeset -g _cai_completion_cache_time=0
typeset -g _cai_completion_cache_ttl=5

# Portable sub-second timeout helper
# Returns 1 (no output) if no timeout command available - avoids hangs
_cai_completion_timeout() {
    local timeout_sec="$1"
    shift
    if (( $+commands[timeout] )); then
        timeout "$timeout_sec" "$@"
    elif (( $+commands[gtimeout] )); then
        gtimeout "$timeout_sec" "$@"
    else
        # No timeout available - skip command to avoid potential hangs
        return 1
    fi
}

_cai_get_containers() {
    local now=$(date +%s)
    if (( now - _cai_completion_cache_time < _cai_completion_cache_ttl )) && [[ -n "$_cai_completion_cache_containers" ]]; then
        echo "$_cai_completion_cache_containers"
        return
    fi

    # Use underscore-prefixed vars matching CLI, clear DOCKER_HOST/DOCKER_CONTEXT for safety
    local docker_socket="${_CAI_CONTAINAI_DOCKER_SOCKET:-/var/run/containai-docker.sock}"
    local docker_context="${_CAI_CONTAINAI_DOCKER_CONTEXT:-containai-docker}"
    if [[ -S "$docker_socket" ]]; then
        _cai_completion_cache_containers=$(DOCKER_HOST= DOCKER_CONTEXT= _cai_completion_timeout 0.5 docker --context "$docker_context" ps -a --filter "label=containai.managed=true" --format '{{.Names}}' 2>/dev/null | tr '\n' ' ')
        _cai_completion_cache_time=$now
    fi
    echo "$_cai_completion_cache_containers"
}

_cai_get_volumes() {
    local now=$(date +%s)
    if (( now - _cai_completion_cache_time < _cai_completion_cache_ttl )) && [[ -n "$_cai_completion_cache_volumes" ]]; then
        echo "$_cai_completion_cache_volumes"
        return
    fi

    # Use underscore-prefixed vars matching CLI, clear DOCKER_HOST/DOCKER_CONTEXT for safety
    local docker_socket="${_CAI_CONTAINAI_DOCKER_SOCKET:-/var/run/containai-docker.sock}"
    local docker_context="${_CAI_CONTAINAI_DOCKER_CONTEXT:-containai-docker}"
    if [[ -S "$docker_socket" ]]; then
        _cai_completion_cache_volumes=$(DOCKER_HOST= DOCKER_CONTEXT= _cai_completion_timeout 0.5 docker --context "$docker_context" volume ls --filter "label=containai.managed=true" --format '{{.Name}}' 2>/dev/null | tr '\n' ' ')
        _cai_completion_cache_time=$now
    fi
    echo "$_cai_completion_cache_volumes"
}

_cai_get_templates() {
    local templates_dir="${HOME}/.config/containai/templates"
    if [[ -d "$templates_dir" ]]; then
        find "$templates_dir" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; 2>/dev/null | tr '\n' ' '
    fi
}

_cai() {
    local curcontext="$curcontext" state line
    typeset -A opt_args

    local -a subcommands
    subcommands=(
        'run:Start/attach to sandbox container'
        'shell:Open interactive shell in container'
        'exec:Run a command in container'
        'doctor:Check system capabilities'
        'setup:Configure secure container isolation'
        'validate:Validate Secure Engine configuration'
        'docker:Run docker with ContainAI context'
        'import:Sync host configs to data volume'
        'export:Export data volume to archive'
        'sync:Move local configs to data volume with symlinks'
        'stop:Stop ContainAI containers'
        'status:Show container status and resource usage'
        'gc:Garbage collection for stale containers and images'
        'ssh:Manage SSH configuration'
        'links:Verify and repair symlinks'
        'config:Manage settings'
        'update:Update ContainAI installation'
        'refresh:Pull latest base image and optionally rebuild template'
        'uninstall:Remove ContainAI'
        'completion:Generate shell completion'
        'help:Show help message'
        'version:Show version'
    )

    _arguments -C \
        '(-h --help)'{-h,--help}'[Show help]' \
        '--refresh[Pull latest base image (alias for refresh subcommand)]' \
        '1: :->command' \
        '*:: :->args'

    case $state in
        command)
            _describe -t commands 'cai command' subcommands
            ;;
        args)
            # After _arguments -C with '*:: :->args', $line[1] contains the subcommand
            # Handle --refresh as alias for refresh
            local effective_subcmd="$line[1]"
            if [[ "$effective_subcmd" == "--refresh" ]]; then
                effective_subcmd="refresh"
            fi
            case $effective_subcmd in
                run)
                    _arguments \
                        '--data-volume[Data volume name]:volume:->volumes' \
                        '--config[Config file path]:file:_files' \
                        '(-w --workspace)'{-w,--workspace}'[Workspace path]:directory:_files -/' \
                        '--container[Container name]:container:->containers' \
                        '--template[Template name]:template:->templates' \
                        '--image-tag[Image tag]:tag:' \
                        '--memory[Memory limit]:size:' \
                        '--cpus[CPU limit]:count:' \
                        '--credentials[Credentials mode]:mode:(none)' \
                        '--acknowledge-credential-risk[Acknowledge credential risk]' \
                        '--fresh[Remove and recreate container]' \
                        '--restart[Force recreate container]' \
                        '--reset[Reset workspace state]' \
                        '--force[Skip isolation checks]' \
                        '(-d --detached)'{-d,--detached}'[Run in background]' \
                        '(-q --quiet)'{-q,--quiet}'[Suppress output]' \
                        '--verbose[Verbose output]' \
                        '(-D --debug)'{-D,--debug}'[Debug mode]' \
                        '--dry-run[Show what would happen]' \
                        '--mount-docker-socket[Mount Docker socket]' \
                        '--please-root-my-host[Dangerous: allow host root access]' \
                        '--allow-host-credentials[Allow host credentials]' \
                        '--i-understand-this-exposes-host-credentials[Acknowledge credential exposure]' \
                        '--allow-host-docker-socket[Allow host Docker socket]' \
                        '--i-understand-this-grants-root-access[Acknowledge root access]' \
                        '*'{-e,--env}'[Set environment variable]:var=value:' \
                        '(-h --help)'{-h,--help}'[Show help]'
                    ;;
                shell)
                    _arguments \
                        '--data-volume[Data volume name]:volume:->volumes' \
                        '--config[Config file path]:file:_files' \
                        '--workspace[Workspace path]:directory:_files -/' \
                        '--container[Container name]:container:->containers' \
                        '--template[Template name]:template:->templates' \
                        '--image-tag[Image tag]:tag:' \
                        '--memory[Memory limit]:size:' \
                        '--cpus[CPU limit]:count:' \
                        '--fresh[Remove and recreate container]' \
                        '--restart[Force recreate container]' \
                        '--reset[Reset workspace state]' \
                        '--force[Skip isolation checks]' \
                        '--dry-run[Show what would happen]' \
                        '(-q --quiet)'{-q,--quiet}'[Suppress output]' \
                        '--verbose[Verbose output]' \
                        '(-D --debug)'{-D,--debug}'[Debug mode]' \
                        '(-h --help)'{-h,--help}'[Show help]'
                    ;;
                exec)
                    _arguments \
                        '(-w --workspace)'{-w,--workspace}'[Workspace path]:directory:_files -/' \
                        '--container[Container name]:container:->containers' \
                        '--template[Template name]:template:->templates' \
                        '--data-volume[Data volume name]:volume:->volumes' \
                        '--config[Config file path]:file:_files' \
                        '--fresh[Remove and recreate container]' \
                        '--force[Skip isolation checks]' \
                        '(-q --quiet)'{-q,--quiet}'[Suppress output]' \
                        '--verbose[Verbose output]' \
                        '(-D --debug)'{-D,--debug}'[Debug mode]' \
                        '(-h --help)'{-h,--help}'[Show help]' \
                        '*:command:_command_names -e'
                    ;;
                doctor)
                    _arguments -C \
                        '--json[JSON output]' \
                        '--build-templates[Run heavy template validation]' \
                        '--reset-lima[Reset Lima VM (macOS)]' \
                        '(-w --workspace)'{-w,--workspace}'[Workspace path]:directory:_files -/' \
                        '(-h --help)'{-h,--help}'[Show help]' \
                        '1: :->doctor_sub' \
                        '*:: :->doctor_args'
                    case $state in
                        doctor_sub)
                            _alternative \
                                'commands:doctor command:(fix)'
                            ;;
                        doctor_args)
                            _arguments \
                                '1:target:(volume container template)' \
                                '--all[Fix all]' \
                                '*:name:'
                            ;;
                    esac
                    ;;
                setup)
                    _arguments \
                        '--dry-run[Show what would happen]' \
                        '--verbose[Verbose output]' \
                        '(-h --help)'{-h,--help}'[Show help]'
                    ;;
                validate)
                    _arguments \
                        '--verbose[Verbose output]' \
                        '--config[Config file path]:file:_files' \
                        '--workspace[Workspace path]:directory:_files -/' \
                        '(-h --help)'{-h,--help}'[Show help]'
                    ;;
                docker)
                    # Delegate to docker completion with containai-docker context
                    # Use __completeNoDesc to get plain completion words without tab-separated descriptions
                    # Set context via DOCKER_CONTEXT env var for Cobra compatibility
                    local docker_context="${_CAI_CONTAINAI_DOCKER_CONTEXT:-containai-docker}"

                    # Build words array for docker (everything after 'docker')
                    local -a docker_words
                    docker_words=("${words[@]:2}")

                    # Try docker __completeNoDesc for Cobra-style completion
                    # Use timeout to avoid hanging if containai-docker context is slow/unreachable
                    # Clear DOCKER_HOST to ensure DOCKER_CONTEXT takes effect
                    if (( $+commands[docker] )); then
                        local docker_out
                        docker_out=$(DOCKER_HOST= DOCKER_CONTEXT="$docker_context" _cai_completion_timeout 0.5 docker __completeNoDesc "${docker_words[@]}" 2>/dev/null)
                        if [[ -n "$docker_out" ]]; then
                            # Docker __completeNoDesc outputs completions one per line, with directive as last line
                            # Filter out directive line (starts with :) and empty lines
                            local -a completions
                            completions=("${(@f)$(printf '%s\n' "$docker_out" | grep -v '^:' | grep -v '^$')}")
                            if (( ${#completions[@]} > 0 )); then
                                compadd -a completions
                                return
                            fi
                        fi

                        docker_out=$(DOCKER_HOST= DOCKER_CONTEXT="$docker_context" _cai_completion_timeout 0.5 docker __complete "${docker_words[@]}" 2>/dev/null)
                        if [[ -n "$docker_out" ]]; then
                            # Convert tab-separated name/description to name:description for _describe
                            local -a completions
                            completions=("${(@f)$(printf '%s\n' "$docker_out" | grep -v '^:' | grep -v '^$' | awk -F '\t' '{print ($2 ? $1 ":" $2 : $1)}')}")
                            if (( ${#completions[@]} > 0 )); then
                                _describe -t docker-commands 'docker command' completions
                                return
                            fi
                        fi
                    fi

                    # Fallback: basic docker subcommands
                    local -a docker_subcommands
                    docker_subcommands=(
                        'attach:Attach to a running container'
                        'build:Build an image from a Dockerfile'
                        'commit:Create a new image from container changes'
                        'container:Manage containers'
                        'cp:Copy files between container and host'
                        'create:Create a new container'
                        'diff:Inspect changes to files or directories'
                        'events:Get real time events from the server'
                        'exec:Run a command in a running container'
                        'export:Export container filesystem as tar'
                        'history:Show the history of an image'
                        'image:Manage images'
                        'images:List images'
                        'import:Import contents from a tarball'
                        'info:Display system-wide information'
                        'inspect:Return low-level information'
                        'kill:Kill running containers'
                        'load:Load an image from a tar archive'
                        'login:Log in to a registry'
                        'logout:Log out from a registry'
                        'logs:Fetch container logs'
                        'network:Manage networks'
                        'pause:Pause all processes in containers'
                        'port:List port mappings'
                        'ps:List containers'
                        'pull:Pull an image from a registry'
                        'push:Push an image to a registry'
                        'rename:Rename a container'
                        'restart:Restart containers'
                        'rm:Remove containers'
                        'rmi:Remove images'
                        'run:Run a command in a new container'
                        'save:Save images to a tar archive'
                        'search:Search Docker Hub for images'
                        'start:Start stopped containers'
                        'stats:Display container resource usage'
                        'stop:Stop running containers'
                        'tag:Create a tag for an image'
                        'top:Display running processes'
                        'unpause:Unpause paused containers'
                        'update:Update container configuration'
                        'version:Show Docker version info'
                        'volume:Manage volumes'
                        'wait:Wait for container to stop'
                    )
                    _describe -t docker-commands 'docker command' docker_subcommands
                    ;;
                import)
                    _arguments \
                        '--dry-run[Show what would happen]' \
                        '--no-excludes[Skip exclude patterns]' \
                        '--no-secrets[Skip secrets sync]' \
                        '--verbose[Verbose output]' \
                        '--container[Container name]:container:->containers' \
                        '--data-volume[Data volume name]:volume:->volumes' \
                        '--config[Config file path]:file:_files' \
                        '--workspace[Workspace path]:directory:_files -/' \
                        '--from[Import from source]:source:' \
                        '(-h --help)'{-h,--help}'[Show help]'
                    ;;
                export)
                    _arguments \
                        '(-o --output)'{-o,--output}'[Output path]:file:_files' \
                        '--container[Container name]:container:->containers' \
                        '--data-volume[Data volume name]:volume:->volumes' \
                        '--config[Config file path]:file:_files' \
                        '--workspace[Workspace path]:directory:_files -/' \
                        '--no-excludes[Skip exclude patterns]' \
                        '--verbose[Verbose output]' \
                        '(-h --help)'{-h,--help}'[Show help]'
                    ;;
                sync)
                    _arguments \
                        '--dry-run[Show what would happen]' \
                        '--verbose[Verbose output]' \
                        '(-h --help)'{-h,--help}'[Show help]'
                    ;;
                stop)
                    _arguments \
                        '--container[Container name]:container:->containers' \
                        '--all[Stop all containers]' \
                        '--remove[Remove containers]' \
                        '--force[Skip session warning prompt]' \
                        '--export[Export data volume before stopping]' \
                        '--verbose[Verbose output]' \
                        '(-h --help)'{-h,--help}'[Show help]'
                    ;;
                status)
                    _arguments \
                        '--json[Output in JSON format]' \
                        '--workspace[Workspace path]:directory:_files -/' \
                        '--container[Container name]:container:->containers' \
                        '--verbose[Verbose output]' \
                        '(-h --help)'{-h,--help}'[Show help]'
                    ;;
                gc)
                    _arguments \
                        '--dry-run[Preview without removing]' \
                        '--force[Skip confirmation prompt]' \
                        '--age[Minimum age for pruning]:duration:' \
                        '--images[Also prune unused images]' \
                        '--verbose[Verbose output]' \
                        '(-h --help)'{-h,--help}'[Show help]'
                    ;;
                ssh)
                    _arguments -C \
                        '(-h --help)'{-h,--help}'[Show help]' \
                        '1: :->ssh_sub' \
                        '*:: :->ssh_args'
                    case $state in
                        ssh_sub)
                            _alternative \
                                'commands:ssh command:(cleanup)'
                            ;;
                        ssh_args)
                            _arguments \
                                '--dry-run[Show what would be cleaned]' \
                                '--verbose[Verbose output]' \
                                '(-h --help)'{-h,--help}'[Show help]'
                            ;;
                    esac
                    ;;
                links)
                    _arguments -C \
                        '(-h --help)'{-h,--help}'[Show help]' \
                        '1: :->links_sub' \
                        '*:: :->links_args'
                    case $state in
                        links_sub)
                            _alternative \
                                'commands:links command:(check fix)'
                            ;;
                        links_args)
                            _arguments \
                                '--workspace[Workspace path]:directory:_files -/' \
                                '--name[Container name]:name:' \
                                '--config[Config file path]:file:_files' \
                                '(-q --quiet)'{-q,--quiet}'[Suppress output]' \
                                '--verbose[Verbose output]' \
                                '--dry-run[Show what would be fixed]' \
                                '(-h --help)'{-h,--help}'[Show help]'
                            ;;
                    esac
                    ;;
                config)
                    _arguments -C \
                        '(-h --help)'{-h,--help}'[Show help]' \
                        '1: :->config_sub' \
                        '*:: :->config_args'
                    case $state in
                        config_sub)
                            _alternative \
                                'commands:config command:(list get set unset)'
                            ;;
                        config_args)
                            _arguments \
                                '(-g --global)'{-g,--global}'[Force global scope]' \
                                '--workspace[Workspace path]:directory:_files -/' \
                                '--verbose[Verbose output]' \
                                '(-h --help)'{-h,--help}'[Show help]' \
                                '*:key:'
                            ;;
                    esac
                    ;;
                update)
                    _arguments \
                        '--dry-run[Show what would happen]' \
                        '--stop-containers[Stop containers before update]' \
                        '--force[Skip confirmation prompts]' \
                        '--lima-recreate[Force Lima VM recreation]' \
                        '--verbose[Verbose output]' \
                        '(-h --help)'{-h,--help}'[Show help]'
                    ;;
                refresh)
                    _arguments \
                        '--rebuild[Rebuild default template after pulling]' \
                        '--verbose[Verbose output]' \
                        '(-h --help)'{-h,--help}'[Show help]'
                    ;;
                uninstall)
                    _arguments \
                        '--dry-run[Show what would happen]' \
                        '--containers[Remove containers]' \
                        '--volumes[Remove volumes]' \
                        '--force[Skip confirmation prompts]' \
                        '--verbose[Verbose output]' \
                        '(-h --help)'{-h,--help}'[Show help]'
                    ;;
                completion)
                    _arguments \
                        '1:shell:(bash zsh)'
                    ;;
            esac

            # Handle dynamic completions for --container and --data-volume only
            # Use space split ${(s: :)} since _cai_get_* returns space-separated values
            case $state in
                containers)
                    local -a containers
                    containers=(${(s: :)"$(_cai_get_containers)"})
                    _describe -t containers 'container' containers
                    ;;
                volumes)
                    local -a volumes
                    volumes=(${(s: :)"$(_cai_get_volumes)"})
                    _describe -t volumes 'volume' volumes
                    ;;
                templates)
                    local -a templates
                    templates=(${(s: :)"$(_cai_get_templates)"})
                    _describe -t templates 'template' templates
                    ;;
            esac
            ;;
    esac
}

# Register completion for both cai and containai
compdef _cai cai containai
ZSH_COMPLETION
}

# Completion command handler
_containai_completion_cmd() {
    local shell_type="${1:-}"

    case "$shell_type" in
        bash)
            _cai_completion_bash
            ;;
        zsh)
            _cai_completion_zsh
            ;;
        -h|--help|"")
            _containai_completion_help
            ;;
        *)
            echo "[ERROR] Unknown shell: $shell_type" >&2
            echo "Supported shells: bash, zsh" >&2
            return 1
            ;;
    esac
}

# ==============================================================================
# Main CLI function
# ==============================================================================

containai() {
    local subcommand="${1:-}"

    # CRITICAL: acp subcommand must be detected BEFORE update checks to avoid stdout pollution
    # ACP protocol requires stdout purity - no diagnostic output allowed
    if [[ "${subcommand:-}" == "acp" ]]; then
        shift
        _containai_acp_cmd "$@"
        return $?
    fi

    # Legacy --acp support (deprecated, use 'cai acp proxy <agent>')
    if [[ "${subcommand:-}" == "--acp" ]]; then
        shift
        _containai_acp_proxy "$@"
        return $?
    fi

    # Reset verbose/quiet state at start of each invocation
    # This prevents state leaking between commands in sourced/dev mode
    _CAI_VERBOSE=""
    _CAI_QUIET=""

    # Reset channel override to prevent leaking between invocations
    _CAI_CHANNEL_OVERRIDE=""

    # Run rate-limited update check before command dispatch
    # Skip in CI environments to avoid noise/delays in automated pipelines
    # Per spec: CI=true (explicit), GITHUB_ACTIONS (presence), JENKINS_URL (presence)
    # Skip for help/version/completion/refresh to avoid latency on informational commands
    # Skip for --refresh since it's doing an explicit update action
    if [[ "${CI:-}" != "true" ]] && [[ -z "${GITHUB_ACTIONS:-}" ]] && [[ -z "${JENKINS_URL:-}" ]]; then
        case "$subcommand" in
            help|-h|--help|version|--version|-v|completion|refresh|--refresh) ;;
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
        exec)
            shift
            _containai_exec_cmd "$@"
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
        sync)
            shift
            _cai_sync_cmd "$@"
            ;;
        stop)
            shift
            _containai_stop_cmd "$@"
            ;;
        status)
            shift
            _containai_status_cmd "$@"
            ;;
        gc)
            shift
            _containai_gc_cmd "$@"
            ;;
        ssh)
            shift
            _containai_ssh_cmd "$@"
            ;;
        links)
            shift
            _containai_links_cmd "$@"
            ;;
        config)
            shift
            _containai_config_cmd "$@"
            ;;
        template)
            shift
            _containai_template_cmd "$@"
            ;;
        sandbox)
            shift
            _containai_sandbox_cmd "$@"
            ;;
        update)
            shift
            _cai_update "$@"
            ;;
        refresh)
            shift
            _cai_refresh "$@"
            ;;
        --refresh)
            shift
            _cai_refresh "$@"
            ;;
        uninstall)
            shift
            _cai_uninstall "$@"
            ;;
        completion)
            shift
            _containai_completion_cmd "$@"
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
