# fn-1.5 Test image build and WASM functionality

## Description
Comprehensive testing of the complete setup: image build, WASM functionality, VS Code integration, security hardening, and container-internal testing.

### Test Cases

#### 1. Image Build Test
```bash
./dotnet-wasm/build.sh
```

#### 2. .NET SDK Verification
```bash
docker run --rm docker-sandbox-dotnet-wasm:latest dotnet --info
docker run --rm docker-sandbox-dotnet-wasm:latest dotnet --list-sdks
```

#### 3. WASM Workload Verification
```bash
docker run --rm docker-sandbox-dotnet-wasm:latest dotnet workload list
```

#### 4. Blazor WASM Build Test
```bash
mkdir -p /tmp/wasm-test && cd /tmp/wasm-test
docker run --rm -v $(pwd):/workspace -w /workspace \
    docker-sandbox-dotnet-wasm:latest \
    sh -c "dotnet new blazorwasm -n TestApp && cd TestApp && dotnet build"
```

#### 5. User/Permission Verification
```bash
docker run --rm docker-sandbox-dotnet-wasm:latest id
# Expected: uid=1000(agent) gid=1000(agent)
```

#### 6. Volume Persistence Test
```bash
# First run - install a package
docker run --rm \
    -v docker-dotnet-packages:/home/agent/.nuget/packages \
    docker-sandbox-dotnet-wasm:latest \
    dotnet add package Newtonsoft.Json --version 13.0.3

# Second run - verify package cached
docker run --rm \
    -v docker-dotnet-packages:/home/agent/.nuget/packages \
    docker-sandbox-dotnet-wasm:latest \
    ls /home/agent/.nuget/packages/newtonsoft.json
```

#### 7. Claude CLI Verification
```bash
docker run --rm docker-sandbox-dotnet-wasm:latest which claude
docker run --rm docker-sandbox-dotnet-wasm:latest claude --version
```

#### 8. Podman Rootless Test
```bash
docker run --rm -it docker-sandbox-dotnet-wasm:latest podman run --rm hello-world
docker run --rm docker-sandbox-dotnet-wasm:latest podman info | grep rootless
```

#### 9. Security Hardening Test
```bash
# Run with security flags
./dotnet-wasm/run.sh

# Inside container, verify restrictions
cat /proc/self/status | grep Cap
# Should show dropped capabilities
```

#### 10. VS Code DevContainer Test (Manual)
```bash
# Test with VS Code Stable
code ./dotnet-wasm
# Select "Reopen in Container"

# Test with VS Code Insiders
code-insiders ./dotnet-wasm
# Select "Reopen in Container"
```

#### 11. GitHub Copilot Volume Test
```bash
# Sync from host
./dotnet-wasm/sync-vscode-data.sh

# Verify data synced
docker run --rm \
    -v docker-github-copilot:/home/agent/.config/github-copilot:ro \
    alpine ls /home/agent/.config/github-copilot/
```

### Notes

- Clean up test artifacts after testing
- Document any issues found in epic notes
- Some tests require manual VS Code interaction
- Podman test may require additional kernel features
## Acceptance
- [ ] Image builds without errors
- [ ] `dotnet --version` returns 10.x
- [ ] `dotnet workload list` shows `wasm-tools` installed
- [ ] Blazor WASM project creates and builds successfully
- [ ] Container runs as `agent` user (UID 1000)
- [ ] NuGet package cache persists across container restarts
- [ ] `claude --version` works inside container
- [ ] `podman run --rm hello-world` succeeds inside container
- [ ] `podman info` shows rootless mode enabled
- [ ] Container starts with security restrictions (cap-drop, no-new-privileges)
- [ ] VS Code Stable can open devcontainer
- [ ] VS Code Insiders can open devcontainer
- [ ] GitHub Copilot auth persists after container rebuild
- [ ] sync-vscode-data.sh successfully syncs host data
- [ ] All test cases documented pass
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
