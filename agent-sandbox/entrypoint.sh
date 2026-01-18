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

# Helper: reject symlinks in top-level tool directories to prevent traversal attacks
# Only checks immediate children of data_dir (e.g., claude, config, gemini)
reject_symlink_traversal() {
  local data_dir="$1"
  local subdir="$2"
  local target="${data_dir}/${subdir}"

  # If target exists and is a symlink, refuse to proceed
  if [[ -L "$target" ]]; then
    log "ERROR: Symlink traversal detected: $target is a symlink. Refusing to proceed."
    return 1
  fi
  return 0
}

# Helper: ensure a directory exists with type validation
ensure_dir() {
  local path="$1"
  if [[ -e "$path" && ! -d "$path" ]]; then
    log "ERROR: Expected directory but found file: $path"
    return 1
  fi
  mkdir -p "$path"
}

# Helper: ensure a file exists with type validation, optionally init JSON
ensure_file() {
  local path="$1"
  local init_json="${2:-false}"

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

# Ensure all volume structure exists for symlinks to work.
# Derived from SYNC_MAP targets in sync-agent-plugins.sh plus additional
# Dockerfile symlink targets (e.g., vscode-server settings.json, mcp.json)
ensure_volume_structure() {
  local data_dir="/mnt/agent-data"

  # Bootstrap: ensure volume root is writable by agent user (1000:1000)
  # On a fresh Docker volume, /mnt/agent-data is root:root, so we need sudo first
  run_as_root mkdir -p "${data_dir}"
  run_as_root chown -R --no-dereference 1000:1000 "${data_dir}"

  # Define top-level tool directories that we'll create
  # Reject any that are symlinks to prevent traversal attacks
  local tool_dirs=(
    "claude"
    "config"
    "copilot"
    "gemini"
    "codex"
    "local"
    "shell"
    "tmux"
    "vscode-server"
    "vscode-server-insiders"
  )

  for subdir in "${tool_dirs[@]}"; do
    reject_symlink_traversal "${data_dir}" "$subdir" || return 1
  done

  # Claude Code
  ensure_dir "${data_dir}/claude"
  ensure_file "${data_dir}/claude/claude.json" true
  ensure_file "${data_dir}/claude/credentials.json" true
  ensure_file "${data_dir}/claude/settings.json" true
  ensure_file "${data_dir}/claude/settings.local.json"
  ensure_dir "${data_dir}/claude/plugins"
  ensure_dir "${data_dir}/claude/skills"

  # GitHub CLI
  ensure_dir "${data_dir}/config/gh"

  # OpenCode (config via ~/.config symlink)
  ensure_dir "${data_dir}/config/opencode"

  # tmux
  ensure_dir "${data_dir}/tmux"
  ensure_file "${data_dir}/tmux/.tmux.conf"
  ensure_dir "${data_dir}/tmux/.tmux"
  ensure_dir "${data_dir}/config/tmux"

  # Shell
  ensure_dir "${data_dir}/shell"
  ensure_file "${data_dir}/shell/.bash_aliases"
  ensure_dir "${data_dir}/shell/.bashrc.d"

  # VS Code Server
  ensure_dir "${data_dir}/vscode-server/extensions"
  ensure_dir "${data_dir}/vscode-server/data/Machine"
  ensure_dir "${data_dir}/vscode-server/data/User/mcp"
  ensure_dir "${data_dir}/vscode-server/data/User/prompts"
  ensure_file "${data_dir}/vscode-server/data/Machine/settings.json" true
  ensure_file "${data_dir}/vscode-server/data/User/mcp.json" true

  # VS Code Insiders
  ensure_dir "${data_dir}/vscode-server-insiders/extensions"
  ensure_dir "${data_dir}/vscode-server-insiders/data/Machine"
  ensure_dir "${data_dir}/vscode-server-insiders/data/User/mcp"
  ensure_dir "${data_dir}/vscode-server-insiders/data/User/prompts"
  ensure_file "${data_dir}/vscode-server-insiders/data/Machine/settings.json" true
  ensure_file "${data_dir}/vscode-server-insiders/data/User/mcp.json" true

  # Copilot
  ensure_dir "${data_dir}/copilot/skills"
  ensure_file "${data_dir}/copilot/config.json" true
  ensure_file "${data_dir}/copilot/mcp-config.json" true

  # Gemini
  ensure_dir "${data_dir}/gemini"
  ensure_file "${data_dir}/gemini/google_accounts.json" true
  ensure_file "${data_dir}/gemini/oauth_creds.json" true
  ensure_file "${data_dir}/gemini/GEMINI.md"
  ensure_file "${data_dir}/gemini/settings.json" true

  # Codex
  ensure_dir "${data_dir}/codex/skills"
  ensure_file "${data_dir}/codex/config.toml"
  ensure_file "${data_dir}/codex/auth.json" true

  # OpenCode (auth from data dir)
  ensure_dir "${data_dir}/local/share/opencode"
  ensure_file "${data_dir}/local/share/opencode/auth.json" true

  # Apply secret permissions (after all files created, before final ownership fix)
  # Secret files: chmod 600
  chmod 600 "${data_dir}/claude/claude.json"
  chmod 600 "${data_dir}/claude/credentials.json"
  chmod 600 "${data_dir}/gemini/google_accounts.json"
  chmod 600 "${data_dir}/gemini/oauth_creds.json"
  chmod 600 "${data_dir}/codex/auth.json"
  chmod 600 "${data_dir}/local/share/opencode/auth.json"

  # Secret dirs: chmod 700
  chmod 700 "${data_dir}/config/gh"

  # Final ownership fix (use sudo since entrypoint runs as non-root USER agent)
  # Use --no-dereference to prevent symlink traversal attacks
  run_as_root chown -R --no-dereference 1000:1000 "${data_dir}"
}

# Ensure volume structure exists
ensure_volume_structure

# Check if .claude.json exists and is 0 bytes
# Docker Sandbox creates the file when creating the container replacing a link
CLAUDE_JSON="${AGENT_WORKSPACE}/.claude.json"
if [[ -f "$CLAUDE_JSON" && ! -s "$CLAUDE_JSON" ]]; then
  echo "{}"> "$CLAUDE_JSON" # Claude complains if there's an empty file and if it creates it it breaks the symlink
fi

# Discover the mirrored workspace mount.
# In Docker Sandbox, the workspace shows up in `findmnt --real` as:
#   TARGET=/some/abs/path
#   SOURCE=/dev/sdX[/some/abs/path]
discover_mirrored_workspace() {
  findmnt --real --json \
  | jq -r '
      # Flatten the tree: any object with target+source is a mount entry.
      def mounts:
        .. | objects | select(has("target") and has("source"))
        | {target: .target, source: .source};

      # Matching rule:
      # 1) source ends with [target]
      # 2) macOS Docker Desktop: source ends with [target without leading /Volumes]
      def is_match($t; $s):
        ($s | endswith("[" + $t + "]"))
        or (
          ($t | startswith("/Volumes"))
          and ($s | endswith("[" + ($t | sub("^/Volumes"; "")) + "]"))
        );

      # Choose the deepest target (longest string) among matches, skip "/".
      [ mounts
        | select(.target != "/")
        | select(is_match(.target; .source))
      ]
      | sort_by(.target | length)
      | last
      | .target
      // empty
    '
}

# Conservative safety check: refuse to replace if TARGET_LINK is a mountpoint.
is_mountpoint() {
  if command -v mountpoint >/dev/null 2>&1; then
    mountpoint -q --nofollow "$1"
    return $?
  fi

  # Fallback: parse /proc/self/mountinfo
  # Mountpoint is field 5 (mount point) in mountinfo.
  local p
  p="$(readlink -f "$1" 2>/dev/null || echo "$1")"
  awk -v p="$p" '$5 == p { found=1 } END { exit(found ? 0 : 1) }' /proc/self/mountinfo
}

main() {
  MIRRORED="$(discover_mirrored_workspace || true)"

  diag="$(findmnt --real --json 2>&1)"

  if [[ -z "${MIRRORED:-}" || ! -d "$MIRRORED" ]]; then
    log "ERROR: Could not discover mirrored workspace mount via findmnt."
    log "Diagnostics:"
    log "$diag"
    exit 1
  fi

  case "$MIRRORED" in
    /|/etc/*|/proc/*|/sys/*|/run/*|/dev/*)
      log "ERROR: Refusing suspicious workspace candidate: $MIRRORED"
      exit 1
      ;;
  esac

  # Replace /home/agent/workspace with a symlink to the mirrored workspace.
  # First cd away from the directory we're about to delete (WORKDIR sets cwd to workspace)
  cd /tmp

  # Safety check: refuse to delete if workspace is a mountpoint
  if is_mountpoint "$AGENT_WORKSPACE"; then
    log "ERROR: $AGENT_WORKSPACE is a mountpoint. Refusing to delete."
    exit 1
  fi

  # Handle workspace replacement robustly:
  # - If it's a symlink, remove it
  # - If it's an empty directory, remove it
  # - If it's a non-empty directory, move it aside (shouldn't happen normally)
  if [[ -L "$AGENT_WORKSPACE" ]]; then
    rm "$AGENT_WORKSPACE"
  elif [[ -d "$AGENT_WORKSPACE" ]]; then
    if ! rm -d "$AGENT_WORKSPACE" 2>/dev/null; then
      # Directory not empty - move aside with timestamp
      local backup="${AGENT_WORKSPACE}.bak.$(date +%s)"
      log "WARNING: $AGENT_WORKSPACE not empty. Moving to $backup"
      mv "$AGENT_WORKSPACE" "$backup"
    fi
  fi

  ln -s "$MIRRORED" "$AGENT_WORKSPACE"
  cd "$AGENT_WORKSPACE"

  # Continue with the container's original command
  exec "$@"
}

main "$@"