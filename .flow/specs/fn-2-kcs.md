# Agent Sandbox Refactor: Image Size & Aliases Cleanup

## Problem

The agent-sandbox project has several issues requiring cleanup:

1. **Docker image too large (9+ GB)**: The image contains accumulated temp files, package caches, and build artifacts that inflate its size far beyond what's necessary
2. **Label warning on attach**: New containers trigger "lacks asb label" warning because `docker sandbox run` isn't being called with `--label` flag
3. **Naming inconsistency**: Variables use `_CSD_` prefix while functions use `asb`, and comments still reference old "csd" naming
4. **Dead code**: Unused arrays (`_CSD_MOUNT_ONLY_VOLUMES`) and inconsistent branding ("Dotnet sandbox" in messages)
5. **Verbose ECI output**: ECI check outputs multiple lines when a brief status would suffice
6. **Build script limitations**: No easy way to configure DOTNET_CHANNEL or other build args

## Approach

Split into **3 separate PRs** for clean, reviewable changes:

### PR 1: Aliases.sh Cleanup
- Rename `_CSD_` prefix to `_ASB_` throughout
- Update all comments from "csd" to "asb"
- Fix branding: "Dotnet sandbox" → "Agent Sandbox"
- Remove dead `_CSD_MOUNT_ONLY_VOLUMES` array
- Add `--label` flag to `docker sandbox run` command (use `org.opencontainers.image.*` standard labels)
- Simplify ECI output to one-line status by default
- Add `ASB_REQUIRE_ECI=1` environment variable option
- Strengthen isolation warning (userns/rootless strongly recommended but not blocking)

### PR 2: Docker Image Size Reduction
- Add BuildKit cache mounts for apt, pip, npm, nuget
- Combine related RUN commands to reduce layers
- Clean up temp files, caches, package lists after each install
- Verify .NET workload installation doesn't leave unnecessary packages
- Target: under 3 GB image size
- Test: build image and verify it starts properly

### PR 3: Build Script Enhancements
- Add `--dotnet-channel` option to build.sh
- Make base image configurable via build arg
- Enable BuildKit features by default (DOCKER_BUILDKIT=1)
- Add OCI standard labels to Dockerfile (org.opencontainers.image.*)

## Edge Cases

- Labels on sandbox containers: `docker sandbox run` may behave differently than `docker run` - test that `--label` works
- BuildKit compatibility: Some Docker versions may not support all cache mount features
- .NET workload cleanup: Must verify workloads still function after cleanup
- Entrypoint `rm -d`: Intentionally fails if workspace not empty (safety check)

## Quick commands

```bash
# Test aliases after changes
source agent-sandbox/aliases.sh && asb --help

# Build with size verification
cd agent-sandbox && ./build.sh && docker images agent-sandbox

# Check image layers
docker history agent-sandbox:latest
```

## Acceptance

- [ ] All `_CSD_` renamed to `_ASB_` in aliases.sh
- [ ] All comments updated from "csd" to "asb"
- [ ] "Dotnet sandbox" messages changed to "Agent Sandbox"
- [ ] `_CSD_MOUNT_ONLY_VOLUMES` removed
- [ ] `docker sandbox run` includes `--label` flag with OCI standard labels
- [ ] ECI check shows one-line status by default
- [ ] `ASB_REQUIRE_ECI=1` environment variable supported
- [ ] Strong warning shown if no userns/rootless isolation detected
- [ ] Docker image under 3 GB
- [ ] BuildKit cache mounts added for apt, pip, npm, nuget
- [ ] `--dotnet-channel` option added to build.sh
- [ ] Base image configurable via build arg
- [ ] OCI standard labels added to Dockerfile
