#!/bin/bash
# Convert config.toml to agent-specific MCP configurations
# This script reads the single source of truth (config.toml in the workspace)
# and generates the appropriate config files for each coding agent

set -e

MCP_CONFIG="/workspace/config.toml"

if [ ! -f "$MCP_CONFIG" ]; then
    echo "⚠️  No config.toml found at $MCP_CONFIG"
    exit 0
fi

echo "🔧 Converting MCP configuration to agent-specific formats..."

# Run the Python converter script
python3 /usr/local/bin/convert-toml-to-mcp.py "$MCP_CONFIG"
