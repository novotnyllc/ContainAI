# Contributing to ContainAI

## Development Workflow

> **📚 Build System Reference:** For a comprehensive overview of the build pipeline, scripts, and artifacts, see [build-architecture.md](build-architecture.md).

### Prerequisites
- **Container Runtime**: Docker Desktop (macOS/Windows) or Docker Engine (Linux)
- **Git** configured with `user.name` and `user.email`
- **GitHub CLI** authenticated: `gh auth login`
- **PowerShell 7+** (Windows) or **Bash** (Linux/macOS)
- (Optional) Authenticated agents (Copilot, Codex, Claude) on host machine

### Quick Start

```bash
# Clone the repository
git clone https://github.com/your-org/containai.git
cd containai

# Run unit tests (fast, ~1-2 minutes)
# Bash
./scripts/test/test-launchers.sh
./scripts/test/test-branch-management.sh

# PowerShell
pwsh scripts/test/test-launchers.ps1
pwsh scripts/test/test-branch-management.ps1

# Run integration tests (slower, ~3-5 minutes)
./scripts/test/integration-test.sh --mode launchers
```

## Test Suite Overview

### Unit Tests
**Purpose**: Fast validation of individual functions and launcher scripts  
**Time**: ~1-2 minutes per test file  
**When to run**: After every code change, before committing

#### Bash Unit Tests
```bash
# Test launcher scripts and common functions
./scripts/test/test-launchers.sh

# Test branch management (conflict detection, archiving, cleanup)
./scripts/test/test-branch-management.sh
```

#### PowerShell Unit Tests
```powershell
# Test launcher scripts and common functions
pwsh scripts/test/test-launchers.ps1

# Test branch management
pwsh scripts/test/test-branch-management.ps1
```

**What they test:**
- Container naming conventions
- Docker label assignment
- Git branch operations (create, rename, delete, detect conflicts)
- Repository name extraction
- Branch sanitization for Docker names
- WSL path conversion (Windows ↔ WSL)
- Image pull and tagging
- Container lifecycle management
- Multi-agent isolation

### Integration Tests
**Purpose**: End-to-end validation of the entire system  
**Time**: 3-5 minutes (launchers mode), 10-15 minutes (full mode)  
**When to run**: Before submitting PR, or when making significant changes

```bash
# Fast mode: Test with existing images
./scripts/test/integration-test.sh --mode launchers

# Full mode: Build all images and test
./scripts/test/integration-test.sh --mode full

# Debug mode: Preserve test resources for inspection
./scripts/test/integration-test.sh --mode full --preserve
```

**What they test:**
- Local Docker registry setup
- Image building (full mode only)
- Image pulling and tagging (launchers mode)
- Launcher script execution
- Container creation with proper labels
- Network connectivity between containers
- Workspace mounting
- Environment variable injection
- **Agent credential flow** (secret broker → capability → unseal → validate)
- Multi-agent concurrent operation
- Resource cleanup

### Deterministic Container Management

Integration tests use **deterministic container management** instead of arbitrary sleep timers:

- **Keep-alive**: Containers use `sleep infinity` instead of time-based sleeps
- **Readiness polling**: `wait_for_container_ready()` polls container state until running
- **Timeout-based**: Maximum wait of 30 seconds with 0.5s poll interval
- **Fail-fast**: Tests fail immediately if container enters `exited` or `dead` state

This ensures tests are reproducible and don't depend on timing assumptions.

## Inner Loop Development

### Typical Development Cycle

1. **Make code changes** to scripts in `host/launchers/` or `host/utils/`

2. **Run relevant unit tests immediately**:
   ```bash
   # Quick validation
   ./scripts/test/test-launchers.sh
   ```

3. **If tests pass, test manually** with a real container:
   ```bash
   # Launch an agent to test manually
   ./host/launchers/launch-agent copilot . --branch test-feature
   ```

4. **Before committing**, run full unit tests:
   ```bash
   ./scripts/test/test-launchers.sh
   ./scripts/test/test-branch-management.sh
   ```

5. **Before submitting PR**, run integration tests:
   ```bash
   ./scripts/test/integration-test.sh --mode launchers
   ```

### Testing Without Secrets
All tests use **mock credentials** and are **completely isolated**:
- No real GitHub tokens required
- Local Docker registry (localhost:5555)
- Temporary git repositories
- Session-labeled containers
- Auto-cleanup after tests

#### Credential Flow Testing
Integration tests verify the **full credential pipeline** without real secrets:

1. **Host-side**: Secret broker issues capabilities and stores mock credentials
2. **Broker seal**: Credentials are cryptographically sealed to capability tokens
3. **Container-side**: `prepare-*-secrets.sh` runs `capability-unseal` to decrypt
4. **Validation**: Tests verify credentials are correctly materialized

This tests the entire security flow from host broker to container credential files.

### Debugging Failed Tests

#### Preserve Test Resources
```bash
# Keep containers and networks for inspection
./scripts/test/integration-test.sh --mode full --preserve
```

Then inspect with:
```bash
# List test containers
docker ps -a --filter "label=containai.test=true"

# View container logs
docker logs <container-name>

# Inspect labels
docker inspect <container-name>

# Check networks
docker network ls | grep test-containai
```

#### Manual Cleanup
If tests crash and don't clean up:
```bash
# Remove all test containers
docker ps -aq --filter "label=containai.test=true" | xargs docker rm -f

# Remove test networks
docker network ls | grep test-containai | awk '{print $1}' | xargs docker network rm

# Remove test repositories
rm -rf /tmp/test-containai-*
```

## Code Quality Standards

### PowerShell Scripts
All PowerShell scripts must pass PSScriptAnalyzer with **PSGallery** settings:

```powershell
# Install PSScriptAnalyzer if needed
Install-Module -Name PSScriptAnalyzer -Scope CurrentUser

# Check all scripts
$results = Get-ChildItem -Path "host" -Filter "*.ps1" -Recurse | 
    ForEach-Object { Invoke-ScriptAnalyzer -Path $_.FullName -Settings PSGallery }

# Should return no errors or warnings
$results | Where-Object {$_.Severity -in @('Error','Warning')}
```

**Requirements:**
- Use approved verbs (`Get-`, `Set-`, `New-`, `Remove-`, `Test-`, etc.)
- Use singular nouns for cmdlet names (except when semantically plural)
- Implement `SupportsShouldProcess` for state-changing functions
- Add `[CmdletBinding()]` to advanced functions
- Use proper parameter validation

### Bash Scripts
- Use `set -euo pipefail` at the top of scripts
- Follow consistent naming: `snake_case` for functions
- Add error handling for all external commands
- Use `||` or `&& ` for explicit error handling
- Test with `shellcheck` if available

### Common Requirements
- **Avoid hardcoded secrets** - use environment variables or mock values in tests
- **Complete error handling** - every external command should handle failures
- **Descriptive error messages** - tell users what went wrong and how to fix it
- **Runtime parity** - bash is the source of truth; Windows `.ps1` shims must invoke the same bash scripts via `host/utils/wsl-shim.ps1`
- **Test coverage** - all new functions need corresponding tests

## Script Parity

### Windows WSL shims

Bash scripts contain all runtime logic. Windows support is delivered through thin `.ps1` wrappers that:
1. dot-source `host/utils/wsl-shim.ps1`
2. call `Invoke-ContainAIWslScript -ScriptRelativePath '<target bash script>' -Arguments $Arguments`
3. exit with the propagated status code

Only scripts that touch native Windows settings (for example `enable-wsl-security.ps1`) should contain standalone PowerShell logic. When adding or renaming a Bash entrypoint, create the matching shim so Windows users can invoke the same behavior from PowerShell.

## File Structure

```
containai/
├── host/
│   ├── launchers/           # User-facing scripts
│   │   ├── launch-agent     # Bash version
│   │   ├── launch-agent.ps1 # PowerShell version
│   │   ├── remove-agent     # Remove containers
│   │   ├── list-agents      # List running agents
│   │   └── run-*            # Quick launch scripts
│   └── utils/               # Shared functions
│       ├── common-functions.sh   # Bash library
│       └── wsl-shim.ps1          # Shared Windows shim helper
├── scripts/
│   └── test/                # Test suites
│       ├── test-launchers.sh     # Unit tests (bash)
│       ├── test-launchers.ps1    # Unit tests (PowerShell)
│       ├── test-branch-management.sh  # Branch tests (bash)
│       ├── test-branch-management.ps1 # Branch tests (PowerShell)
│       ├── integration-test.sh   # Full system tests
│       ├── test-env.sh           # Test environment utilities
│       ├── test-config.sh        # Test configuration (bash)
│       └── test-config.ps1       # Test configuration (PowerShell)
└── docs/development/contributing.md          # This file
```

## Submitting Changes

### Before Submitting a PR
1. ✅ Run all unit tests (bash and PowerShell)
2. ✅ Run integration tests (`--mode launchers` minimum)
3. ✅ Verify PowerShell passes PSScriptAnalyzer
4. ✅ Test manually with at least one agent
5. ✅ Update tests if adding new functionality
6. ✅ Ensure bash/PowerShell parity for new features

### PR Checklist
- [ ] All unit tests pass (bash and PowerShell)
- [ ] Integration tests pass
- [ ] PSScriptAnalyzer shows no errors/warnings
- [ ] Both bash and PowerShell versions updated (if applicable)
- [ ] New functions have corresponding tests
- [ ] Error messages are clear and actionable
- [ ] No hardcoded secrets or credentials
- [ ] Documentation updated if needed

## Getting Help

### Common Issues

**Docker not starting?**
- Windows: Ensure Docker Desktop is installed
- Linux: `sudo systemctl start docker`
- Mac: Open Docker Desktop application

**Tests hanging?**
- Check Docker is responsive: `docker ps`
- Check available disk space: `docker system df`
- Kill stuck containers: `docker ps -aq | xargs docker rm -f`

**Path issues on Windows?**
- Use WSL2 for best compatibility
- Check path conversion: `Convert-WindowsPathToWsl "C:\path"`
- Verify Git is installed in WSL: `wsl git --version`

**Port conflicts?**
- Default registry port: 5555
- Check with: `lsof -i :5555` (Linux/Mac) or `netstat -ano | findstr :5555` (Windows)
- Kill process or change `TEST_REGISTRY_PORT` in test-config

## Architecture Notes

### Branch Management
Each agent gets its own branch: `<agent>/<base-branch>`
- **Conflict detection**: Checks for unmerged commits before replacing
- **Auto-archiving**: Branches with unmerged work are renamed with timestamp
- **Cleanup**: Branches deleted when container removed (unless unmerged)

### Network Isolation
Two network modes:
- **squid**: HTTP proxy with full access (default)
- **restricted**: HTTP proxy with strict allowlist (*.github.com, *.nuget.org, etc.)

### Container Labels
Every agent container has labels:
```
containai.type=agent
containai.agent=<copilot|codex|claude>
containai.repo-path=<path>
containai.branch=<agent/branch>
containai.proxy-container=<proxy-name>  # if using squid
containai.proxy-network=<network-name>  # if using squid
```

### Test Isolation
Tests use session IDs (process ID) for complete isolation:
- Containers: `label=containai.test-session=<PID>`
- Networks: `test-containai-net-<PID>`
- Repositories: `/tmp/test-containai-<PID>`

This allows parallel test execution without conflicts.

---

## See Also

- [build-architecture.md](build-architecture.md) — Complete build pipeline and script reference
- [build.md](build.md) — Container image contents and modification
- [ghcr-publishing.md](ghcr-publishing.md) — GitHub repository setup and operations

## External Resources

- [Docker Documentation](https://docs.docker.com/)
- [PowerShell Documentation](https://docs.microsoft.com/powershell/)
- [PSScriptAnalyzer Rules](https://github.com/PowerShell/PSScriptAnalyzer)
- [Git Branch Naming](https://git-scm.com/docs/git-check-ref-format)
- [Docker Labels](https://docs.docker.com/config/labels-custom-metadata/)
