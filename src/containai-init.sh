#!/usr/bin/env bash
# ContainAI initialization script for systemd containers
# Runs as a oneshot systemd service to prepare volume structure and workspace
set -euo pipefail

# Ensure HOME is set (systemd services may not have it even with User=)
: "${HOME:=/home/agent}"

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

  resolved="$(realpath -m "$path" 2>/dev/null)" || {
    log "ERROR: Cannot resolve path: $path"
    return 1
  }

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

  reject_symlink "$path" || return 1
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

  reject_symlink "$path" || return 1
  verify_path_under_data_dir "$path" || return 1

  local parent
  parent="$(dirname "$path")"
  ensure_dir "$parent" || return 1

  if [[ -e "$path" && ! -f "$path" ]]; then
    log "ERROR: Expected file but found directory: $path"
    return 1
  fi

  if [[ "$init_json" == "true" ]]; then
    [[ -s "$path" ]] || echo '{}' > "$path"
  else
    touch "$path"
  fi
}

# Helper: apply chmod with symlink and path validation
safe_chmod() {
  local mode="$1"
  local path="$2"

  reject_symlink "$path" || return 1
  verify_path_under_data_dir "$path" || return 1

  chmod "$mode" "$path"
}

# Ensure all volume structure exists for symlinks to work
ensure_volume_structure() {
  run_as_root mkdir -p "${DATA_DIR}"
  run_as_root chown -R --no-dereference 1000:1000 "${DATA_DIR}"

  # Claude Code
  ensure_dir "${DATA_DIR}/claude"
  ensure_file "${DATA_DIR}/claude/claude.json" true
  ensure_file "${DATA_DIR}/claude/credentials.json" true
  ensure_file "${DATA_DIR}/claude/settings.json" true
  ensure_file "${DATA_DIR}/claude/settings.local.json"
  ensure_dir "${DATA_DIR}/claude/plugins"
  ensure_dir "${DATA_DIR}/claude/skills"

  # GitHub CLI
  ensure_dir "${DATA_DIR}/config/gh"

  # OpenCode config
  ensure_dir "${DATA_DIR}/config/opencode"

  # tmux
  ensure_dir "${DATA_DIR}/config/tmux"
  ensure_dir "${DATA_DIR}/local/share/tmux"

  # Shell (paths match import.sh: shell/bash_aliases, shell/bashrc.d - no dots)
  ensure_dir "${DATA_DIR}/shell"
  ensure_file "${DATA_DIR}/shell/bash_aliases"
  ensure_dir "${DATA_DIR}/shell/bashrc.d"

  # VS Code Server
  ensure_dir "${DATA_DIR}/vscode-server/extensions"
  ensure_dir "${DATA_DIR}/vscode-server/data/Machine"
  ensure_dir "${DATA_DIR}/vscode-server/data/User/mcp"
  ensure_dir "${DATA_DIR}/vscode-server/data/User/prompts"
  ensure_file "${DATA_DIR}/vscode-server/data/Machine/settings.json" true
  ensure_file "${DATA_DIR}/vscode-server/data/User/mcp.json" true

  # VS Code Insiders
  ensure_dir "${DATA_DIR}/vscode-server-insiders/extensions"
  ensure_dir "${DATA_DIR}/vscode-server-insiders/data/Machine"
  ensure_dir "${DATA_DIR}/vscode-server-insiders/data/User/mcp"
  ensure_dir "${DATA_DIR}/vscode-server-insiders/data/User/prompts"
  ensure_file "${DATA_DIR}/vscode-server-insiders/data/Machine/settings.json" true
  ensure_file "${DATA_DIR}/vscode-server-insiders/data/User/mcp.json" true

  # Copilot
  ensure_dir "${DATA_DIR}/copilot/skills"
  ensure_file "${DATA_DIR}/copilot/config.json"
  ensure_file "${DATA_DIR}/copilot/mcp-config.json"

  # Gemini
  ensure_dir "${DATA_DIR}/gemini"
  ensure_file "${DATA_DIR}/gemini/google_accounts.json"
  ensure_file "${DATA_DIR}/gemini/oauth_creds.json"
  ensure_file "${DATA_DIR}/gemini/GEMINI.md"
  ensure_file "${DATA_DIR}/gemini/settings.json" true

  # Codex
  ensure_dir "${DATA_DIR}/codex/skills"
  ensure_file "${DATA_DIR}/codex/config.toml"
  ensure_file "${DATA_DIR}/codex/auth.json"

  # OpenCode auth
  ensure_dir "${DATA_DIR}/local/share/opencode"
  ensure_file "${DATA_DIR}/local/share/opencode/auth.json"

  # Secret permissions
  safe_chmod 600 "${DATA_DIR}/claude/claude.json"
  safe_chmod 600 "${DATA_DIR}/claude/credentials.json"
  safe_chmod 600 "${DATA_DIR}/gemini/google_accounts.json"
  safe_chmod 600 "${DATA_DIR}/gemini/oauth_creds.json"
  safe_chmod 600 "${DATA_DIR}/codex/auth.json"
  safe_chmod 600 "${DATA_DIR}/local/share/opencode/auth.json"
  safe_chmod 700 "${DATA_DIR}/config/gh"

  run_as_root chown -R --no-dereference 1000:1000 "${DATA_DIR}"
}

# Load environment variables from .env file safely
_load_env_file() {
  local env_file="${DATA_DIR}/.env"

  if [[ -L "$env_file" ]]; then
    log "[WARN] .env is symlink - skipping"
    return 0
  fi
  if [[ ! -f "$env_file" ]]; then
    return 0
  fi
  if [[ ! -r "$env_file" ]]; then
    log "[WARN] .env unreadable - skipping"
    return 0
  fi

  log "[INFO] Loading environment from .env"
  local line_num=0
  local line key value
  while IFS= read -r line || [[ -n "$line" ]]; do
    line_num=$((line_num + 1))
    line="${line%$'\r'}"
    if [[ "$line" =~ ^[[:space:]]*# ]]; then continue; fi
    if [[ -z "${line//[[:space:]]/}" ]]; then continue; fi
    if [[ "$line" =~ ^export[[:space:]]+ ]]; then
      line="${line#export}"
      line="${line#"${line%%[![:space:]]*}"}"
    fi
    if [[ "$line" != *=* ]]; then
      local key_token="${line#"${line%%[![:space:]]*}"}"
      key_token="${key_token%%[[:space:]]*}"
      [[ -z "$key_token" ]] && key_token="<unknown>"
      log "[WARN] line $line_num: no = found for '$key_token' - skipping"
      continue
    fi
    key="${line%%=*}"
    value="${line#*=}"
    if [[ ! "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
      log "[WARN] line $line_num: invalid key '$key' - skipping"
      continue
    fi
    if [[ -z "${!key+x}" ]]; then
      export "$key=$value" || { log "[WARN] line $line_num: export failed for '$key'"; continue; }
    fi
  done < "$env_file"
}

# Copy .gitconfig from data volume to $HOME if it exists
_setup_git_config() {
  local src="${DATA_DIR}/.gitconfig"
  local dst="${HOME}/.gitconfig"

  if [[ -L "$src" ]]; then
    log "[WARN] Source .gitconfig is symlink - skipping"
    return 0
  fi
  if [[ ! -f "$src" ]]; then
    return 0
  fi
  if [[ ! -r "$src" ]]; then
    log "[WARN] Source .gitconfig unreadable - skipping"
    return 0
  fi

  if [[ -L "$dst" ]]; then
    log "[WARN] Destination $dst is symlink - refusing to overwrite"
    return 0
  fi
  if [[ -e "$dst" && ! -f "$dst" ]]; then
    log "[WARN] Destination $dst exists but is not a regular file - skipping"
    return 0
  fi

  local tmp_dst="${dst}.tmp.$$"
  if cp "$src" "$tmp_dst" 2>/dev/null && mv "$tmp_dst" "$dst" 2>/dev/null; then
    log "[INFO] Git config loaded from data volume"
  else
    rm -f "$tmp_dst" 2>/dev/null || true
    log "[WARN] Failed to copy .gitconfig to $HOME"
  fi
}

# Setup workspace symlink from original host path to mount point
setup_workspace_symlink() {
  local host_path="${CAI_HOST_WORKSPACE:-}"
  local mount_path="/home/agent/workspace"

  if [[ -z "$host_path" ]]; then
    return 0
  fi

  if [[ "$host_path" == "$mount_path" ]]; then
    return 0
  fi

  run_as_root mkdir -p "$(dirname "$host_path")" 2>/dev/null || true
  run_as_root ln -sfn "$mount_path" "$host_path" 2>/dev/null || true
}

# Main initialization
main() {
  log "[INFO] ContainAI initialization starting..."

  ensure_volume_structure
  _load_env_file
  _setup_git_config
  setup_workspace_symlink

  log "[INFO] ContainAI initialization complete"
}

main "$@"
