#!/usr/bin/env python3
"""
Convert config.toml to agent-specific MCP JSON configurations.
Reads a single source of truth (config.toml) and generates config files for each agent.
"""

import json
import os
import sys
import tomllib 

def convert_toml_to_mcp(toml_path):
    """Convert TOML config to MCP JSON format for all agents."""
    
    if not os.path.exists(toml_path):
        print(f"⚠️  No config.toml found at {toml_path}", file=sys.stderr)
        return False
    
    # Read and parse TOML
    try:
        with open(toml_path, "rb") as f:
            config = tomllib.load(f)
    except Exception as e:
        print(f"❌ Error parsing TOML: {e}", file=sys.stderr)
        return False
    
    # Extract MCP servers configuration
    mcp_servers = config.get("mcp_servers", {})
    
    if not mcp_servers:
        print("⚠️  No mcp_servers found in config.toml", file=sys.stderr)
        return False
    
    # Only generate standard mcpServers format for Copilot and Claude
    # Codex uses native TOML with MCP servers appended
    agents = {
        "github-copilot": "~/.config/github-copilot/mcp",
        "claude": "~/.config/claude/mcp"
    }
    
    for agent_name, config_path in agents.items():
        config_dir = os.path.expanduser(config_path)
        os.makedirs(config_dir, exist_ok=True)
        
        mcp_config = {
            "mcpServers": mcp_servers
        }
        
        config_file = os.path.join(config_dir, "config.json")
        try:
            with open(config_file, "w") as f:
                json.dump(mcp_config, f, indent=2)
        except Exception as e:
            print(f"❌ Error writing {agent_name} config: {e}", file=sys.stderr)
            return False
    
    print("✅ MCP configurations generated for all agents")
    print(f"   Servers configured: {', '.join(mcp_servers.keys())}")
    print(f"   Config source: {toml_path}")
    return True


if __name__ == "__main__":
    toml_path = sys.argv[1] if len(sys.argv) > 1 else "/workspace/config.toml"
    success = convert_toml_to_mcp(toml_path)
    sys.exit(0 if success else 1)
