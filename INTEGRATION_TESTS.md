# Comprehensive Integration Test Suite

## Overview

The test suite has been upgraded from simple smoke tests to comprehensive integration tests with two modes of operation and complete isolation.

## Architecture

### Two Test Modes

#### 1. Full Mode (`--mode full`)
- **Purpose**: Complete validation including image building
- **Process**:
  1. Starts local Docker registry (localhost:5555)
  2. Builds base image from Dockerfile
  3. Builds all agent images (copilot, codex, claude)
  4. All images stay in local registry (no external push)
  5. Runs comprehensive integration tests
  6. Cleans up all resources
- **Use Case**: Pre-merge validation, Dockerfile changes, complete CI/CD
- **Time**: ~10-15 minutes

#### 2. Launchers Mode (`--mode launchers`)
- **Purpose**: Fast validation of launcher scripts
- **Process**:
  1. Starts local Docker registry
  2. Pulls existing images from registry (or uses local cache)
  3. Tags for isolated testing
  4. Runs integration tests
  5. Cleans up all resources
- **Use Case**: Quick development workflow, launcher script changes
- **Time**: ~2-5 minutes

### Security & Isolation

#### No Real Secrets Required
All tests use mock credentials:
```bash
TEST_GH_TOKEN="ghp_test_token_not_real_1234567890abcdef"
TEST_GH_USER="test-user"
TEST_GH_EMAIL="test@example.com"
```

#### Complete Isolation
- **Local Registry**: localhost:5555, never pushes to public
- **Test Network**: Unique per session (`test-coding-agents-net-<PID>`)
- **Test Repository**: Temporary git repo with realistic structure
- **Test Containers**: Session-labeled for cleanup
- **No Host Impact**: All config is test-specific

### Resource Management

#### Auto-Cleanup (Default)
All resources automatically removed after tests:
- Containers (by session label)
- Networks (by name pattern)
- Test repositories (temp directories)
- Test images (local registry namespace)
- Local registry container

#### Preserve Mode (`--preserve`)
Keep resources for debugging:
```bash
./scripts/test/integration-test.sh --mode full --preserve
```

Resources tagged with session ID for manual inspection and cleanup.

## File Structure

```
scripts/test/
├── integration-test.sh       # Main integration test suite (400+ lines)
├── test-config.sh            # Test configuration (no secrets)
├── test-config.ps1           # PowerShell test config
├── test-env.sh               # Environment setup/teardown utilities (300+ lines)
├── test-launchers.sh         # Unit tests (bash) - 386 lines
├── test-launchers.ps1        # Unit tests (PowerShell) - 388 lines
└── README.md                 # Complete documentation
```

## Test Coverage

### Integration Tests (New)

1. **Environment Setup**
   - Local registry startup and health check
   - Test network creation
   - Test repository with git structure
   - Mock credential injection

2. **Image Management**
   - Full mode: Build all images from Dockerfiles
   - Launchers mode: Pull and tag existing images
   - Image availability verification
   - Multi-stage build dependencies

3. **Container Lifecycle**
   - Launcher script execution
   - Container creation with labels
   - Network connectivity
   - Workspace mounting
   - Environment variables
   - Multiple agents simultaneously
   - Proper cleanup

4. **Real-World Scenarios**
   - File access in mounted workspace
   - Inter-container communication
   - Label-based discovery
   - Resource cleanup verification

### Unit Tests (Improved)

1. **Shared Functions**
   - Repository name extraction
   - Branch detection
   - Docker availability
   - Image management
   - Container operations
   - WSL path conversion

2. **Container Operations**
   - Naming conventions
   - Label verification
   - Management commands
   - Status tracking

3. **Edge Cases**
   - Branch sanitization
   - Multiple agents
   - Label filtering

## CI/CD Integration

### GitHub Actions Workflow

```yaml
jobs:
  # Fast unit tests (always run)
  unit-test-bash:         # 2-3 minutes
  unit-test-powershell:   # 2-3 minutes
  
  # Integration tests (launchers mode - always run)
  integration-test-launchers:  # 3-5 minutes
  
  # Integration tests (full mode - main branch only)
  integration-test-full:       # 10-15 minutes
```

**Triggers**:
- Push to main/develop
- Pull requests
- Changes to scripts/, docker/, or workflows

**Strategy**:
- PRs run unit + launchers integration (fast feedback)
- Main branch runs full integration (complete validation)

## Usage Examples

### Local Development

```bash
# Quick validation while developing
./scripts/test/integration-test.sh --mode launchers

# Full validation before merge
./scripts/test/integration-test.sh --mode full

# Debug a failing test
./scripts/test/integration-test.sh --mode full --preserve
# Then inspect: docker ps -a --filter "label=coding-agents.test-session=<PID>"

# Quick unit tests
./scripts/test/test-launchers.sh
```

### CI/CD Pipeline

```bash
# Pre-merge checks (fast)
./scripts/test/integration-test.sh --mode launchers

# Post-merge validation (complete)
./scripts/test/integration-test.sh --mode full

# Both exit with code 1 on failure (CI-friendly)
```

## Metrics

| Aspect | Unit Tests | Integration Tests (Launchers) | Integration Tests (Full) |
|--------|-----------|-------------------------------|--------------------------|
| **Time** | ~1 minute | ~3-5 minutes | ~10-15 minutes |
| **Isolation** | Partial | Complete | Complete |
| **Build Validation** | No | No | Yes |
| **Real Behavior** | Limited | Yes | Yes |
| **Secrets Required** | No | No | No |
| **CI Recommended** | Always | Always | Main branch only |

## Next Steps

1. **Run locally** to validate:
   ```bash
   ./scripts/test/integration-test.sh --mode full
   ```

2. **Review CI results** after pushing to ensure all jobs pass

3. **Use `--preserve`** flag when debugging test failures

4. **Extend tests** as needed by adding functions to `integration-test.sh`

## Troubleshooting

### Port 5555 already in use
```bash
# Find process using port
lsof -i :5555
# Stop existing registry
docker stop test-registry-*
```

### Out of disk space
```bash
# Clean up Docker
docker system prune -a --volumes
```

### Tests hanging
```bash
# Check Docker is responsive
docker ps
# Check registry is healthy
curl http://localhost:5555/v2/
```

### Manual cleanup needed
```bash
# Clean all test resources
docker ps -aq --filter "label=coding-agents.test=true" | xargs docker rm -f
docker network ls | grep test-coding-agents | awk '{print $1}' | xargs docker network rm
rm -rf /tmp/test-coding-agents-*
```

## Files Created/Modified

### New Files
1. `scripts/test/integration-test.sh` - Main integration test suite
2. `scripts/test/test-config.sh` - Test configuration (bash)
3. `scripts/test/test-config.ps1` - Test configuration (PowerShell)
4. `scripts/test/test-env.sh` - Environment utilities (bash)
5. `INTEGRATION_TESTS.md` - This documentation

### Modified Files
1. `scripts/test/README.md` - Updated with integration test docs
2. `.github/workflows/test-launchers.yml` - Added integration test jobs
3. `scripts/test/test-launchers.sh` - Refactored, better factored
4. `scripts/test/test-launchers.ps1` - Refactored, better factored

## Summary

The test suite has been transformed from basic smoke tests into a comprehensive integration testing framework that:

- **Validates the entire system** end-to-end
- **Requires no real secrets** (mock credentials only)
- **Provides complete isolation** (local registry, networks, repos)
- **Offers two modes** (fast launchers, complete full)
- **Includes auto-cleanup** (with preserve option for debugging)
- **Integrates with CI/CD** (different jobs for different scenarios)
- **Is production-ready** for validating changes before deployment

This ensures that launcher scripts, images, and the entire container ecosystem work correctly in realistic scenarios without impacting the host system or requiring actual credentials.
