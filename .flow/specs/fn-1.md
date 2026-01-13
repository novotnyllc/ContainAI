# .NET 10 WASM Docker Sandbox with DevContainer Support

## Overview

Create a Docker image template for a development sandbox that includes .NET SDK 10 with WASM workloads, building on the existing `claude/Dockerfile` patterns. The template supports VS Code (Stable + Insiders) devcontainers with shared volume caching for VS Code Server, Claude extension, GitHub Copilot auth, and C# Dev Kit data. Security hardening and container-internal testing capabilities are core requirements.

## Scope

**In Scope:**
- New `dotnet-wasm/` directory with Dockerfile extending existing patterns
- .NET SDK 10 (floating version) with `wasm-tools` workload pre-installed
- `.devcontainer/devcontainer.json` supporting both VS Code Stable and Insiders
- Named volumes for all persistent data:
  - VS Code Server cache (`~/.vscode-server`)
  - GitHub Copilot auth (`~/.config/github-copilot`, globalStorage)
  - C# Dev Kit data (OmniSharp, extension storage)
  - NuGet package cache
- Claude extension configured to use local `claude` CLI
- Helper scripts following existing `sync-plugins.sh` patterns
- VS Code data pre-population script (like sync-plugins.sh)
- Security hardening for untrusted code execution
- Container-internal testing strategy (Sysbox/Podman-in-container)
- Documentation for usage

**Out of Scope (Phase 2):**
- OpenAI Codex CLI integration (future)
- Gemini CLI integration (future)
- Network firewall scripts (can be added later)

## Approach

### Architecture Decisions

1. **Base Image Strategy**: Layer on top of `docker/sandbox-templates:claude-code` to inherit existing Claude setup, then add .NET SDK 10 from Microsoft's Ubuntu packages (Debian images discontinued for .NET 10).

2. **User Convention**: Maintain `agent` user with UID 1000 for volume compatibility with existing `docker-claude-*` volumes.

3. **Version Strategy**: Use floating versions (e.g., `10.0` not `10.0.100`) for .NET SDK to automatically get updates.

4. **VS Code Support**: Support both VS Code Stable and Insiders via devcontainer.json.

5. **Volume Strategy**:
   | Volume | Mount Point | Purpose |
   |--------|-------------|---------|
   | `docker-vscode-server` | `/home/agent/.vscode-server` | VS Code Server cache |
   | `docker-vscode-data` | `/home/agent/.config/Code` | VS Code user data (globalStorage, workspaceStorage) |
   | `docker-github-copilot` | `/home/agent/.config/github-copilot` | Copilot CLI auth |
   | `docker-dotnet-packages` | `/home/agent/.nuget/packages` | NuGet package cache |
   | `docker-omnisharp` | `/home/agent/.omnisharp` | OmniSharp/C# Dev Kit |
   | `docker-claude-plugins` | `/home/agent/.claude/plugins` | (existing) Claude plugins |
   | `docker-claude-sandbox-data` | `/mnt/claude-data` | (existing) Claude credentials |

6. **devcontainer.json Strategy**: Include in image AND provide as copyable template. Image includes default config; users can override by copying to their project.

7. **Container-Internal Testing**: Use Podman (rootless) for testing within container. Sysbox requires host runtime installation; Podman can run nested containers without host changes.

8. **Security Hardening**:
   - Run as non-root user (agent, UID 1000)
   - Drop all capabilities except required ones
   - Read-only root filesystem with tmpfs for writes
   - seccomp profile (Docker default + custom restrictions)
   - No access to host Docker socket
   - ECI already enabled on host (user confirmed)

### Key Patterns from Existing Code

- `claude/Dockerfile:18-20`: npm-global path pattern at `~/.npm-global`
- `claude/Dockerfile:29`: Credential symlink from `/mnt/claude-data/`
- `sync-plugins.sh:21-23`: Volume naming convention
- `sync-plugins.sh:108-114`: Volume mount pattern using alpine for file operations
- `update-claude-sandbox.sh:44-59`: Build and tag pattern

### Dependencies

- Microsoft .NET 10 SDK packages (Ubuntu Noble)
- Python 3 (required for WASM workloads on Linux)
- Podman (for container-internal testing)
- VS Code Stable or Insiders on host machine
- Existing `docker-claude-*` volumes

## Quick Commands

```bash
# Build the image
docker build -t docker-sandbox-dotnet-wasm:latest ./dotnet-wasm/

# Run with devcontainer (VS Code Stable)
code --folder-uri vscode-remote://dev-container+$(pwd | xxd -p)/home/agent/workspace

# Run with devcontainer (VS Code Insiders)
code-insiders --folder-uri vscode-remote://dev-container+$(pwd | xxd -p)/home/agent/workspace

# Smoke test - verify .NET and WASM
docker run --rm docker-sandbox-dotnet-wasm:latest dotnet --list-sdks
docker run --rm docker-sandbox-dotnet-wasm:latest dotnet workload list

# Test container-internal Docker (Podman)
docker run --rm -it docker-sandbox-dotnet-wasm:latest podman run --rm hello-world

# Sync VS Code data from host
./dotnet-wasm/sync-vscode-data.sh

# Test WASM build capability
docker run --rm -v $(pwd):/workspace docker-sandbox-dotnet-wasm:latest \
  sh -c "cd /workspace && dotnet new blazorwasm -n TestWasm && cd TestWasm && dotnet build"
```

## Acceptance Criteria

- [ ] `docker build` succeeds for `dotnet-wasm/Dockerfile`
- [ ] Container has .NET SDK 10.x installed (`dotnet --version`)
- [ ] WASM workload is installed (`dotnet workload list` shows `wasm-tools`)
- [ ] VS Code Stable can open project in devcontainer
- [ ] VS Code Insiders can open project in devcontainer
- [ ] VS Code Server is cached in named volume (persists across container rebuilds)
- [ ] GitHub Copilot auth persists across container rebuilds
- [ ] C# Dev Kit functions with persisted OmniSharp data
- [ ] Claude extension works in VS Code and uses local `claude` CLI
- [ ] Agent user has UID 1000 (compatible with existing volumes)
- [ ] Can create and build a Blazor WASM project
- [ ] Container can build Docker images internally (Podman)
- [ ] Container runs with security hardening (no --privileged, capabilities dropped)
- [ ] sync-vscode-data.sh pre-populates VS Code volumes from host

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| .NET 10 not GA yet | Build may use preview SDK | Use floating version; auto-updates when GA |
| Ubuntu vs Debian base conflict | Package manager issues | Use multi-stage or apt sources carefully |
| Podman rootless complexity | Testing may fail | Test thoroughly; document workarounds |
| GitHub Copilot token expiry | Auth breaks | Document re-auth process |
| Security restrictions break functionality | Extensions/tools fail | Test each capability; allow specific exceptions |

## Security Considerations

1. **Container Isolation**: ECI enabled on host, no docker socket access
2. **User Namespaces**: Run as UID 1000 (agent), not root
3. **Capability Dropping**: Drop all caps, add only required ones
4. **Read-only Root**: Use tmpfs for `/tmp`, named volumes for data
5. **Network**: Container can access network (required for NuGet, VS Code)
6. **Testing**: Podman rootless for internal builds (no host Docker access)

## References

- Existing Dockerfile: `claude/Dockerfile`
- Volume patterns: `claude/sync-plugins.sh:21-23`
- Reference devcontainer: https://github.com/centminmod/claude-code-devcontainers/
- .NET 10 Docker images: https://mcr.microsoft.com/en-us/product/dotnet/sdk/about
- WASM workloads: https://learn.microsoft.com/en-us/aspnet/core/blazor/webassembly-build-tools-and-aot
- VS Code Dev Containers: https://containers.dev/implementors/json_reference/
- Claude Code extension: https://marketplace.visualstudio.com/items?itemName=anthropic.claude-code
- GitHub Copilot storage: `~/.config/github-copilot/hosts.json`
- VS Code globalStorage: `~/.config/Code/User/globalStorage/`
- Sysbox: https://github.com/nestybox/sysbox
- Podman rootless: https://github.com/containers/podman/blob/main/docs/tutorials/rootless_tutorial.md
- Docker ECI: https://docs.docker.com/enterprise/security/hardened-desktop/enhanced-container-isolation/

## Resolved Questions

1. **Version pinning**: Use floating versions (10.0) for auto-updates
2. **devcontainer.json**: Include in image AND provide as copyable template
3. **VS Code versions**: Support both Stable and Insiders
