# ContainAI Repository

This file contains repository-specific guidance for working with the ContainAI codebase.

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

- `agent-configs/` - Custom instruction files for agents (copied to containers)
- `docker/` - Container definitions and compose configurations
- `scripts/` - Utility scripts (bash plus thin Windows shims)
- `config.toml` - MCP server configuration template
- `docs/` - Documentation

## Key Principles

1. **Canonical Bash** - Bash implementations are the source of truth. Windows `.ps1` wrappers simply delegate into WSL and must stay in sync with their bash counterparts.
2. **Test Coverage** - All functions must have comprehensive unit tests
3. **Shim Quality** - Windows shims should perform only WSL validation/path translation and must not fork business logic
4. **Fail-Closed Security** - Security controls (user switching, seccomp, capabilities) must never fail open. If a security primitive cannot be established, the process must exit immediately. No silent fallbacks to insecure states.
5. **Dependency Management** - Regularly check for and update dependencies (Docker base images, system packages, NuGet packages, Rust crates, npm packages) to the latest stable versions to absorb bug fixes and security updates.
6. **Documentation** - Keep CONTRIBUTING.md `docs/` updated with workflow changes

## Coding Conventions 

- **Windows shims**: `host/utils/wsl-shim.ps1` handles WSL detection and path conversion. Keep individual `.ps1` entrypoints minimal—dot-source the shim, pass arguments through, and propagate exit codes.
- **Bash**: Use `set -euo pipefail`, quote variables, prefer POSIX-friendly syntax unless Bash-only needed.
- **Shared Behavior**: Fixes belong in bash. After updating a bash workflow, regenerate or adjust the corresponding shim (if any) plus its tests so Windows callers still reach the new logic.
- **Tests First-Class**: Whenever you change branch/remote handling or setup scripts, update both bash and PowerShell launcher tests plus integration tests to reflect the new guarantees.

## Agent Configuration

Custom instructions for AI agents are stored in `agent-configs/`

These files are automatically copied to containers and applied per agent.

## Development Workflow

See `CONTRIBUTING.md` for detailed development guidelines including:
- Test suite usage
- Inner loop development process
- Code quality standards
- Debugging techniques

### Integration Test Expectations

- **Build time**: A full rebuild (`integration-test.sh --mode full`) takes 15-25 minutes because every agent image is rebuilt. Launchers mode (`--mode launchers`) uses mock images and completes in 5-10 minutes. Plan your CI and local workflows accordingly.
- **Resource isolation**: Integration tests use session-scoped labels (`containai.test.session=<ID>`) to track all created resources. The harness automatically cleans up test containers, networks, and volumes on exit. Orphaned resources older than 24 hours are also pruned at startup.

### CI Verification Standards

All code changes must pass the following automated checks in the CI pipeline:

1.  **Static Analysis**:
    - **Bash**: `shellcheck` must pass for all `.sh` scripts.
    - **Python**: `pylint` and `mypy` must pass for all host utility scripts.
    - **Rust**: `cargo clippy` must pass with no warnings.

2.  **Unit Tests**:
    - **C#**: All `.Tests` projects must pass (`dotnet test`).
    - **Rust**: All crates must pass `cargo test`.
    - **Bash**: Launcher logic must pass `scripts/test/test-launchers.sh`.

3.  **Integration Tests**:
    - Changes to launchers or core runtime must pass `scripts/test/integration-test.sh`.

