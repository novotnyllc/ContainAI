# Coding Agents Repository

This file contains repository-specific guidance for working with the Coding Agents codebase.

# Required Tools and Workflows

## Always Use These MCP Tools

1. **Serena** - For semantic code retrieval and editing
   - Use for understanding code structure and relationships
   - Use for targeted code modifications
   - Provides symbol-level navigation and editing

2. **Context7** - For up-to-date third-party documentation
   - Use when working with external libraries or frameworks
   - Ensures you have current API references
   - Helps avoid deprecated patterns

3. **Sequential Thinking** - For decision making
   - Use for complex problem-solving
   - Break down multi-step tasks
   - Validate assumptions before implementing

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

## Coding Conventions 

- **PowerShell**: Always use approved verb-noun names (`Clear-TestEnvironment`, `Get-ContainerStatus`, etc.). Avoid aliases like `curl`, prefer full cmdlets (`Invoke-WebRequest`). Ensure scripts stay analyzer-clean.
- **Bash**: Use `set -euo pipefail`, quote variables, prefer POSIX-friendly syntax unless Bash-only needed. Mirror behavior with the PowerShell counterpart.
- **Shared Behavior**: When fixing a workflow in one shell, immediately update the sibling script and its tests. Keep comments minimal and only for non-obvious logic so agents can diff quickly.
- **Tests First-Class**: Whenever you change branch/remote handling or setup scripts, update both bash and PowerShell launcher tests plus integration tests to reflect the new guarantees.

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
