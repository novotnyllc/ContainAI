#!/usr/bin/env python3
"""
Convert config.toml to agent-specific MCP JSON configurations.
Reads a single source of truth (config.toml) and generates config files for each agent.
"""

import json
import os
import sys

try:
    import tomllib  # Python 3.11+
except ImportError:
    try:
        import tomli as tomllib  # Fallback for older Python
    except ImportError:
        print("❌ Error: tomllib/tomli not available", file=sys.stderr)
        print("   Install with: pip install tomli", file=sys.stderr)
        sys.exit(1)


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
    
    # Create config directories and write configs for each agent
    agents = {
        "github-copilot": "~/.config/github-copilot/mcp",
        "codex": "~/.config/codex/mcp",
        "claude": "~/.config/claude/mcp"
    }
    
    for agent_name, config_path in agents.items():
        config_dir = os.path.expanduser(config_path)
        os.makedirs(config_dir, exist_ok=True)
        
        # Customize serena context per agent (codex uses 'codex', others use 'ide-assistant')
        agent_mcp_servers = mcp_servers.copy()
        if "serena" in agent_mcp_servers and agent_name == "codex":
            # Deep copy serena config for codex agent
            serena_config = agent_mcp_servers["serena"].copy()
            if "args" in serena_config:
                args = serena_config["args"].copy()
                # Replace '--context', 'ide-assistant' with '--context', 'codex'
                for i in range(len(args) - 1):
                    if args[i] == "--context" and args[i + 1] == "ide-assistant":
                        args[i + 1] = "codex"
                        break
                serena_config["args"] = args
                agent_mcp_servers["serena"] = serena_config
        
        mcp_config = {
            "mcpServers": agent_mcp_servers
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
