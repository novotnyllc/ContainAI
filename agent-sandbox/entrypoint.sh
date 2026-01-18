#!/usr/bin/env bash
set -euo pipefail


# Canonical location
AGENT_WORKSPACE="${HOME}/workspace"

# Ensure all volume structure exists for symlinks to work.
# Derived from SYNC_MAP targets in sync-agent-plugins.sh
ensure_volume_structure() {
  local data_dir="/mnt/agent-data"

  # Bootstrap: ensure volume root is writable by agent user (1000:1000)
  # On a fresh Docker volume, /mnt/agent-data is root:root, so we need sudo first
  sudo mkdir -p "${data_dir}"
  sudo chown 1000:1000 "${data_dir}"

  # Claude Code
  mkdir -p "${data_dir}/claude"
  [ -s "${data_dir}/claude/claude.json" ] || echo '{}' > "${data_dir}/claude/claude.json"
  touch "${data_dir}/claude/credentials.json"
  [ -s "${data_dir}/claude/settings.json" ] || echo '{}' > "${data_dir}/claude/settings.json"
  touch "${data_dir}/claude/settings.local.json"
  mkdir -p "${data_dir}/claude/plugins"
  mkdir -p "${data_dir}/claude/skills"
  chmod 600 "${data_dir}/claude/claude.json"
  chmod 600 "${data_dir}/claude/credentials.json"

  # GitHub CLI
  mkdir -p "${data_dir}/config/gh"
  chmod 700 "${data_dir}/config/gh"

  # OpenCode (config via ~/.config symlink)
  mkdir -p "${data_dir}/config/opencode"

  # tmux
  mkdir -p "${data_dir}/tmux"
  touch "${data_dir}/tmux/.tmux.conf"
  mkdir -p "${data_dir}/tmux/.tmux"
  mkdir -p "${data_dir}/config/tmux"

  # Shell
  mkdir -p "${data_dir}/shell"
  touch "${data_dir}/shell/.bash_aliases"
  mkdir -p "${data_dir}/shell/.bashrc.d"

  # VS Code Server
  mkdir -p "${data_dir}/vscode-server/extensions"
  mkdir -p "${data_dir}/vscode-server/data/Machine"
  mkdir -p "${data_dir}/vscode-server/data/User/mcp"
  mkdir -p "${data_dir}/vscode-server/data/User/prompts"
  [ -s "${data_dir}/vscode-server/data/Machine/settings.json" ] || echo '{}' > "${data_dir}/vscode-server/data/Machine/settings.json"
  [ -s "${data_dir}/vscode-server/data/User/mcp.json" ] || echo '{}' > "${data_dir}/vscode-server/data/User/mcp.json"

  # VS Code Insiders
  mkdir -p "${data_dir}/vscode-server-insiders/extensions"
  mkdir -p "${data_dir}/vscode-server-insiders/data/Machine"
  mkdir -p "${data_dir}/vscode-server-insiders/data/User/mcp"
  mkdir -p "${data_dir}/vscode-server-insiders/data/User/prompts"
  [ -s "${data_dir}/vscode-server-insiders/data/Machine/settings.json" ] || echo '{}' > "${data_dir}/vscode-server-insiders/data/Machine/settings.json"
  [ -s "${data_dir}/vscode-server-insiders/data/User/mcp.json" ] || echo '{}' > "${data_dir}/vscode-server-insiders/data/User/mcp.json"

  # Copilot
  mkdir -p "${data_dir}/copilot/skills"
  [ -s "${data_dir}/copilot/config.json" ] || echo '{}' > "${data_dir}/copilot/config.json"
  [ -s "${data_dir}/copilot/mcp-config.json" ] || echo '{}' > "${data_dir}/copilot/mcp-config.json"

  # Gemini
  mkdir -p "${data_dir}/gemini"
  [ -s "${data_dir}/gemini/google_accounts.json" ] || echo '{}' > "${data_dir}/gemini/google_accounts.json"
  [ -s "${data_dir}/gemini/oauth_creds.json" ] || echo '{}' > "${data_dir}/gemini/oauth_creds.json"
  touch "${data_dir}/gemini/GEMINI.md"
  [ -s "${data_dir}/gemini/settings.json" ] || echo '{}' > "${data_dir}/gemini/settings.json"
  chmod 600 "${data_dir}/gemini/google_accounts.json"
  chmod 600 "${data_dir}/gemini/oauth_creds.json"

  # Codex
  mkdir -p "${data_dir}/codex/skills"
  touch "${data_dir}/codex/config.toml"
  [ -s "${data_dir}/codex/auth.json" ] || echo '{}' > "${data_dir}/codex/auth.json"
  chmod 600 "${data_dir}/codex/auth.json"

  # OpenCode (auth from data dir)
  mkdir -p "${data_dir}/local/share/opencode"
  [ -s "${data_dir}/local/share/opencode/auth.json" ] || echo '{}' > "${data_dir}/local/share/opencode/auth.json"
  chmod 600 "${data_dir}/local/share/opencode/auth.json"

  # Fix ownership (use sudo since entrypoint runs as non-root USER agent)
  sudo chown -R 1000:1000 "${data_dir}"
}

# Ensure volume structure exists
ensure_volume_structure

# Check if .claude.json exists and is 0 bytes
# Docker Sandbox creates the file when creating the container replacing a link
CLAUDE_JSON="${AGENT_WORKSPACE}/.claude.json"
if [[ -f "$CLAUDE_JSON" && ! -s "$CLAUDE_JSON" ]]; then
  echo "{}"> "$CLAUDE_JSON" # Claude complains if there's an empty file and if it creates it it breaks the symlink
fi

log() { printf '%s\n' "$*" >&2; }

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
  rm -d "$AGENT_WORKSPACE"
  ln -s "$MIRRORED" "$AGENT_WORKSPACE"
  cd "$AGENT_WORKSPACE"
  
  # Continue with the container's original command
  exec "$@"
}

main "$@"