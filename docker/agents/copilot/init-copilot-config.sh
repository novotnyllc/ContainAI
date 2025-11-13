#!/usr/bin/env bash
set -euo pipefail

echo "⚙️ Initializing GitHub Copilot CLI config inside container..."

HOST_CFG="$HOME/.copilot/config.json"
CONTAINER_CFG="$HOME/.copilot/config.json"
DEFAULT_CFG="$HOME/.config/github-copilot/agents/config.json"

mkdir -p "$(dirname "$CONTAINER_CFG")"

# Seed from repo-provided defaults if container config doesn't exist yet
if [ ! -f "$CONTAINER_CFG" ] && [ -f "$DEFAULT_CFG" ]; then
  cp "$DEFAULT_CFG" "$CONTAINER_CFG"
fi

if [ ! -f "$HOST_CFG" ]; then
  echo "ℹ️ Host Copilot config not mounted – no tokens to import" >&2
  exit 0
fi

python3 /usr/local/bin/merge-copilot-tokens.py "$HOST_CFG" "$CONTAINER_CFG"
