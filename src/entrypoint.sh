#!/usr/bin/env bash
set -euo pipefail


# Canonical location
AGENT_WORKSPACE="${HOME}/workspace"

log() { printf '%s\n' "$*" >&2; }

# Helper: run command as root (using sudo -n for non-interactive fail-fast)
run_as_root() {
  if [[ $(id -u) -eq 0 ]]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo -n "$@" || {
      log "ERROR: sudo -n failed. Ensure agent user has passwordless sudo or run as root."
      return 1
    }
  else
    log "ERROR: Not root and sudo not available."
    return 1
  fi
}

# Data directory constant for path validation
readonly DATA_DIR="/mnt/agent-data"

# Helper: verify path resolves under DATA_DIR (prevents symlink traversal)
verify_path_under_data_dir() {
  local path="$1"
  local resolved

  # Use realpath -m to resolve the path even if it doesn't exist yet
  # This handles symlinks in any path component, not just the final one
  resolved="$(realpath -m "$path" 2>/dev/null)" || {
    log "ERROR: Cannot resolve path: $path"
    return 1
  }

  # Verify resolved path is exactly DATA_DIR or starts with DATA_DIR/
  # This prevents /mnt/agent-datax from passing the check
  if [[ "$resolved" != "${DATA_DIR}" && "$resolved" != "${DATA_DIR}/"* ]]; then
    log "ERROR: Path escapes data directory: $path -> $resolved"
    return 1
  fi
  return 0
}

# Helper: reject symlinks at any path (for security-sensitive operations)
reject_symlink() {
  local path="$1"
  if [[ -L "$path" ]]; then
    log "ERROR: Symlink detected where regular file/dir expected: $path"
    return 1
  fi
  return 0
}

# Helper: ensure a directory exists with type and symlink validation
ensure_dir() {
  local path="$1"

  # Reject symlinks
  reject_symlink "$path" || return 1

  # Verify path stays under data directory
  verify_path_under_data_dir "$path" || return 1

  if [[ -e "$path" && ! -d "$path" ]]; then
    log "ERROR: Expected directory but found file: $path"
    return 1
  fi
  mkdir -p "$path"
}

# Helper: ensure a file exists with type and symlink validation, optionally init JSON
ensure_file() {
  local path="$1"
  local init_json="${2:-false}"

  # Reject symlinks
  reject_symlink "$path" || return 1

  # Verify path stays under data directory
  verify_path_under_data_dir "$path" || return 1

  # Ensure parent directory exists
  local parent
  parent="$(dirname "$path")"
  ensure_dir "$parent" || return 1

  if [[ -e "$path" && ! -f "$path" ]]; then
    log "ERROR: Expected file but found directory: $path"
    return 1
  fi

  if [[ "$init_json" == "true" ]]; then
    # Initialize with {} if file is missing or empty
    [[ -s "$path" ]] || echo '{}' > "$path"
  else
    touch "$path"
  fi
}

# Helper: apply chmod with symlink and path validation
safe_chmod() {
  local mode="$1"
  local path="$2"

  # Reject symlinks before chmod
  reject_symlink "$path" || return 1

  # Verify path stays under data directory
  verify_path_under_data_dir "$path" || return 1

  chmod "$mode" "$path"
}

# Ensure all volume structure exists for symlinks to work.
# Derived from _IMPORT_SYNC_MAP targets in lib/import.sh plus additional
# Dockerfile symlink targets (e.g., vscode-server settings.json, mcp.json)
ensure_volume_structure() {
  # Bootstrap: ensure volume root is writable by agent user (1000:1000)
  # On a fresh Docker volume, /mnt/agent-data is root:root, so we need sudo first
  run_as_root mkdir -p "${DATA_DIR}"
  run_as_root chown -R --no-dereference 1000:1000 "${DATA_DIR}"

  # Claude Code (SYNC_MAP flags: fjs for claude.json, fs for credentials, fj for settings)
  # Note: credentials.json gets JSON init even though SYNC_MAP has 'fs' not 'fjs'
  # because Claude CLI requires valid JSON (empty file causes parse errors)
  ensure_dir "${DATA_DIR}/claude"
  ensure_file "${DATA_DIR}/claude/claude.json" true
  ensure_file "${DATA_DIR}/claude/credentials.json" true
  ensure_file "${DATA_DIR}/claude/settings.json" true
  ensure_file "${DATA_DIR}/claude/settings.local.json"
  ensure_dir "${DATA_DIR}/claude/plugins"
  ensure_dir "${DATA_DIR}/claude/skills"

  # GitHub CLI (SYNC_MAP flags: ds - secret directory)
  ensure_dir "${DATA_DIR}/config/gh"

  # OpenCode config (SYNC_MAP flags: d)
  ensure_dir "${DATA_DIR}/config/opencode"

  # tmux (SYNC_MAP uses XDG paths: config/tmux, local/share/tmux)
  ensure_dir "${DATA_DIR}/config/tmux"
  ensure_dir "${DATA_DIR}/local/share/tmux"

  # Shell (SYNC_MAP flags: f for .bash_aliases, d for .bashrc.d)
  ensure_dir "${DATA_DIR}/shell"
  ensure_file "${DATA_DIR}/shell/.bash_aliases"
  ensure_dir "${DATA_DIR}/shell/.bashrc.d"

  # VS Code Server (SYNC_MAP flags: d for dirs, Dockerfile symlinks need JSON init)
  ensure_dir "${DATA_DIR}/vscode-server/extensions"
  ensure_dir "${DATA_DIR}/vscode-server/data/Machine"
  ensure_dir "${DATA_DIR}/vscode-server/data/User/mcp"
  ensure_dir "${DATA_DIR}/vscode-server/data/User/prompts"
  ensure_file "${DATA_DIR}/vscode-server/data/Machine/settings.json" true
  ensure_file "${DATA_DIR}/vscode-server/data/User/mcp.json" true

  # VS Code Insiders (same structure as VS Code Server)
  ensure_dir "${DATA_DIR}/vscode-server-insiders/extensions"
  ensure_dir "${DATA_DIR}/vscode-server-insiders/data/Machine"
  ensure_dir "${DATA_DIR}/vscode-server-insiders/data/User/mcp"
  ensure_dir "${DATA_DIR}/vscode-server-insiders/data/User/prompts"
  ensure_file "${DATA_DIR}/vscode-server-insiders/data/Machine/settings.json" true
  ensure_file "${DATA_DIR}/vscode-server-insiders/data/User/mcp.json" true

  # Copilot (SYNC_MAP flags: f for config.json/mcp-config.json, d for skills - NO json init)
  ensure_dir "${DATA_DIR}/copilot/skills"
  ensure_file "${DATA_DIR}/copilot/config.json"
  ensure_file "${DATA_DIR}/copilot/mcp-config.json"

  # Gemini (SYNC_MAP flags: fs for oauth files, f for GEMINI.md, Dockerfile symlink for settings)
  ensure_dir "${DATA_DIR}/gemini"
  ensure_file "${DATA_DIR}/gemini/google_accounts.json"
  ensure_file "${DATA_DIR}/gemini/oauth_creds.json"
  ensure_file "${DATA_DIR}/gemini/GEMINI.md"
  ensure_file "${DATA_DIR}/gemini/settings.json" true

  # Codex (SYNC_MAP flags: f for config.toml, fs for auth.json, dx for skills)
  ensure_dir "${DATA_DIR}/codex/skills"
  ensure_file "${DATA_DIR}/codex/config.toml"
  ensure_file "${DATA_DIR}/codex/auth.json"

  # OpenCode auth (SYNC_MAP flags: fs - secret file)
  ensure_dir "${DATA_DIR}/local/share/opencode"
  ensure_file "${DATA_DIR}/local/share/opencode/auth.json"

  # Apply secret permissions (after all files created, before final ownership fix)
  # Secret files: chmod 600 (SYNC_MAP 's' flag on files)
  safe_chmod 600 "${DATA_DIR}/claude/claude.json"
  safe_chmod 600 "${DATA_DIR}/claude/credentials.json"
  safe_chmod 600 "${DATA_DIR}/gemini/google_accounts.json"
  safe_chmod 600 "${DATA_DIR}/gemini/oauth_creds.json"
  safe_chmod 600 "${DATA_DIR}/codex/auth.json"
  safe_chmod 600 "${DATA_DIR}/local/share/opencode/auth.json"

  # Secret dirs: chmod 700 (SYNC_MAP 's' flag on directories)
  safe_chmod 700 "${DATA_DIR}/config/gh"

  # Final ownership fix (use sudo since entrypoint runs as non-root USER agent)
  # Use --no-dereference to prevent symlink traversal attacks
  run_as_root chown -R --no-dereference 1000:1000 "${DATA_DIR}"
}

# Load environment variables from .env file safely (no shell source/eval)
# Called AFTER ownership fix to ensure volume is readable
_load_env_file() {
  local env_file="${DATA_DIR}/.env"

  # Guard against set -e - use if/else, not raw test
  # Check symlink FIRST (before -f) to properly reject symlinks to non-files
  if [[ -L "$env_file" ]]; then
    log "[WARN] .env is symlink - skipping"
    return 0
  fi
  if [[ ! -f "$env_file" ]]; then
    return 0  # Silent - expected for first run
  fi
  if [[ ! -r "$env_file" ]]; then
    log "[WARN] .env unreadable - skipping"
    return 0
  fi

  log "[INFO] Loading environment from .env"
  local line_num=0
  local line key value
  while IFS= read -r line || [[ -n "$line" ]]; do
    # set -e safe increment (NOT ((line_num++)) which fails on 0)
    line_num=$((line_num + 1))
    # Strip CRLF
    line="${line%$'\r'}"
    # Skip comments (allows leading whitespace before #)
    if [[ "$line" =~ ^[[:space:]]*# ]]; then continue; fi
    # Skip blank/whitespace-only lines (spaces and tabs)
    if [[ -z "${line//[[:space:]]/}" ]]; then continue; fi
    # Strip optional 'export ' prefix (must be at line start, no leading whitespace)
    if [[ "$line" =~ ^export[[:space:]]+ ]]; then
      line="${line#export}"
      line="${line#"${line%%[![:space:]]*}"}"  # trim leading whitespace after export
    fi
    # Require = before parsing
    if [[ "$line" != *=* ]]; then
      # Extract key token only (first word, no value content) for log hygiene
      # Trim leading whitespace, then take up to first whitespace
      local key_token="${line#"${line%%[![:space:]]*}"}"
      key_token="${key_token%%[[:space:]]*}"
      [[ -z "$key_token" ]] && key_token="<unknown>"
      log "[WARN] line $line_num: no = found for '$key_token' - skipping"
      continue
    fi
    # Extract key and value (no whitespace trimming - strict format)
    key="${line%%=*}"
    value="${line#*=}"
    # Validate key
    if [[ ! "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
      log "[WARN] line $line_num: invalid key '$key' - skipping"
      continue
    fi
    # Only set if not present (empty string = present)
    if [[ -z "${!key+x}" ]]; then
      export "$key=$value" || { log "[WARN] line $line_num: export failed for '$key'"; continue; }
    fi
  done < "$env_file"
}

# Ensure volume structure exists
ensure_volume_structure

# Load .env after ownership fix completes (volume readable now)
_load_env_file

# Copy .gitconfig from data volume to $HOME if it exists
# This enables git commits inside the container with the user's identity
# and sets safe.directory for the workspace mount
_setup_git_config() {
  local src="${DATA_DIR}/.gitconfig"
  local dst="${HOME}/.gitconfig"

  # Check source: symlink FIRST (before -f) to properly reject symlinks
  if [[ -L "$src" ]]; then
    log "[WARN] Source .gitconfig is symlink - skipping"
    return 0
  fi
  if [[ ! -f "$src" ]]; then
    return 0  # Silent - expected if cai import wasn't run with git config
  fi
  if [[ ! -r "$src" ]]; then
    log "[WARN] Source .gitconfig unreadable - skipping"
    return 0
  fi

  # Check destination: refuse if symlink or non-regular file exists
  if [[ -L "$dst" ]]; then
    log "[WARN] Destination $dst is symlink - refusing to overwrite"
    return 0
  fi
  if [[ -e "$dst" && ! -f "$dst" ]]; then
    log "[WARN] Destination $dst exists but is not a regular file - skipping"
    return 0
  fi

  # Copy to $HOME using temp file + atomic mv to avoid partial writes
  local tmp_dst="${dst}.tmp.$$"
  if cp "$src" "$tmp_dst" 2>/dev/null && mv "$tmp_dst" "$dst" 2>/dev/null; then
    log "[INFO] Git config loaded from data volume"
  else
    rm -f "$tmp_dst" 2>/dev/null || true
    log "[WARN] Failed to copy .gitconfig to $HOME"
  fi
}

_setup_git_config

# Check if .claude.json exists and is 0 bytes
# Docker Sandbox creates the file when creating the container replacing a link
CLAUDE_JSON="${AGENT_WORKSPACE}/.claude.json"
if [[ -f "$CLAUDE_JSON" && ! -s "$CLAUDE_JSON" ]]; then
  echo "{}"> "$CLAUDE_JSON" # Claude complains if there's an empty file and if it creates it it breaks the symlink
fi

# Setup workspace symlink from original host path to mount point.
# The container mounts workspace at /home/agent/workspace, and the original
# host path is passed via CAI_HOST_WORKSPACE environment variable.
# If host path differs from mount point, we create a symlink so tools
# expecting the original path can find the workspace.
#
# This approach:
# - Avoids docker inspect (would require Docker socket inside container)
# - Gracefully handles permission errors
# - Works with paths containing spaces
# - Is idempotent (safe to rerun)
setup_workspace_symlink() {
  local host_path="${CAI_HOST_WORKSPACE:-}"
  local mount_path="/home/agent/workspace"

  # No host path provided - nothing to do
  if [[ -z "$host_path" ]]; then
    return 0
  fi

  # Host path matches mount path - no symlink needed
  if [[ "$host_path" == "$mount_path" ]]; then
    return 0
  fi

  # Create parent directory for symlink (may need to exist)
  # Use run_as_root since host paths like /home/user/... require root inside container
  # Gracefully handle permission errors (|| true) in case sudo is unavailable
  run_as_root mkdir -p "$(dirname "$host_path")" 2>/dev/null || true

  # Create symlink from original path to mount point
  # Use ln -sfn:
  #   -s: create symbolic link
  #   -f: remove existing destination files
  #   -n: treat destination that is symlink to dir as if it were a normal file
  # Use run_as_root since host paths typically require elevated privileges
  # Gracefully handle permission errors (|| true) in case sudo is unavailable
  run_as_root ln -sfn "$mount_path" "$host_path" 2>/dev/null || true
}

main() {
  # Start dockerd for Docker-in-Docker capability
  sudo -n dockerd --iptables=false --ip6tables=false --ip-masq=false --bridge=none &

  # Setup workspace symlink if original host path differs from mount path
  # This allows tools expecting the original path (e.g., /home/user/project)
  # to find the workspace which is mounted at /home/agent/workspace
  setup_workspace_symlink

  # Verify workspace directory exists and is accessible
  if [[ ! -d "$AGENT_WORKSPACE" ]]; then
    log "ERROR: Workspace directory does not exist: $AGENT_WORKSPACE"
    exit 1
  fi

  cd -- "$AGENT_WORKSPACE"

  # Continue with the container's original command
  exec "$@"
}

main "$@"