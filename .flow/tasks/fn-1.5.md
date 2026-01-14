# fn-1.5 Test image build and WASM functionality

## Description
Comprehensive testing using both docker sandbox (for interactive) and docker run (for CI/smoke tests).

### Test Strategy

**Interactive/Development Testing**: Use `csd` alias (wraps `docker sandbox run`)
**CI/Smoke Testing**: Use `docker run --rm` (acceptable for non-interactive verification)

### Test Cases

#### 1. Image Build Test
```bash
./dotnet-sandbox/build.sh
```

#### 2. .NET SDK Verification (CI/Smoke)
```bash
docker run --rm -u agent dotnet-sandbox:latest dotnet --info
docker run --rm -u agent dotnet-sandbox:latest dotnet --version | grep -E '^10\.'
docker run --rm -u agent dotnet-sandbox:latest dotnet workload list
```

#### 3. Node.js Verification (CI/Smoke)
```bash
# Use bash -lc for nvm-installed node
docker run --rm -u agent dotnet-sandbox:latest bash -lc "node --version"
docker run --rm -u agent dotnet-sandbox:latest bash -lc "nvm --version"
# Direct symlink access
docker run --rm -u agent dotnet-sandbox:latest /usr/local/bin/node --version
```

#### 4. Docker Sandbox Launch Test (Interactive)
```bash
# Source aliases
source ./dotnet-sandbox/aliases.sh

# Start sandbox - csd handles volume creation and sandbox enforcement
csd

# Volumes are created automatically by csd
```

#### 5. Blazor WASM Build Test (CI/Smoke)
```bash
mkdir -p /tmp/wasm-test && cd /tmp/wasm-test
docker run --rm -u agent -v $(pwd):/workspace -w /workspace \
    dotnet-sandbox:latest \
    sh -c "dotnet new blazorwasm -n BlazorTestApp && cd BlazorTestApp && dotnet build"
```

#### 6. Uno Platform WASM Build Test (CI/Smoke)
```bash
mkdir -p /tmp/uno-test && cd /tmp/uno-test
docker run --rm -u agent -v $(pwd):/workspace -w /workspace \
    dotnet-sandbox:latest \
    sh -c "dotnet new install Uno.Templates && \
           dotnet new unoapp -n UnoTestApp --preset=blank --platforms wasm && \
           cd UnoTestApp && \
           dotnet build UnoTestApp.Wasm/UnoTestApp.Wasm.csproj"
```

#### 7. uno-check Verification (Interactive)
```bash
# Run inside sandbox (not during build - moved here per spec)
csd
# Inside container:
uno-check --fix --non-interactive || echo "uno-check reported issues"
```

#### 8. Claude CLI Verification (CI/Smoke)
```bash
docker run --rm -u agent dotnet-sandbox:latest sh -c "command -v claude && claude --version"
docker run --rm -u agent dotnet-sandbox:latest ls -la /home/agent/.claude/.credentials.json
```

#### 9. Sandbox Enforcement Test
```bash
# Verify csd blocks with clear message when sandbox unavailable
# This test requires probing detection logic, not breaking Docker

# Test detection by probing CLI:
docker sandbox --help 2>&1  # Should show help if supported

# csd should block if above fails
csd  # Should fail with actionable message if sandbox unavailable
```

#### 10. Container Naming Test
```bash
# Source aliases in a git repo
cd /path/to/some-repo
source /path/to/dotnet-sandbox/aliases.sh

# Start sandbox - should be named "some-repo-main" (lowercase, sanitized)
csd
docker sandbox ls  # Verify name

# Test restart flag
csd --restart  # Should recreate container

# Test detached HEAD
git checkout --detach
csd  # Should use "detached-<sha>" pattern
```

#### 11. Port Forwarding Test
```bash
# Start a Blazor WASM app inside sandbox
csd
# Inside container:
dotnet new blazorwasm -o /tmp/testapp
cd /tmp/testapp
dotnet run --urls http://0.0.0.0:5000

# From host:
curl http://localhost:5000  # Should get response
```

### Notes

- **Interactive/dev sessions**: Use `csd` for full security isolation with volumes
- **CI/smoke tests**: `docker run --rm` is acceptable (no sandbox enforcement in image)
- **Container naming**: Defaults to `<repo>-<branch>`, use `--restart` to recreate
- **uno-check**: Run interactively, not during build (per spec)
- **Sandbox enforcement test**: Probe CLI capabilities, not "break your Docker"

## Acceptance
- [ ] Image builds without errors
- [ ] `dotnet --version | grep -E '^10\.'` succeeds
- [ ] `dotnet workload list` shows `wasm-tools`
- [ ] `bash -lc "node --version"` returns LTS version
- [ ] `bash -lc "nvm --version"` works
- [ ] `/usr/local/bin/node --version` works (symlink)
- [ ] Blazor WASM project creates and builds
- [ ] Uno Platform WASM project creates and builds
- [ ] `uno-check` passes when run interactively in sandbox
- [ ] `command -v claude && claude --version` succeeds
- [ ] Claude credentials symlink exists
- [ ] `csd` starts sandbox with all volumes
- [ ] `csd` auto-attaches if container with same name running
- [ ] `csd --restart` recreates container
- [ ] Container name follows `<repo>-<branch>` pattern (sanitized, lowercase, max 63)
- [ ] Falls back to directory name outside git repo
- [ ] `csd` blocks with actionable message if sandbox unavailable
- [ ] Ports 5000-5010 accessible from host
- [ ] README documents all test procedures

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
