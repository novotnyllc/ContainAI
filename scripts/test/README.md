# Test Suite

Comprehensive automated testing for the CodingAgents project, including unit tests and integration tests.

## Overview

### Unit Tests (Primary)

Fast, focused validation of individual components - **run these during development**:

**Launcher Tests** (`test-launchers.sh` / `test-launchers.ps1`):
- Container naming conventions
- Docker label assignment and verification
- Git repository operations
- Image pull and tagging
- WSL path conversion (Windows)
- Branch name sanitization
- Multi-agent isolation

**Branch Management Tests** (`test-branch-management.sh` / `test-branch-management.ps1`):
- Branch existence checking
- Branch creation, renaming, deletion
- Unmerged commit detection
- Conflict resolution and archiving
- Agent branch isolation
- Container/branch cleanup integration

**Both bash and PowerShell** versions provide equivalent coverage and should pass identically.

### Integration Tests (Bash Only)

Full end-to-end system validation with two modes:

**Launchers Mode** (Fast - recommended for development):
- Uses existing Docker images
- Tests launcher script execution end-to-end
- Validates container creation, networking, mounting
- Tests multi-agent scenarios
- ~3-5 minutes

**Full Mode** (Complete - for CI/CD):
- Builds all images from Dockerfiles in isolated registry
- Complete validation including build process
- ~10-15 minutes

**Note**: Integration tests are bash-only because they test the complete system including Docker images and containers, which are language-agnostic. Unit tests provide bash/PowerShell parity validation.

## Feature Coverage Matrix

| Integration tests – host secrets | `./scripts/test/integration-test.sh --mode launchers --with-host-secrets` | Copies your `mcp-secrets.env` into the isolated DinD harness (or uses the host daemon if you pass `--isolation host`) and exercises the `run-<agent> --prompt` path (currently Copilot) to verify live secrets. |

> **Why there isn't a PowerShell integration harness**
> The PowerShell launchers (`run-*.ps1`) are thin wrappers that forward arguments to the shared bash implementation (`host/launchers/run-agent`). The integration suite manipulates containers, DinD, and git state entirely through bash, so duplicating the 800+ line harness in PowerShell would provide no extra coverage. We rely on the existing PowerShell unit tests (`test-launchers.ps1`, `test-branch-management.ps1`) to guard the PS entrypoints and keep all end-to-end validation centralized in the bash integration runner.
| Feature / Guarantee                          | Automated Coverage                                                                                              | Notes |
|----------------------------------------------|------------------------------------------------------------------------------------------------------------------|-------|
| Container launch, labels, workspace mounts   | `integration-test.sh`: launcher execution, label, networking, workspace, env-variable tests                      | Ensures runtime wiring matches docs. |
| Multi-agent isolation & cleanup              | `integration-test.sh`: multiple agent, isolation, cleanup sections                                               | Validates concurrent containers + teardown. |
| Branch/auto-push safety                      | `test-branch-management.sh` / `.ps1` unit suites                                                                 | Bash & PowerShell parity. |
| MCP config conversion                        | `integration-test.sh::test_mcp_configuration_generation`                                                         | Exercises `/usr/local/bin/setup-mcp-configs.sh` with mock config.toml. |
| Network proxy modes (`restricted` / `squid`) | `integration-test.sh::test_network_proxy_modes`                                                                  | Uses mock proxy container + `--network none` to ensure wiring behaves. |
| Proxy payload limits                         | `integration-test.sh::test_squid_proxy_hardening` (rate-limit checks)                                            | Enforces 10MB request / 100MB response caps and logs limit violations. |
| Proxy hardening (metadata/RFC1918 blocks)    | `integration-test.sh::test_squid_proxy_hardening`                                                                | Builds the Squid image and ensures private/link-local ranges are denied while allowed domains still transit. |
| Shared utility functions                     | `integration-test.sh::test_shared_functions` + unit suites                                                       | Guards regressions in `host/utils/common-functions.*`. |
| Runtime secret handling                      | Mock fixtures under `scripts/test/fixtures/mock-secrets` ensure no real credentials are required for tests       | Fixtures copied into isolated workspace. |

## Test Files

### Unit Tests
- **`test-launchers.sh`**: Bash launcher unit tests (~390 lines)
- **`test-launchers.ps1`**: PowerShell launcher unit tests (~460 lines)  
  Tests: container naming, labels, image operations, WSL paths, branch sanitization
  
- **`test-branch-management.sh`**: Bash branch management tests (~430 lines)
- **`test-branch-management.ps1`**: PowerShell branch management tests (~512 lines)  
  Tests: branch operations, conflict detection, archiving, cleanup, unmerged commits

### Integration Tests (Bash Only)
- **`integration-test.sh`**: Isolated integration test runner (~250 lines)
- **`integration-test-impl.sh`**: Internal test implementation (~577 lines)
- **`test-config.sh`**: Test configuration with mock credentials
- **`test-env.sh`**: Environment setup/teardown utilities (~330 lines)

**Complete Parity**: Bash and PowerShell unit tests provide equivalent coverage. Integration tests are bash-only as they test the system end-to-end (both bash and PowerShell launchers use same Docker infrastructure).

### Runtime Mock Inputs
- `scripts/test/fixtures/mock-secrets/config.toml`: Sample MCP configuration copied into every test repository.
- `scripts/test/fixtures/mock-secrets/gh-token.txt`: Placeholder GitHub token used for environment variables.
- Integration harness mounts these fixtures automatically; no manual setup is required. The mocks live entirely inside `/tmp` test directories, so the host environment remains untouched.

## Running Tests

### Quick Start (Development)

**During development, run unit tests** - they're fast and comprehensive:

**Bash:**
```bash
./scripts/test/test-launchers.sh
./scripts/test/test-branch-management.sh
```

**PowerShell:**
```powershell
pwsh scripts/test/test-launchers.ps1
pwsh scripts/test/test-branch-management.ps1
```

Both should pass with identical results. Time: ~1-2 minutes per file.

### Integration Tests (Before PR)

Integration tests run inside an isolated Docker-in-Docker environment for reproducibility and safety:

```bash
# Quick validation with existing/mock images (recommended for development)
./scripts/test/integration-test.sh --mode launchers

# Full build validation (run before submitting PR)
./scripts/test/integration-test.sh --mode full

# Preserve resources for debugging
./scripts/test/integration-test.sh --mode launchers --preserve
```

**How it works:** Starts a privileged `docker:25.0-dind` container, mounts your repo read-only at `/workspace`, installs required tooling (bash/git/python/jq), then runs the full integration suite against the isolated Docker daemon. All containers, images, registries, and networks are confined to the sandbox and deleted automatically when complete.

**Timing:**
- Launchers mode: ~5-10 minutes (includes DinD startup + mock image builds)
- Full mode: ~15-25 minutes (rebuilds base + all agent images)

**Requirements:**
- Docker daemon with `--privileged` container support
- ~2GB disk space for DinD container
- Port 5555 available inside the isolated environment

**Runtime mocks**: Both modes automatically mount the fixture config/tokens, spin up a disposable proxy container, and create a restricted network to verify `--network-proxy` behavior. No host credentials or proxy daemons are modified.

**Key Features**:
- ✅ No real secrets required (uses mock credentials)
- ✅ Complete isolation (local registry, test network, temp repos)
- ✅ Automatic cleanup (or `--preserve` for debugging)
- ✅ Tests real container behavior, mounting, networking, etc.

**Full mode** - Complete validation including builds:
```bash
./scripts/test/integration-test.sh --mode full

# With resource preservation for debugging
./scripts/test/integration-test.sh --mode full --preserve
```

### In CI

Tests run automatically on:
- Push to `main` or `develop` branches
- Pull requests targeting `main` or `develop`
- Changes to `host/launchers/`, `host/utils/`, `scripts/test/`, or `docker/`

See `.github/workflows/test-launchers.yml` for workflow details.

## Test Coverage

### Integration Tests

**Environment Setup**:
- Local Docker registry (isolated, no push to public)
- Test network creation and isolation
- Test repository with realistic git structure
- Mock credentials (no real secrets)

**Image Management**:
- Full mode: Build all images (base + agents) from Dockerfiles
- Launchers mode: Pull and tag existing images
- Image availability verification
- Multi-layer build dependencies

**Container Lifecycle**:
- Launcher script execution
- Container creation with proper labels
- Network connectivity and isolation
- Workspace mounting and file access
- Environment variable injection
- Multiple agents running simultaneously
- Proper cleanup on exit

**Real-World Scenarios**:
- Repository changes accessible in container
- Agent-to-agent network communication
- Label-based container discovery
- Resource cleanup (containers, networks, images, repos)

### Unit Tests

**Shared Functions**:
- `get_repo_name` / `Get-RepoName`: Repository name extraction
- `get_current_branch` / `Get-CurrentBranch`: Current branch detection
- `check_docker_running` / `Test-DockerRunning`: Docker availability
- `pull_and_tag_image` / `Update-AgentImage`: Image management
- `container_exists` / `Test-ContainerExists`: Container lookup
- `push_to_local` / `Push-ToLocal`: Auto-push functionality
- `remove_container_with_sidecars` / `Remove-ContainerWithSidecars`: Container cleanup with branch management
- `convert_to_wsl_path` (bash only): WSL path conversion
- `branch_exists` / `Test-BranchExists`: Check if branch exists in repository
- `get_unmerged_commits` / `Get-UnmergedCommits`: List commits not merged into base branch
- `remove_git_branch` / `Remove-GitBranch`: Delete a branch (with force option)
- `rename_git_branch` / `Rename-GitBranch`: Rename/archive a branch
- `create_git_branch` / `New-GitBranch`: Create new branch from specific commit

**Container Operations**:
- Container naming follows `{agent}-{repo}-{branch}` pattern
- All containers have required labels including `coding-agents.branch` and `coding-agents.repo-path`
- List and remove operations
- Label-based filtering
- Branch conflict detection and resolution
- Automatic branch cleanup on container removal
- Unmerged commit protection (branches with unmerged work are preserved)

**Edge Cases**:
- Branch name sanitization
- Multiple agents on same repository with isolated branches
- Container status tracking
- Agent branch conflicts and replacement
- Unmerged commit detection and archiving
- Force flag (-y) for automated workflows

## Test Structure

### Setup Phase
1. Create temporary test repository with git initialized
2. Configure test environment variables
3. Source shared function libraries

### Test Execution
Each test function:
1. Sets up test containers with proper labels
2. Validates expected behavior
3. Reports pass/fail with detailed output
4. Cleans up test resources

### Cleanup Phase
- Removes all test containers (labeled `coding-agents.test=true`)
- Removes temporary test repository
- Reports final pass/fail counts
- Exits with code 1 if any tests failed (CI-friendly)

## Output Format

### Success
```
✓ Test passed: Container naming convention
✓ Test passed: Container labels
✓ Test passed: list-agents command
```

### Failure
```
✗ Test failed: Expected 'copilot-test-main', got 'test-main'
```

### Summary
```
================================================================================
Test Summary
================================================================================
Total tests: 12
Passed: 12
Failed: 0
================================================================================
All tests passed!
```

## Adding New Tests

### Bash Test Template
```bash
test_new_feature() {
    local test_name="New feature description"
    
    # Setup
    # ... create test conditions
    
    # Test
    local result=$(your_command_here)
    
    # Validate
    if [[ "$result" == "$expected" ]]; then
        pass "$test_name"
    else
        fail "$test_name: Expected '$expected', got '$result'"
    fi
    
    # Cleanup
    # ... remove test resources
}
```

### PowerShell Test Template
```powershell
function Test-NewFeature {
    $TestName = "New feature description"
    
    try {
        # Setup
        # ... create test conditions
        
        # Test
        $Result = Your-Command
        
        # Validate
        Assert-Equals $Result $Expected $TestName
        
        Write-Pass $TestName
    }
    catch {
        Write-Fail "$TestName : $_"
    }
    finally {
        # Cleanup
        # ... remove test resources
    }
}
```

## Prerequisites

### Integration Tests
- Docker daemon with `--privileged` container support
- Git installed and configured
- Bash 4.0+ (Linux/macOS/WSL)
- ~5GB disk space for DinD container and builds (full mode)
- No real GitHub/API tokens required (uses mock credentials)

### Unit Tests
- **Container Runtime**: Docker (scripts require Docker Desktop or Docker Engine)
- Git installed and configured
- Bash 4.0+ or PowerShell 5.1+
- Minimal disk space

## Test Modes Explained

### Full Mode (`--mode full`)
**When to use**: 
- Before making Dockerfile changes
- Complete validation of build process
- Before submitting pull requests
- Ensuring no external dependencies

**What it does**:
1. Starts isolated Docker-in-Docker environment
2. Creates local registry inside sandbox
3. Builds base image from `docker/base/Dockerfile`
4. Builds agent images (copilot, codex, claude)
5. Runs complete test suite
6. Cleans up (or preserves with `--preserve`)

**Time**: ~15-25 minutes (includes DinD startup + all builds)

### Launchers Mode (`--mode launchers`)
**When to use**:
- Quick validation during development
- Testing launcher scripts
- When agent images already exist locally

**What it does**:
1. Starts isolated Docker-in-Docker environment
2. Creates local registry inside sandbox
3. Builds lightweight mock agent images
4. Runs complete test suite
5. Cleans up (or preserves with `--preserve`)

**Time**: ~5-10 minutes (includes DinD startup + mock builds)

## Security & Isolation

### No Real Secrets Required
- Uses mock GitHub token: `ghp_test_token_not_real_1234567890abcdef`
- Mock user: `test-user`
- Mock email: `test@example.com`
- All credentials are fake and for testing only

### Complete Isolation
- **Registry**: Local only (localhost:5555), never pushes to public
- **Network**: Isolated test network per test session
- **Repository**: Temporary directories with unique PIDs
- **Containers**: Labeled with session ID for cleanup
- **Config**: Test-specific, doesn't touch host configuration

### Resource Preservation
Use `--preserve` flag to keep resources for debugging:
```bash
./scripts/test/integration-test.sh --mode full --preserve
```

Then manually inspect:
```bash
# View test containers
docker ps -a --filter "label=coding-agents.test-session=<PID>"

# View test images
docker images | grep "localhost:5555/test-coding-agents"

# View test network
docker network ls | grep "test-coding-agents-net"

# View test repository
ls -la /tmp/test-coding-agents-repo-<PID>
```

Manual cleanup:
```bash
# Remove all test containers from session
docker ps -aq --filter "label=coding-agents.test-session=<PID>" | xargs docker rm -f

# Remove test network
docker network rm test-coding-agents-net-<PID>

# Remove test registry
docker rm -f test-registry-<PID>

# Remove test repository
rm -rf /tmp/test-coding-agents-repo-<PID>
```

## Notes

- **Unit tests** use containers labeled `coding-agents.test=true`
- **Integration tests** use `coding-agents.test-session=<PID>` for isolation
- Temporary repositories created with unique PIDs to avoid conflicts
- All resources cleaned up automatically (unless `--preserve` specified)
- Tests run independently and can be executed in any order
- CI workflow runs both unit and integration tests

## Troubleshooting

### "Docker is not running"
Ensure Docker Desktop or Docker Engine is running before executing tests.

### "Permission denied"
Make bash test script executable: `chmod +x scripts/test/test-launchers.sh`

### "Test containers still present"
Manually clean up test containers:
```bash
docker rm -f $(docker ps -aq --filter "label=coding-agents.test=true")
```

### "Temporary repository not removed"
Manually clean up (bash):
```bash
rm -rf /tmp/coding-agents-test-*
```

Manually clean up (PowerShell):
```powershell
Remove-Item "$env:TEMP\coding-agents-test-*" -Recurse -Force
```

## Contributing

When modifying launcher scripts or shared functions:
1. Run tests locally before committing
2. Add new tests for new functionality
3. Update this README if test coverage changes
4. Ensure all tests pass in CI before merging

## License

Tests are part of the CodingAgents project and follow the same license.
