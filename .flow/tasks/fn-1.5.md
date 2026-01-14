# fn-1.5 Test image build and WASM functionality

## Description

Comprehensive testing of the dotnet-sandbox image using Docker-in-Docker (DinD) for CI-compatible tests and manual verification for sandbox-specific features.

### Test Strategy

**CI/Automated Testing (DinD):** Tests that use standard `docker build` and `docker run` commands can run in a DinD environment.

**Manual Testing (Docker Desktop required):** Tests that verify `docker sandbox` features require Docker Desktop 4.50+ on the host.

---

## Part A: CI-Compatible Tests (DinD)

These tests can run in a containerized environment using Docker-in-Docker.

### DinD Setup

Start a DinD environment with workspace mounted:
```bash
# Start DinD with current directory mounted
docker run --privileged --name dind -d \
  -e DOCKER_TLS_CERTDIR="" \
  -v "$(pwd):/workspace:ro" \
  docker:dind --storage-driver overlay2

# Wait for daemon to be ready
sleep 5

# Verify DinD is working
docker exec dind docker info
```

### Test A1: Image Build
```bash
# Build inside DinD (workspace already mounted at /workspace)
docker exec dind docker build -t dotnet-sandbox:latest /workspace/dotnet-sandbox
```

### Test A2: .NET SDK Verification
```bash
docker exec dind docker run --rm -u agent dotnet-sandbox:latest dotnet --info
docker exec dind docker run --rm -u agent dotnet-sandbox:latest dotnet --version | grep -E '^10\.'
docker exec dind docker run --rm -u agent dotnet-sandbox:latest dotnet workload list
```

### Test A3: Node.js Verification
```bash
# Use bash -lc for nvm-installed node
docker exec dind docker run --rm -u agent dotnet-sandbox:latest bash -lc "node --version"
docker exec dind docker run --rm -u agent dotnet-sandbox:latest bash -lc "nvm --version"
# Direct symlink access
docker exec dind docker run --rm -u agent dotnet-sandbox:latest /usr/local/bin/node --version
```

### Test A4: Blazor WASM Build
```bash
docker exec dind docker run --rm -u agent -w /tmp \
    dotnet-sandbox:latest \
    sh -c "dotnet new blazorwasm -n BlazorTestApp && cd BlazorTestApp && dotnet build"
```

### Test A5: Uno Platform WASM Build
```bash
# Note: requires internet access for NuGet restore
docker exec dind docker run --rm -u agent -w /tmp \
    dotnet-sandbox:latest \
    sh -c "dotnet new install Uno.Templates && \
           dotnet new unoapp -n UnoTestApp --preset=blank --platforms wasm && \
           cd UnoTestApp && \
           dotnet build UnoTestApp.Wasm/UnoTestApp.Wasm.csproj"
```

### Test A6: Claude CLI Verification
```bash
docker exec dind docker run --rm -u agent dotnet-sandbox:latest sh -c "command -v claude && claude --version"
docker exec dind docker run --rm -u agent dotnet-sandbox:latest ls -la /home/agent/.claude/.credentials.json
```

### DinD Cleanup
```bash
docker stop dind && docker rm dind
```

---

## Part B: Sandbox-Specific Tests (Manual)

These tests require Docker Desktop 4.50+ with `docker sandbox` support. They cannot run in DinD because `docker sandbox` is a Docker Desktop-specific feature.

**Run these on a host with Docker Desktop installed.**

### Test B1: Docker Sandbox Launch
```bash
source ./dotnet-sandbox/aliases.sh
csd  # Should start sandbox with volumes
```

### Test B2: uno-check Verification (Interactive)
```bash
csd
# Inside container - install uno-check first (not pre-installed):
dotnet tool install -g uno.check
uno-check --fix --non-interactive || echo "uno-check reported issues"
```

### Test B3: Sandbox Enforcement
```bash
# Verify csd blocks with clear message when sandbox unavailable
docker sandbox --help 2>&1  # Check if supported
csd  # Should fail with actionable message if sandbox unavailable
```

### Test B4: Container Naming
```bash
cd /path/to/some-repo
source /path/to/dotnet-sandbox/aliases.sh
csd  # Should be named "<repo>-<branch>"
docker sandbox ls  # Verify name
csd --restart  # Should recreate container
```

### Test B5: Port Forwarding (CONDITIONAL)
```bash
# First, detect if sandbox supports port publishing
docker sandbox run --help | grep -q '\-p\|--publish' && PORTS_SUPPORTED=true || PORTS_SUPPORTED=false

if $PORTS_SUPPORTED; then
  # Test via sandbox
  csd
  # Inside container:
  dotnet new blazorwasm -o /tmp/testapp && cd /tmp/testapp
  dotnet run --urls http://0.0.0.0:5000
  # From host:
  curl http://localhost:5000
else
  # Verify via plain docker run instead:
  echo "Port publishing not supported by sandbox, testing via docker run"
  docker run --rm -d -p 5000:5000 --name port-test -u agent dotnet-sandbox:latest \
    bash -c "cd /tmp && dotnet new blazorwasm -o testapp && cd testapp && dotnet run --urls http://0.0.0.0:5000"
  sleep 60  # Wait for build and startup
  curl http://localhost:5000 || echo "Port test requires longer startup time"
  docker stop port-test 2>/dev/null || true
fi
```

---

## Implementation Notes

### DinD Approach Selected

- **Method:** Privileged docker:dind container with workspace volume mount
- **Why:** Simplest setup, sufficient for CI smoke tests
- **Security:** Acceptable for testing (tests run trusted code)
- **Alternative considered:** Sysbox (more secure but requires host installation)

### Limitations

- `docker sandbox` commands not available in DinD (Docker Desktop feature)
- Volume names inside DinD are isolated from host
- Port forwarding tests need host-level Docker Desktop
- Uno tests require internet access for NuGet package restore

### CI Integration (future)

For GitHub Actions or similar CI:
```yaml
services:
  docker:
    image: docker:dind
    options: --privileged
    env:
      DOCKER_TLS_CERTDIR: ""
    volumes:
      - ${{ github.workspace }}:/workspace:ro
```

## Part C: Implementation Compliance Tests

These tests verify the implementation matches the spec (identified in plan review).

### Test C1: Dockerfile Workload Commands
```bash
# Verify wasm-tools and wasm-tools-net9 are in SEPARATE RUN commands
# wasm-tools should be required (hard fail)
# wasm-tools-net9 should be optional (fail-open with || echo)
grep -n "RUN.*dotnet workload install" dotnet-sandbox/Dockerfile
# Expected: Two separate RUN lines, one for wasm-tools, one for wasm-tools-net9 with || echo
```



### Test C3: csd Label Support Check
```bash
# Verify csd checks for label support before using labels
grep -E "label.*help|--help.*label" dotnet-sandbox/aliases.sh
# Expected: Code that probes docker sandbox run --help for --label support
```

### Test C4: csd Volume Permission Fixing
```bash
# Verify permission fixing includes docker-claude-sandbox-data
grep -A 20 "_csd_ensure_volumes\|_csd_fix_permissions" dotnet-sandbox/aliases.sh | grep "docker-claude-sandbox-data\|claude-data"
# Expected: docker-claude-sandbox-data is included in chown operations
```

### Test C5: csd Helper Image Fallback
```bash
# Verify fallback to base image if dotnet-sandbox:latest not available
grep -E "docker/sandbox-templates:claude-code|helper.*image|fallback.*image" dotnet-sandbox/aliases.sh
# Expected: Code that falls back to docker/sandbox-templates:claude-code if dotnet-sandbox not built
```

### Test C6: Blocking Error Messages
```bash
# Verify blocking errors include raw docker output
grep -B 5 -A 10 "sandbox.*unavailable\|not available\|block" dotnet-sandbox/aliases.sh | grep -E "output|stderr|\$\("
# Expected: Raw docker output included in error messages
```

### Test C7: Collision Error Details
```bash
# Verify collision errors include expected vs actual identity
grep -B 5 -A 10 "collision\|identity\|mismatch\|foreign" dotnet-sandbox/aliases.sh | grep -E "expected|actual|observed"
# Expected: Error messages include expected identity, actual value
```

### Test C8: README sync-plugins Clarification
```bash
# Verify README clarifies sync-plugins does NOT sync credentials
grep -i "credentials" dotnet-sandbox/README.md | grep -i "not\|does not\|doesn't"
# Expected: Clear statement that sync-plugins does NOT sync credentials
```

### Test C9: Container Name Fallback
```bash
# Verify fallback uses sandbox-<dirname>, not sandbox-container
grep -E "fallback|empty.*sanitiz|sandbox-" dotnet-sandbox/aliases.sh | grep -v "sandbox-container"
# Expected: Uses sandbox-$dirname pattern, NOT sandbox-container
```

---

## Acceptance

### Part A: CI-Compatible (DinD)

- [ ] DinD environment starts with workspace mounted
- [ ] Image builds without errors inside DinD
- [ ] `dotnet --version | grep -E '^10\.'` succeeds
- [ ] `dotnet workload list` shows `wasm-tools`
- [ ] `bash -lc "node --version"` returns LTS version
- [ ] `bash -lc "nvm --version"` works
- [ ] `/usr/local/bin/node --version` works (symlink)
- [ ] Blazor WASM project creates and builds
- [ ] Uno Platform WASM project creates and builds (requires internet)
- [ ] `command -v claude && claude --version` succeeds
- [ ] Claude credentials symlink exists

### Part B: Sandbox-Specific (Manual on Docker Desktop)

- [ ] `csd` starts sandbox with all volumes
- [ ] `csd` auto-attaches if container with same name running
- [ ] `csd --restart` recreates container
- [ ] Container name follows `<repo>-<branch>` pattern
- [ ] Falls back to directory name outside git repo
- [ ] `csd` blocks with actionable message if sandbox unavailable
- [ ] `uno-check` passes when installed (`dotnet tool install -g uno.check`) and run interactively
- [ ] Port forwarding works (via sandbox if supported, or via `docker run -p` fallback)

### Part C: Implementation Compliance

- [x] Dockerfile: wasm-tools and wasm-tools-net9 in separate RUN commands
- [x] Dockerfile: wasm-tools-net9 uses fail-open pattern (`|| echo`)
- [x] csd: Checks label support before using `--label`
- [x] csd: Falls back to image name verification if labels not supported
- [x] csd: Chowns ALL volumes including docker-claude-sandbox-data to uid 1000
- [x] csd: Uses base image as fallback for permission fixing if dotnet-sandbox not built
- [x] csd: Blocking errors include raw docker output
- [x] csd: Collision errors include expected vs actual identity
- [x] README: Clarifies sync-plugins does NOT sync credentials
- [x] csd: Container name fallback uses `sandbox-<dirname>` pattern

## Done summary
# fn-1.5: Test image build and WASM functionality

## Summary

Completed Part C (Implementation Compliance) tests and fixed all compliance issues. Parts A (DinD) and B (Sandbox) tests could not be executed as Docker daemon is not available in this environment.

## Test Results

### Part A: CI-Compatible (DinD) - SKIPPED
- Requires Docker daemon (not available)
- Tests: Image build, .NET SDK, Node.js, Blazor WASM, Uno WASM, Claude CLI

### Part B: Sandbox-Specific - SKIPPED
- Requires Docker Desktop 4.50+ with sandbox feature
- Tests: csd command, uno-check, container naming, port forwarding

### Part C: Implementation Compliance - PASS (8/8)

| Test | Status | Fix Applied |
|------|--------|-------------|
| C1: Workload separation | PASS | Split wasm-tools and wasm-tools-net9 into separate RUN commands |
| C3: Label support check | PASS | Probe sandbox_help for --label support before using |
| C4: Volume permissions | PASS | Chown ALL volumes including docker-claude-sandbox-data |
| C5: Fallback image | PASS | Use base image for permission fix if dotnet-sandbox not built |
| C6: Blocking errors | PASS | Already implemented |
| C7: Collision details | PASS | Show expected vs actual label and image in errors |
| C8: README clarification | PASS | Clarified sync-plugins does NOT sync credentials |
| C9: Fallback pattern | PASS | Use sandbox-<dirname> pattern, not sandbox-container |

## Files Modified

1. **dotnet-sandbox/Dockerfile** - Split workload installation into separate RUN commands
2. **dotnet-sandbox/aliases.sh** - Multiple fixes for csd wrapper
3. **dotnet-sandbox/README.md** - Clarified sync-plugins credential handling

## Notes

- Parts A and B require Docker runtime which is not available in this environment
- Part C fixes address implementation issues from prerequisite tasks
- The image and sandbox functionality should be tested manually when Docker is available
## Evidence
- Commits:
- Tests:
- PRs: