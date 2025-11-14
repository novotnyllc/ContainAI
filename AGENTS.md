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

### Integration Test Expectations

- **Build time**: Integration tests run inside an isolated Docker-in-Docker environment to keep the host Docker daemon pristine. A full rebuild (`integration-test.sh --mode full`) takes 15-25 minutes because every agent image is rebuilt inside the isolated sandbox. Launchers mode (`--mode launchers`) uses mock images and completes in 5-10 minutes. Plan your CI and local workflows accordingly.
- **Host isolation**: All integration tests run via `scripts/test/integration-test.sh`, which automatically creates a disposable Docker-in-Docker container. This ensures no containers, images, or networks leak to the host system.
