# Coding Agents Repository

This file contains repository-specific guidance for working with the Coding Agents codebase.

## Repository Structure

- `agent-configs/` - Custom instruction files for coding agents (copied to containers)
- `docker/` - Container definitions and compose configurations
- `scripts/` - Utility scripts (PowerShell and bash)
- `config.toml` - MCP server configuration template
- `docs/` - Documentation

## Key Principles

1. **Script Parity** - All functionality must exist in both PowerShell and bash
2. **Test Coverage** - All functions must have comprehensive unit tests
3. **Code Quality** - PowerShell must pass PSScriptAnalyzer with zero warnings
4. **Documentation** - Keep CONTRIBUTING.md `docs/` updated with workflow changes

## Agent Configuration

Custom instructions for AI coding agents are stored in `agent-configs/`

These files are automatically copied to containers and applied per agent.

## Development Workflow

See `CONTRIBUTING.md` for detailed development guidelines including:
- Test suite usage
- Inner loop development process
- Code quality standards
- Debugging techniques
