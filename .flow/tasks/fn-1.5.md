# fn-1.5 Test image build and WASM functionality

## Description
Comprehensive testing using both docker sandbox (for interactive) and docker run (for CI/smoke tests).

### Test Strategy

**Interactive/Development Testing**: Use `docker sandbox run` with all 5 volumes
**CI/Smoke Testing**: Use `docker run --rm` (acceptable for non-interactive verification)

### Test Cases

#### 1. Image Build Test
```bash
./dotnet-wasm/build.sh
```

#### 2. Volume Initialization
```bash
# First time only
./dotnet-wasm/init-volumes.sh
```

#### 3. .NET SDK Verification (CI/Smoke)
```bash
# docker run is acceptable for non-interactive smoke tests
docker run --rm -u agent dotnet-wasm:latest dotnet --info
docker run --rm -u agent dotnet-wasm:latest dotnet --list-sdks
docker run --rm -u agent dotnet-wasm:latest dotnet workload list
```

#### 4. Docker Sandbox Launch Test (Interactive) - ALL 5 VOLUMES
```bash
# Source aliases
source ./dotnet-wasm/aliases.sh

# Start sandbox (uses docker sandbox run with all 5 volumes)
# Container will be named <repo>-<branch> by default
claude-sandbox-dotnet

# Or manually with ALL 5 volumes and custom name:
docker sandbox run \
  --name my-custom-sandbox \
  -v docker-vscode-server:/home/agent/.vscode-server \
  -v docker-github-copilot:/home/agent/.config/github-copilot \
  -v docker-dotnet-packages:/home/agent/.nuget/packages \
  -v docker-claude-plugins:/home/agent/.claude/plugins \
  -v docker-claude-sandbox-data:/mnt/claude-data \
  dotnet-wasm
```

#### 5. Blazor WASM Build Test (CI/Smoke)
```bash
mkdir -p /tmp/wasm-test && cd /tmp/wasm-test
docker run --rm -u agent -v $(pwd):/workspace -w /workspace \
    dotnet-wasm:latest \
    sh -c "dotnet new blazorwasm -n BlazorTestApp && cd BlazorTestApp && dotnet build"
```

#### 6. Uno Platform WASM Build Test (CI/Smoke)
```bash
mkdir -p /tmp/uno-test && cd /tmp/uno-test
docker run --rm -u agent -v $(pwd):/workspace -w /workspace \
    dotnet-wasm:latest \
    sh -c "dotnet new install Uno.Templates && \
           dotnet new unoapp -n UnoTestApp --preset=blank --platforms wasm && \
           cd UnoTestApp && \
           dotnet build UnoTestApp.Wasm/UnoTestApp.Wasm.csproj"
```

#### 7. Claude CLI Verification (CI/Smoke)
```bash
docker run --rm -u agent dotnet-wasm:latest sh -c "command -v claude && claude --version"
```

#### 8. Sandbox/ECI Detection Test
```bash
# Verify the check-sandbox.sh script runs on container startup
docker sandbox run dotnet-wasm check-sandbox.sh
# Should output sandbox detection info and ECI status
```

#### 9. Container Naming Test
```bash
# Source aliases in a git repo
cd /path/to/some-repo
source /path/to/dotnet-wasm/aliases.sh

# Start sandbox - should be named "some-repo-main" (or current branch)
claude-sandbox-dotnet

# Verify with docker sandbox ls
docker sandbox ls
# Should show container named after repo-branch

# Test custom name override
claude-sandbox-dotnet my-custom-name
docker sandbox ls | grep my-custom-name
```

### Notes

- **Interactive/dev sessions**: Use `docker sandbox run` with **all 5 volumes** for full security isolation
- **CI/smoke tests**: `docker run --rm` is acceptable for automated verification (no volumes needed)
- **Manual sandbox commands** must include all 5 volumes (match the function)
- **Container naming**: Defaults to `<repo>-<branch>`, can be overridden with first argument

## Acceptance
- [ ] Image builds without errors
- [ ] `dotnet --version` returns 10.x
- [ ] `dotnet workload list` shows `wasm-tools`
- [ ] Blazor WASM project creates and builds
- [ ] Uno Platform WASM project creates and builds
- [ ] `command -v claude && claude --version` succeeds
- [ ] `docker sandbox run ... dotnet-wasm` starts successfully
- [ ] `claude-sandbox-dotnet` function works
- [ ] Container name defaults to `<repo>-<branch>`
- [ ] Container name can be overridden with argument
- [ ] Sandbox/ECI detection script outputs correct environment info
- [ ] README documents all test procedures

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
