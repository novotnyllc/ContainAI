# fn-1.4 Create helper scripts (build and run)

## Description
Create helper scripts following existing repo patterns for building and running the container.

### Scripts to Create

1. **`build.sh`** - Build the Docker image
2. **`run.sh`** - Run container with proper volume mounts

### Reference Patterns

- `claude/update-claude-sandbox.sh:44-59` - Build and tag pattern
- `claude/sync-plugins.sh:1-34` - Script style (set -euo pipefail, colors, readonly)

### build.sh Structure

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly IMAGE_NAME="docker-sandbox-dotnet-wasm"
readonly IMAGE_TAG="latest"

echo "Building ${IMAGE_NAME}:${IMAGE_TAG}..."
docker build -t "${IMAGE_NAME}:${IMAGE_TAG}" "$SCRIPT_DIR"

echo "Build complete."
docker images "${IMAGE_NAME}:${IMAGE_TAG}"
```

### run.sh Structure

```bash
#!/usr/bin/env bash
set -euo pipefail

readonly IMAGE_NAME="docker-sandbox-dotnet-wasm:latest"
readonly VSCODE_VOLUME="docker-vscode-server"
readonly DOTNET_VOLUME="docker-dotnet-packages"
readonly CLAUDE_PLUGINS_VOLUME="docker-claude-plugins"

# Create volumes if they don't exist
docker volume create "$VSCODE_VOLUME" 2>/dev/null || true
docker volume create "$DOTNET_VOLUME" 2>/dev/null || true

# Run interactive shell
docker run -it --rm \
    -v "${VSCODE_VOLUME}:/home/agent/.vscode-server" \
    -v "${DOTNET_VOLUME}:/home/agent/.nuget/packages" \
    -v "${CLAUDE_PLUGINS_VOLUME}:/home/agent/.claude/plugins" \
    -v "$(pwd):/home/agent/workspace" \
    "$IMAGE_NAME" \
    bash
```

### Notes

- Scripts must be executable (chmod +x)
- Use readonly for constants
- Follow existing color/logging patterns if appropriate
- Include --rm flag for clean container removal
## Acceptance
- [ ] `dotnet-wasm/build.sh` exists and is executable
- [ ] `dotnet-wasm/run.sh` exists and is executable
- [ ] `./dotnet-wasm/build.sh` successfully builds the image
- [ ] `./dotnet-wasm/run.sh` starts container with correct volume mounts
- [ ] Scripts use `set -euo pipefail` pattern
- [ ] Scripts use readonly for constants
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
