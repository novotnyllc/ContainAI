# fn-2-kcs.2 PR2: Docker image size reduction to under 3GB

## Description
Reduce Docker image size from 9+ GB to under 3 GB through cache optimization and cleanup.

## Optimization Strategies

### BuildKit Cache Mounts
Add cache mounts to avoid baking package caches into layers:
```dockerfile
RUN --mount=type=cache,target=/var/cache/apt \
    --mount=type=cache,target=/var/lib/apt/lists \
    apt-get update && apt-get install -y ...
```

Similar mounts for:
- `/root/.cache/pip` and `/home/agent/.cache/pip` (pip)
- `/home/agent/.npm/_cacache` (npm)
- `/home/agent/.nuget/packages` (NuGet)
- `/home/agent/.dotnet/toolResolverCache` (.NET tools)

### Layer Cleanup
- Remove `/tmp/*` after each major install step
- Clean `/var/lib/apt/lists/*` after apt installs
- Remove `.cache` directories that aren't needed at runtime
- Clear npm/pip/nuget caches after installs complete

### Layer Combination
Combine related RUN commands where it makes sense:
- All apt-get operations in one layer
- Node.js + global npm packages in one layer
- .NET SDK + workloads + tools in one layer

### .NET Specific Cleanup
After workload installation:
- Clear `/home/agent/.dotnet/sdk-manifests` if not needed
- Remove any workload package archives
- Verify workloads still function after cleanup

## Testing
- Build the image with `./build.sh`
- Verify size with `docker images agent-sandbox`
- Start a container and verify all tools work:
  - `dotnet --version` and `dotnet workload list`
  - `node --version` and `npm --version`
  - `python3 --version`
  - `bun --version`
  - All AI CLI tools start (claude, codex, gemini, etc.)

## Files to Modify
- `agent-sandbox/Dockerfile`
## Acceptance
- [ ] BuildKit cache mounts added for apt packages
- [ ] BuildKit cache mounts added for pip, npm, nuget
- [ ] Temp files cleaned up after each major install
- [ ] .NET workload caches cleaned (workloads still functional)
- [ ] Related RUN commands combined where appropriate
- [ ] Final image size under 3 GB
- [ ] Container starts successfully
- [ ] All development tools functional (dotnet, node, python, bun)
- [ ] All AI CLI tools launch (claude, codex, gemini, copilot, opencode, beads)
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
