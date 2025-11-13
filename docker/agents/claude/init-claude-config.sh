#!/usr/bin/env bash
set -euo pipefail

echo "⚙️ Initializing Claude config inside container..."

HOST_CLAUDE_DIR="$HOME/.claude"
HOST_CREDENTIALS="$HOST_CLAUDE_DIR/.credentials.json"

CONTAINER_CLAUDE_DIR="$HOME/.claude"
CONTAINER_CREDENTIALS="$CONTAINER_CLAUDE_DIR/.credentials.json"
DEFAULT_CONFIG_SOURCE="$HOME/.config/coding-agents/claude/.claude.json"
DEFAULT_CONFIG_TARGET="$HOME/.claude.json"

mkdir -p "$CONTAINER_CLAUDE_DIR"

# Seed global .claude.json from repo defaults if not present
if [ ! -f "$DEFAULT_CONFIG_TARGET" ] && [ -f "$DEFAULT_CONFIG_SOURCE" ]; then
  cp "$DEFAULT_CONFIG_SOURCE" "$DEFAULT_CONFIG_TARGET"
fi

# Copy credentials from host into container if available
if [ -f "$HOST_CREDENTIALS" ]; then
  cp "$HOST_CREDENTIALS" "$CONTAINER_CREDENTIALS"
fi
