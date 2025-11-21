#!/usr/bin/env bash
# Convert config.toml to agent-specific MCP configurations
# This script reads the single source of truth (config.toml in the workspace)
# and generates the appropriate config files for each agent

set -euo pipefail

MCP_CONFIG="${MCP_CONFIG_OVERRIDE:-/workspace/config.toml}"

if [ ! -f "$MCP_CONFIG" ]; then
    echo "⚠️  No config.toml found at $MCP_CONFIG"
    exit 0
fi

# Validate config file is readable
if [ ! -r "$MCP_CONFIG" ]; then
    echo "❌ Error: Cannot read config.toml at $MCP_CONFIG"
    exit 1
fi

echo "🔧 Converting MCP configuration to agent-specific formats..."

# Run the Python converter script with error handling
if ! python3 /usr/local/bin/convert-toml-to-mcp.py "$MCP_CONFIG"; then
    echo "❌ Error: Failed to convert MCP configuration"
    exit 1
fi

echo "✅ MCP configuration converted successfully"
