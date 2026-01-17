#!/usr/bin/env bash
set -euo pipefail


# Canonical location
AGENT_WORKSPACE="${HOME}/workspace"

# Ensure that files are were they are expected to be and folders created.
sudo chown -R agent:agent /mnt/agent-data
mkdir -p /mnt/agent-data/claude/plugins 
mkdir -p /mnt/agent-data/vscode-server/extensions /mnt/agent-data/vscode-server/data/Machine /mnt/agent-data/vscode-server/data/User /mnt/agent-data/vscode-server/data/User/mcp /mnt/agent-data/vscode-server/data/User/prompts 
mkdir -p /mnt/agent-data/vscode-server-insiders/extensions /mnt/agent-data/vscode-server-insiders/data/Machine /mnt/agent-data/vscode-server-insiders/data/User /mnt/agent-data/vscode-server-insiders/data/User/mcp /mnt/agent-data/vscode-server-insiders/data/User/prompts 
mkdir -p /mnt/agent-data/copilot
mkdir -p /mnt/agent-data/codex/skills
mkdir -p /mnt/agent-data/gemini
mkdir -p /mnt/agent-data/opencode

touch /mnt/agent-data/vscode-server/data/Machine/settings.json /mnt/agent-data/vscode-server/data/User/mcp.json
touch /mnt/agent-data/vscode-server-insiders/data/Machine/settings.json /mnt/agent-data/vscode-server-insiders/data/User/mcp.json
touch /mnt/agent-data/claude/claude.json /mnt/agent-data/claude/.credentials.json /mnt/agent-data/claude/settings.json
touch /mnt/agent-data/gemini/google_accounts.json /mnt/agent-data/gemini/oauth_creds.json /mnt/agent-data/gemini/settings.json
touch /mnt/agent-data/codex/auth.json /mnt/agent-data/codex/config.toml

# Check if .claude.json exists, is 0 bytes, and is not a symlink
# Docker Sandbox creates the file when creating the container replacing a link
  CLAUDE_JSON="${AGENT_WORKSPACE}/.claude.json"
  if [[ -f "$CLAUDE_JSON" && ! -L "$CLAUDE_JSON" && ! -s "$CLAUDE_JSON" ]]; then
    log "WARNING: ${CLAUDE_JSON} exists but is empty (0 bytes)"
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
  rm -d "$AGENT_WORKSPACE"
  ln -s "$MIRRORED" "$AGENT_WORKSPACE"

  

  # Continue with the container's original command
  exec "$@"
}

main "$@"
