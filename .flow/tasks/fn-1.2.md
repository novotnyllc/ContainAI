# fn-1.2 Create Dockerfile with .NET 10 SDK and WASM workloads

## Description
Create a single-stage Dockerfile for .NET 10 SDK with WASM workloads. The full SDK is required in the final image for development, so multi-stage provides no benefit.

### Single-Stage Build

Based on `docker/sandbox-templates:claude-code`:
- **Fail fast** if base is not Ubuntu Noble (deps are distro-specific)
- Install .NET SDK 10 from Microsoft apt repo
- Install wasm-tools workload
- Create ALL 5 volume mount points with correct ownership
- Add Claude credentials symlink workaround
- Verify agent can use dotnet and wasm-tools (as USER agent)

### Complete Dockerfile

```dockerfile
# syntax=docker/dockerfile:1
FROM docker/sandbox-templates:claude-code

USER root

# FAIL FAST if not Ubuntu Noble - our deps are Noble-specific
# This is intentional: if base changes, deps must be updated
RUN if [ -r /etc/os-release ]; then \
      . /etc/os-release && \
      if [ "$ID" != "ubuntu" ] || [ "$VERSION_CODENAME" != "noble" ]; then \
        echo "ERROR: Base image must be Ubuntu Noble (24.04)" >&2; \
        echo "Found: $ID $VERSION_CODENAME" >&2; \
        echo "Update deps (libicu74, libssl3, zlib1g) for new base" >&2; \
        exit 1; \
      fi; \
    else \
      echo "ERROR: /etc/os-release not found - cannot verify base OS" >&2; \
      exit 1; \
    fi

# Set environment variables
ENV PATH="/home/agent/.npm-global/bin:/usr/share/dotnet:${PATH}"
ENV DOTNET_ROOT=/usr/share/dotnet
ENV DOTNET_CLI_TELEMETRY_OPTOUT=1
ENV DOTNET_NOLOGO=1
ENV NUGET_PACKAGES=/home/agent/.nuget/packages

# Install prerequisites and .NET SDK 10
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    wget \
    python3 \
    libicu74 \
    libssl3 \
    zlib1g \
    && wget https://packages.microsoft.com/config/ubuntu/24.04/packages-microsoft-prod.deb -O packages-microsoft-prod.deb \
    && dpkg -i packages-microsoft-prod.deb \
    && rm packages-microsoft-prod.deb \
    && apt-get update \
    && apt-get install -y --no-install-recommends dotnet-sdk-10.0 \
    && rm -rf /var/lib/apt/lists/*

# Install WASM workload (as root, will be available system-wide)
RUN dotnet workload install wasm-tools

# Verify workload installed correctly
RUN dotnet workload list | grep -q wasm-tools

# Create symlink for dotnet command accessibility
RUN ln -sf /usr/share/dotnet/dotnet /usr/local/bin/dotnet

# Verify .NET installation works (fails if deps missing)
RUN dotnet --info

# Create ALL 5 volume mount points with correct ownership
# Note: This helps new volumes but existing volumes may still have wrong ownership
# Run init-volumes.sh (from fn-1.4) to fix pre-existing volumes
RUN mkdir -p /home/agent/.vscode-server \
             /home/agent/.nuget/packages \
             /home/agent/.config/github-copilot \
             /home/agent/.claude/plugins \
             /mnt/claude-data \
    && chown -R agent:agent /home/agent/.vscode-server \
                            /home/agent/.nuget/packages \
                            /home/agent/.config \
                            /home/agent/.claude \
    && chown agent:agent /mnt/claude-data

# Claude credentials symlink workaround (sandbox doesn't do this automatically)
RUN ln -sf /mnt/claude-data/.credentials.json /home/agent/.claude/.credentials.json \
    && chown -h agent:agent /home/agent/.claude/.credentials.json

# Switch to agent user for verification
USER agent

# Verify agent can see workload (fails if PATH/env is wrong)
RUN dotnet workload list | grep -q wasm-tools

WORKDIR /home/agent/workspace
```

### Prerequisites: Verify Base Image

Before building, verify `docker/sandbox-templates:claude-code` is Ubuntu Noble:

```bash
docker run --rm docker/sandbox-templates:claude-code cat /etc/os-release | grep -E "^(ID|VERSION_CODENAME)="
# Expected: ID=ubuntu, VERSION_CODENAME=noble
```

If not Noble, update the deps for the actual distro.

### Critical: All 5 Volume Mount Points

The Dockerfile creates and chowns all 5 volume mount points, but this only helps **new** volumes. For **pre-existing** volumes that may have wrong ownership, use `init-volumes.sh` (see fn-1.4).

### Critical: ca-certificates

The Dockerfile MUST install `ca-certificates` explicitly - don't rely on the base image. This is required for:
- `dotnet restore` (NuGet over HTTPS)
- Any SDK/workload operations
- General HTTPS connectivity

### Why Single-Stage

The full .NET SDK is required in the final image for development work (building, debugging, testing). Multi-stage would add complexity without reducing image size.

## Acceptance
- [ ] Dockerfile uses single-stage build based on `docker/sandbox-templates:claude-code`
- [ ] `docker build -t dotnet-wasm:latest ./dotnet-wasm/` succeeds
- [ ] Build **fails** with clear error if base image is not Ubuntu Noble
- [ ] `docker run --rm -u agent dotnet-wasm:latest dotnet --version` shows 10.x
- [ ] `docker run --rm -u agent dotnet-wasm:latest dotnet workload list` shows `wasm-tools`
- [ ] `docker run --rm -u agent dotnet-wasm:latest sh -c "command -v claude && claude --version"` succeeds
- [ ] `docker run --rm dotnet-wasm:latest id` shows `uid=1000(agent)`
- [ ] `docker run --rm dotnet-wasm:latest python3 --version` succeeds
- [ ] All 5 volume mount points created with correct ownership
- [ ] Claude credentials symlink exists: `/home/agent/.claude/.credentials.json -> /mnt/claude-data/.credentials.json`
- [ ] Dockerfile uses `USER agent` for verification steps (not `su - agent`)
- [ ] No docker-claude-* images are referenced as dependencies
- [ ] DOTNET_ROOT environment variable is set to /usr/share/dotnet
- [ ] `dotnet --info` runs successfully during build (validates deps are complete)

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
