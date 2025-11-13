# Test Suite

Comprehensive automated testing for the CodingAgents project, including unit tests and integration tests.

## Overview

### Integration Tests (Recommended)

Full end-to-end testing with two modes:

**Full Mode**: Builds all images in isolated environment
- Creates local Docker registry (no push to public registry)
- Builds base image and all agent images from Dockerfiles
- Tests against freshly built images
- Complete isolation - no external dependencies

**Launchers Mode**: Tests against existing images
- Pulls images from registry (or uses local)
- Tags for isolated testing
- Tests launcher scripts and functionality
- Faster execution

### Unit Tests (Legacy)

Quick validation of launcher scripts and shared functions:
- Container naming conventions
- Label verification
- Management commands
- Shared function validation

## Test Files

### Integration Tests
- **`integration-test.sh`**: Comprehensive bash integration test suite
- **`test-config.sh`**: Test configuration (no real secrets)
- **`test-env.sh`**: Environment setup/teardown utilities

### Unit Tests
- **`test-launchers.sh`**: Bash unit test suite (386 lines)
- **`test-launchers.ps1`**: PowerShell unit test suite (388 lines)

## Running Tests

### Integration Tests (Recommended)

**Full mode** - Build and test everything in isolation:
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

### Unit Tests (Quick Validation)

**Linux/macOS/WSL:**
```bash
chmod +x scripts/test/test-launchers.sh
./scripts/test/test-launchers.sh
```

**Windows PowerShell:**
```powershell
.\scripts\test\test-launchers.ps1
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
- `remove_container_with_sidecars` / `Remove-ContainerWithSidecars`: Container cleanup
- `convert_to_wsl_path` (bash only): WSL path conversion

**Container Operations**:
- Container naming follows `{agent}-{repo}-{branch}` pattern
- All containers have 4 required labels
- List and remove operations
- Label-based filtering

**Edge Cases**:
- Branch name sanitization
- Multiple agents on same repository
- Container status tracking

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
- Docker installed and running (with BuildKit support for full mode)
- Git installed and configured
- Bash 4.0+ (Linux/macOS/WSL)
- Sufficient disk space for building images (full mode: ~5GB)
- Port 5555 available for local registry
- No real GitHub/API tokens required (uses mock credentials)

### Unit Tests
- Docker installed and running
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
Ensure Docker Desktop or Docker daemon is running before executing tests.

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
