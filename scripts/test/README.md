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

## Test Files

### Unit Tests
- **`test-launchers.sh`**: Bash launcher unit tests (~390 lines)
- **`test-launchers.ps1`**: PowerShell launcher unit tests (~460 lines)  
  Tests: container naming, labels, image operations, WSL paths, branch sanitization
  
- **`test-branch-management.sh`**: Bash branch management tests (~430 lines)
- **`test-branch-management.ps1`**: PowerShell branch management tests (~512 lines)  
  Tests: branch operations, conflict detection, archiving, cleanup, unmerged commits

### Integration Tests (Bash Only)
- **`integration-test.sh`**: Full system integration tests (~450 lines)
- **`test-config.sh`**: Test configuration with mock credentials
- **`test-env.sh`**: Environment setup/teardown utilities (~300 lines)

**Complete Parity**: Bash and PowerShell unit tests provide equivalent coverage. Integration tests are bash-only as they test the system end-to-end (both bash and PowerShell launchers use same Docker infrastructure).

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

**Launchers mode** - Fast validation with existing images:
```bash
# Linux/macOS/WSL
chmod +x scripts/test/integration-test.sh
./scripts/test/integration-test.sh --mode full

# With resource preservation for debugging
./scripts/test/integration-test.sh --mode full --preserve
```

**Launchers mode** - Test with existing images:
```bash
# Linux/macOS/WSL
./scripts/test/integration-test.sh --mode launchers

# Faster, uses images from registry or local cache
```

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
- Changes to `scripts/launchers/`, `scripts/utils/`, `scripts/test/`, or `docker/`

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
- **Container Runtime**: Docker or Podman (scripts auto-detect)
  - Docker: Requires BuildKit support for full mode
  - Podman: Native support for BuildKit-compatible builds
- Git installed and configured
- Bash 4.0+ (Linux/macOS/WSL)
- Sufficient disk space for building images (full mode: ~5GB)
- Port 5555 available for local registry
- No real GitHub/API tokens required (uses mock credentials)

### Unit Tests
- **Container Runtime**: Docker or Podman (scripts auto-detect)
- Git installed and configured
- Bash 4.0+ or PowerShell 5.1+
- Minimal disk space

## Test Modes Explained

### Full Mode (`--mode full`)
**When to use**: 
- Before making Dockerfile changes
- Complete validation of build process
- CI/CD pipeline for image building
- Ensuring no external dependencies

**What it does**:
1. Starts local Docker registry on localhost:5555
2. Builds base image from `docker/base.Dockerfile`
3. Pushes base to local registry
4. Builds agent images (copilot, codex, claude) using local base
5. Runs full test suite against built images
6. Cleans up (or preserves with `--preserve`)

**Time**: ~10-15 minutes (depending on build cache)

### Launchers Mode (`--mode launchers`)
**When to use**:
- Testing launcher scripts only
- Quick validation
- Local development workflow
- When images already exist

**What it does**:
1. Starts local Docker registry on localhost:5555
2. Pulls existing images from registry (or uses local)
3. Tags for testing (no modifications)
4. Runs test suite against tagged images
5. Cleans up (or preserves with `--preserve`)

**Time**: ~2-5 minutes

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
Ensure Docker or Podman is running before executing tests. Scripts automatically detect which container runtime is available.

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
