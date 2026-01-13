# fn-1.2 Create Dockerfile with .NET 10 SDK and WASM workloads

## Description
Create the Dockerfile for .NET 10 SDK with WASM workloads, building on `claude/Dockerfile` patterns.

### Base Image Strategy

Use `docker/sandbox-templates:claude-code` as base (inherits Claude CLI), then add .NET SDK from Microsoft packages.

### Key Components

1. **Install .NET 10 SDK** via Microsoft apt repository (Ubuntu packages)
2. **Install WASM workloads**: `dotnet workload install wasm-tools`
3. **Install Python 3** (required for WASM on Linux)
4. **Create volume mount points**:
   - `/home/agent/.vscode-server` (VS Code Server cache)
   - `/home/agent/.nuget/packages` (NuGet cache)
5. **Set environment variables**:
   - `DOTNET_CLI_TELEMETRY_OPTOUT=1`
   - `DOTNET_NOLOGO=1`
   - `CLAUDE_CODE_PATH=/usr/local/bin/claude` (for VS Code extension)

### Reference Files

- `claude/Dockerfile:1-34` - Base patterns (USER switching, npm-global, credential symlink)
- `claude/Dockerfile:18-20` - npm-global PATH pattern
- `claude/Dockerfile:29` - Credential symlink pattern

### Pattern to Follow

```dockerfile
FROM docker/sandbox-templates:claude-code

USER root

# Install .NET SDK 10
RUN apt-get update && apt-get install -y ... \
    && dotnet workload install wasm-tools \
    && apt-get clean

# Create volume mount points
RUN mkdir -p /home/agent/.vscode-server /home/agent/.nuget/packages \
    && chown -R agent:agent /home/agent/.vscode-server /home/agent/.nuget/packages

USER agent
WORKDIR /home/agent/workspace
```

### Important Notes

- .NET 10 uses Ubuntu packages (Debian discontinued)
- WASM workload install must run as root
- Maintain agent user with UID 1000 for volume compatibility
- Keep credential symlink pattern from base claude/Dockerfile
## Acceptance
- [ ] `docker build -t docker-sandbox-dotnet-wasm:latest ./dotnet-wasm/` succeeds
- [ ] `docker run --rm docker-sandbox-dotnet-wasm:latest dotnet --version` shows 10.x
- [ ] `docker run --rm docker-sandbox-dotnet-wasm:latest dotnet workload list` shows `wasm-tools`
- [ ] `docker run --rm docker-sandbox-dotnet-wasm:latest id` shows `uid=1000(agent)`
- [ ] `docker run --rm docker-sandbox-dotnet-wasm:latest python3 --version` succeeds
- [ ] Volume mount points exist: `/home/agent/.vscode-server`, `/home/agent/.nuget/packages`
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
