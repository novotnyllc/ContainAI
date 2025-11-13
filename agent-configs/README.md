# Agent Configuration Files

This directory contains custom instruction files for AI coding agents used in containers.

## Directory Structure

```
agent-configs/
  AGENTS.md              # General instructions applied to all agents
  github-copilot/        # GitHub Copilot specific files
  codex/                 # Codex specific files
  claude/                # Claude specific files
  README.md              # This file
```

### Base Directory (`agent-configs/`)

Files directly in this directory apply to **all agents**:
- **`AGENTS.md`** - Required MCP tools, workflows, and general guidelines
- No front-matter required in base files

### Agent-Specific Subdirectories

Each agent has its own subdirectory for custom configurations:
- **`github-copilot/`** - Files specific to GitHub Copilot
- **`codex/`** - Files specific to Codex
- **`claude/`** - Files specific to Claude

Agent-specific files may use markdown front-matter for advanced configuration.

## Deployment

Files are copied to containers via `docker/base/Dockerfile`:

1. **Base directory files** → Copied to all agent config locations
2. **Agent-specific subdirectories** → Copied to respective agent config paths
   - `github-copilot/*` → GitHub Copilot config directory
   - `codex/*` → Codex config directory
   - `claude/*` → Claude config directory

## Usage Guidelines

### Base Directory Files

Use base directory (`agent-configs/AGENTS.md`) for:
- MCP tool requirements (Serena, Context7, Sequential Thinking)
- General coding standards applicable to all agents
- Project-wide conventions and patterns
- Do not duplicate this content in agent-specific files

### Agent-Specific Files

Use agent subdirectories for:
- Agent-specific workflows or features
- Custom commands or chat modes
- Agent-optimized patterns or preferences
- Files with markdown front-matter for advanced configuration

## References

- [GitHub Copilot Custom Instructions](https://code.visualstudio.com/docs/copilot/copilot-customization)
- [VS Code Instruction Files](https://code.visualstudio.com/docs/copilot/copilot-customization#_instructions-files)
