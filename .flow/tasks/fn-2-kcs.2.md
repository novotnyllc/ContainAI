# fn-2-kcs.2: PR2 - Dockerfile & build.sh (image size + CLI options + OCI labels)

## Description

Reduce Docker image size and enhance build pipeline with CLI options and OCI labels. This combines Dockerfile optimization with build.sh enhancements to avoid merge conflicts.

## Files to Modify

- `agent-sandbox/Dockerfile` (161 lines)
- `agent-sandbox/build.sh` (33 lines)

## Part A: Dockerfile Prerequisites

### Fix Line Continuation Issues
Trailing spaces after backslash on lines 30, 127, 133 - remove them.

### Add BASE_IMAGE ARG
After line 1 (`# syntax=docker/dockerfile:1`):
```dockerfile
ARG BASE_IMAGE=docker/sandbox-templates:claude-code
FROM ${BASE_IMAGE}
```

## Part B: Image Size Reduction

**Target**: >=10% reduction from baseline (manual verification; skip for first build)

### BuildKit Cache Mounts

**APT packages** (lines 16-58):
```dockerfile
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    curl -fsSL ... \
    && apt-get update \
    && apt-get install -y ...
```
Note: With cache mounts, no need to delete lists - they're not baked into layer.

**.NET SDK** (lines 80-83):
```dockerfile
# NOTE: sdk-manifests must NOT be cache-mounted - it's needed at runtime for workloads
RUN --mount=type=cache,target=/tmp/dotnet-install,uid=1000,gid=1000 \
    curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install/dotnet-install.sh \
    && chmod +x /tmp/dotnet-install/dotnet-install.sh \
    && TMPDIR=/tmp/dotnet-install /tmp/dotnet-install/dotnet-install.sh --channel ${DOTNET_CHANNEL}
```

**.NET workloads** (lines 96-99):
```dockerfile
RUN --mount=type=cache,target=/home/agent/.nuget/packages,uid=1000,gid=1000 \
    --mount=type=cache,target=/home/agent/.dotnet/toolResolverCache,uid=1000,gid=1000 \
    dotnet workload install wasm-tools wasm-tools-net9 \
    && dotnet tool install -g PowerShell
```

**npm** (lines 116-125):
```dockerfile
RUN --mount=type=cache,target=/home/agent/.npm/_cacache,uid=1000,gid=1000 \
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash \
    && source /home/agent/.nvm/nvm.sh \
    && nvm install --lts \
    && nvm alias default 'lts/*' \
    && npm install -g typescript eslint prettier
```

**pip/uv** (lines 127-128):
```dockerfile
RUN --mount=type=cache,target=/home/agent/.cache/pip,uid=1000,gid=1000 \
    --mount=type=cache,target=/home/agent/.cache/uv,uid=1000,gid=1000 \
    curl -fsSL https://bun.com/install | bash \
    && curl -LsSf https://astral.sh/uv/install.sh | bash
```

### Additional Cleanup
After AI tools install (line 136), add cleanup:
```dockerfile
    && rm -rf /tmp/* /home/agent/.bun/install-cache
```

## Part C: OCI Labels

Add after FROM (before first RUN):
```dockerfile
ARG BUILD_DATE=unknown
ARG VCS_REF=unknown
LABEL org.opencontainers.image.title="Agent Sandbox" \
      org.opencontainers.image.description="Docker sandbox for AI coding agents" \
      org.opencontainers.image.source="https://github.com/clairernovotny/agent-sandbox" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.revision="${VCS_REF}"
```

## Part D: build.sh Enhancements

Replace entire build.sh with:
```bash
#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Build agent-sandbox Docker image
# ==============================================================================
# Usage: ./build.sh [options] [docker build options]
#   --dotnet-channel CHANNEL  .NET SDK channel (default: 10.0)
#   --base-image IMAGE        Base image (default: docker/sandbox-templates:claude-code)
#   --help                    Show this help
#
# Examples:
#   ./build.sh                          # Build with defaults
#   ./build.sh --dotnet-channel lts     # Use latest LTS
#   ./build.sh --no-cache               # Pass option to docker build
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="agent-sandbox"
DATE_TAG="$(date +%Y-%m-%d)"

# Defaults
DOTNET_CHANNEL="10.0"
BASE_IMAGE="docker/sandbox-templates:claude-code"

# Parse options
DOCKER_ARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dotnet-channel)
            DOTNET_CHANNEL="$2"
            shift 2
            ;;
        --base-image)
            BASE_IMAGE="$2"
            shift 2
            ;;
        --help|-h)
            head -20 "$0" | grep -E '^#' | sed 's/^# //' | sed 's/^#//'
            exit 0
            ;;
        *)
            DOCKER_ARGS+=("$1")
            shift
            ;;
    esac
done

# Enable BuildKit
export DOCKER_BUILDKIT=1

# Capture baseline
BASELINE_SIZE=$(docker images agent-sandbox:latest --format '{{.Size}}' 2>/dev/null | head -1)
if [[ -z "$BASELINE_SIZE" ]]; then
    echo "=== Baseline: (no existing image) ==="
    HAVE_BASELINE=0
else
    echo "=== Baseline: $BASELINE_SIZE ==="
    HAVE_BASELINE=1
fi

# Generate OCI label values
BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
VCS_REF="$(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')"

echo "Building $IMAGE_NAME..."
echo "  Tags: :latest, :$DATE_TAG"
echo "  .NET channel: $DOTNET_CHANNEL"
echo "  Base image: $BASE_IMAGE"
echo ""

docker build \
    -t "${IMAGE_NAME}:latest" \
    -t "${IMAGE_NAME}:${DATE_TAG}" \
    --build-arg DOTNET_CHANNEL="$DOTNET_CHANNEL" \
    --build-arg BASE_IMAGE="$BASE_IMAGE" \
    --build-arg BUILD_DATE="$BUILD_DATE" \
    --build-arg VCS_REF="$VCS_REF" \
    "${DOCKER_ARGS[@]}" \
    "$SCRIPT_DIR"

# Capture result
RESULT_SIZE=$(docker images agent-sandbox:latest --format '{{.Size}}' | head -1)
if [[ -z "$RESULT_SIZE" ]]; then
    echo "ERROR: Build did not produce agent-sandbox:latest"
    exit 1
fi

echo ""
echo "Build complete!"
echo "=== Result: $RESULT_SIZE ==="
docker images "${IMAGE_NAME}" --format "table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.Size}}"

if [[ "$HAVE_BASELINE" == "1" ]]; then
    echo ""
    echo "=== Compare baseline ($BASELINE_SIZE) vs result ($RESULT_SIZE) for >=10% reduction ==="
fi
```

## Testing

```bash
# Build with defaults
cd agent-sandbox && ./build.sh

# Build with options
./build.sh --dotnet-channel lts
./build.sh --help

# Verify image size reduction
docker images agent-sandbox

# Analyze layers
docker history agent-sandbox:latest

# Verify OCI labels
docker inspect agent-sandbox:latest --format '{{json .Config.Labels}}' | jq

# Verify tools work
docker run --rm agent-sandbox:latest dotnet --version
docker run --rm agent-sandbox:latest node --version
docker run --rm agent-sandbox:latest python3 --version
```

## Acceptance

- [ ] Dockerfile line continuations fixed (lines 30, 127, 133)
- [ ] `ARG BASE_IMAGE` added before FROM
- [ ] FROM uses `${BASE_IMAGE}`
- [ ] BuildKit cache mount added for apt (`/var/cache/apt`, `/var/lib/apt`)
- [ ] BuildKit cache mount added for .NET (`/tmp/dotnet-install`, `nuget/packages`, `toolResolverCache`) - NOTE: sdk-manifests must NOT be cached (needed at runtime)
- [ ] BuildKit cache mount added for npm (`/home/agent/.npm/_cacache`)
- [ ] BuildKit cache mount added for pip/uv (`/home/agent/.cache/pip`, `/home/agent/.cache/uv`)
- [ ] OCI labels added (title, description, source, licenses, created, revision)
- [ ] build.sh has `--dotnet-channel` option (default: 10.0)
- [ ] build.sh has `--base-image` option (default: docker/sandbox-templates:claude-code)
- [ ] build.sh has `--help` option
- [ ] build.sh sets `DOCKER_BUILDKIT=1`
- [ ] build.sh captures baseline and result sizes
- [ ] Stale "dotnet-sandbox" comment in build.sh removed
- [ ] Image builds successfully
- [ ] All dev tools functional (dotnet, node, python3, bun)
- [ ] Image size reduced >=10% from baseline (or documented if first build)
- [ ] `docker inspect` shows correct OCI labels

## Done summary
Added BuildKit cache mounts for apt, dotnet, npm, pip/uv to reduce image size and rebuild time. Implemented CLI options (--dotnet-channel, --base-image, --help) and OCI labels in build.sh. Note: sdk-manifests intentionally NOT cache-mounted as it's required at runtime for dotnet workloads.
## Evidence
- Commits: e9b457c
- Tests: build.sh --help works, build.sh --dotnet-channel validation works, no trailing whitespace in Dockerfile
- PRs: