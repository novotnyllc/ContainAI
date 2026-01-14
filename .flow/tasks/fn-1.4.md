# fn-1.4 Create helper scripts (build and run)

## Description
Create helper scripts using docker sandbox commands, plus shell aliases and volume initialization.

### Scripts to Create

1. **`build.sh`** - Build and tag the Docker image

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

# Build the image
docker build -t dotnet-wasm:latest "$SCRIPT_DIR"

# Tag for docker sandbox compatibility
docker tag dotnet-wasm:latest docker/sandbox-templates:dotnet-wasm

echo "✅ Built dotnet-wasm:latest"
echo "✅ Tagged as docker/sandbox-templates:dotnet-wasm"
echo ""
echo "Next steps:"
echo "  1. Run: ./init-volumes.sh (first time only)"
echo "  2. Run: source ./aliases.sh"
echo "  3. Run: claude-sandbox-dotnet"
```

2. **`init-volumes.sh`** - Initialize all 5 volumes with correct ownership

```bash
#!/usr/bin/env bash
set -euo pipefail

# Initialize all 5 required named volumes with correct ownership
# Run this ONCE before first use, or whenever you get permission errors

readonly VOLUMES=(
  "docker-vscode-server"
  "docker-github-copilot"
  "docker-dotnet-packages"
  "docker-claude-plugins"
  "docker-claude-sandbox-data"
)

echo "Initializing volumes with UID 1000 ownership..."

for vol in "${VOLUMES[@]}"; do
  echo "  Creating and fixing ownership for: $vol"
  docker volume create "$vol" 2>/dev/null || true
  docker run --rm -v "$vol":/target alpine chown -R 1000:1000 /target
done

echo "✅ All volumes initialized with correct ownership"
echo "You can now run: claude-sandbox-dotnet"
```

3. **`aliases.sh`** - Shell aliases to source (with automatic container naming)

```bash
#!/usr/bin/env bash
# Source this file: source ./dotnet-wasm/aliases.sh

# Get default container name from git repo and branch
_get_sandbox_name() {
  local repo_name branch_name
  repo_name=$(basename "$(git rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null || echo "sandbox")
  branch_name=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
  # Sanitize: replace non-alphanumeric with dash, lowercase
  echo "${repo_name}-${branch_name}" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g'
}

# Main sandbox function - includes ALL 5 required volumes and auto-naming
claude-sandbox-dotnet() {
  local name="${1:-$(_get_sandbox_name)}"
  echo "Starting sandbox: $name"
  docker sandbox run \
    --name "$name" \
    -v docker-vscode-server:/home/agent/.vscode-server \
    -v docker-github-copilot:/home/agent/.config/github-copilot \
    -v docker-dotnet-packages:/home/agent/.nuget/packages \
    -v docker-claude-plugins:/home/agent/.claude/plugins \
    -v docker-claude-sandbox-data:/mnt/claude-data \
    dotnet-wasm
}

# Stop ALL sandboxes (guarded to avoid errors when empty)
claude-sandbox-stop-all() {
  local ids
  ids=$(docker sandbox ls -q 2>/dev/null) || true
  if [ -n "$ids" ]; then
    echo "$ids" | xargs docker sandbox rm
    echo "Stopped all sandboxes"
  else
    echo "No sandboxes running"
  fi
}

echo "Aliases loaded:"
echo "  claude-sandbox-dotnet [name]  - Start .NET WASM sandbox (default: <repo>-<branch>)"
echo "  claude-sandbox-stop-all       - Stop ALL running sandboxes (use with care)"
```

### Container Naming

The `claude-sandbox-dotnet` function automatically names the container based on the current git repository and branch:
- Format: `<repo-name>-<branch-name>`
- Example: `DockerSandbox-main`, `my-project-feature-xyz`
- Sanitized to lowercase alphanumeric with dashes
- Override by passing a name: `claude-sandbox-dotnet my-custom-name`

### Critical: Volume Initialization

Docker volume ownership is tricky:
- Dockerfile `chown` only helps **new** volumes (initial copy-up)
- Pre-existing volumes may be root-owned and break the container
- `init-volumes.sh` fixes ownership for ALL 5 volumes

**Users MUST run `init-volumes.sh` at least once** before first use, or whenever they get permission errors.

### Critical: Image Tagging for docker sandbox

`docker sandbox run` uses the `docker/sandbox-templates:` namespace convention. The build script must:
1. Build as `dotnet-wasm:latest` (for direct docker run testing)
2. Tag as `docker/sandbox-templates:dotnet-wasm` (for docker sandbox compatibility)

### Pattern from Existing Code

Following `sync-plugins.sh` line 253-258:
```bash
docker sandbox rm $(docker sandbox ls -q)   # Remove existing sandbox
claude-sandbox                               # Start with plugins
```

### No Manual Security Flags

Do NOT use `docker run` with:
- `--cap-drop`, `--cap-add`
- `--security-opt`
- `--device`

Docker sandbox handles all security automatically.

## Acceptance
- [ ] `dotnet-wasm/build.sh` exists and is executable
- [ ] `dotnet-wasm/init-volumes.sh` exists and is executable
- [ ] `dotnet-wasm/aliases.sh` exists and can be sourced
- [ ] `./build.sh` successfully builds the image as `dotnet-wasm:latest`
- [ ] `./build.sh` also tags the image as `docker/sandbox-templates:dotnet-wasm`
- [ ] `./init-volumes.sh` creates and fixes ownership for all 5 volumes
- [ ] `claude-sandbox-dotnet` function uses `docker sandbox run`
- [ ] `claude-sandbox-dotnet` function includes ALL 5 volumes
- [ ] `claude-sandbox-dotnet` defaults container name to `<repo>-<branch>`
- [ ] `claude-sandbox-dotnet custom-name` allows custom name override
- [ ] `claude-sandbox-stop-all` function provided (guarded, no error when empty)
- [ ] No manual security flags (--cap-drop, --security-opt) in any script
- [ ] Scripts use `set -euo pipefail`
- [ ] README documents: run init-volumes.sh before first use

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
