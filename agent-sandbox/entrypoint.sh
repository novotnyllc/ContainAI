#!/usr/bin/env bash
set -euo pipefail

# Ensure that files are were they are expected to be and folders created.

mkdir -p /mnt/agent-data/claude/plugins 
mkdir -p /mnt/agent-data/vscode-server/extensions /mnt/agent-data/vscode-server/data/Machine /mnt/agent-data/vscode-server/data/User /mnt/agent-data/vscode-server/data/User/mcp /mnt/agent-data/vscode-server/data/User/prompts 
mkdir -p /mnt/agent-data/vscode-server-insiders/extensions /mnt/agent-data/vscode-server-insiders/data/Machine /mnt/agent-data/vscode-server-insiders/data/User /mnt/agent-data/vscode-server-insiders/data/User/mcp /mnt/agent-data/vscode-server-insiders/data/User/prompts 
mkdir -p /mnt/agent-data/copilot 
mkdir -p /mnt/agent-data/codex/skills
mkdir -p /mnt/agent-data/gemini
mkdir -p /mnt/agent-data/opencode

touch /mnt/agent-data/vscode-server/data/Machine/settings.json /mnt/agent-data/vscode-server/data/User/mcp.json
touch /mnt/agent-data/vscode-server-insiders/data/Machine/settings.json /mnt/agent-data/vscode-server-insiders/data/User/mcp.json

touch /mnt/agent-data/gemini/google_accounts.json /mnt/agent-data/gemini/oauth_creds.json /mnt/agent-data/gemini/settings.json

touch /mnt/agent-data/codex/auth.json /mnt/agent-data/codex/config.toml


# Canonical location your tooling expects
TARGET_LINK="${HOME}/workspace"

log() { printf '%s\n' "$*" >&2; }

# Discover the mirrored workspace mount.
# In Docker Sandbox, the workspace shows up in `findmnt --real` as:
#   TARGET=/some/abs/path
#   SOURCE=/dev/sdX[/some/abs/path]
discover_mirrored_workspace() {
  findmnt --real -n -o TARGET,SOURCE \
  | awk '
      {
        tgt=$1; src=$2
        # Match SOURCE ending with "[<TARGET>]"
        if (src ~ "\\[" tgt "\\]$") print tgt
      }
    ' \
  | head -n 1
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

  if [[ -z "${MIRRORED:-}" ]]; then
    log "ERROR: Could not discover mirrored workspace mount via findmnt."
    log "Diagnostics:"
    (findmnt --real -o TARGET,SOURCE,FSTYPE,OPTIONS || true) >&2
    exit 1
  fi

  if [[ ! -d "$MIRRORED" ]]; then
    log "ERROR: Discovered mirrored workspace is not a directory: $MIRRORED"
    exit 1
  fi

  # If /home/agent/workspace is itself a mountpoint, do not rm -rf it.
  if is_mountpoint "$TARGET_LINK"; then
    log "ERROR: $TARGET_LINK is a mountpoint; refusing to replace it with a symlink."
    log "       Use the mirrored workspace directly: $MIRRORED"
    exit 1
  fi

  # Replace /home/agent/workspace with a symlink to the mirrored workspace.
  rm -d "$TARGET_LINK"
  ln -s "$MIRRORED" "$TARGET_LINK"

  # Continue with the container's original command
  exec "$@"
}

main "$@"
