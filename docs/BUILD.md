# Build Guide for Container Authors

This guide is for developers who want to build and publish the coding agent container images.

## Prerequisites

- **Container Runtime**: Docker or Podman
  - Docker: Requires BuildKit enabled (default in recent versions)
  - Podman: Native support for BuildKit-compatible builds
  - Set `CONTAINER_RUNTIME=podman` to force Podman usage
- Git
- (Optional) GitHub Container Registry access for publishing

## Architecture Overview

The container system uses a **layered architecture**:

```
┌─────────────────────────────────────┐
│   Specialized Images (Optional)     │
│  ┌──────────┬──────────┬──────────┐ │
│  │ copilot  │  codex   │  claude  │ │
│  └──────────┴──────────┴──────────┘ │
└──────────────┬──────────────────────┘
               │
┌──────────────▼──────────────────────┐
│      All-Agents Image (Main)        │
│         coding-agents:local         │
│                                     │
│  • Entrypoint scripts               │
│  • MCP config converter             │
│  • Multi-agent support              │
└──────────────┬──────────────────────┘
               │
┌──────────────▼──────────────────────┐
│         Base Image                  │
│    coding-agents-base:local         │
│                                     │
│  • Ubuntu 22.04                     │
│  • Node.js 20.x                     │
│  • Python 3.11                      │
│  • .NET SDK's 8.0, 9.0, 10.0        │
│  • GitHub CLI                       │
│  • Playwright                       │
│  • MCP servers                      │
│  • Non-root user (UID 1000)         │
└─────────────────────────────────────┘
```

## Building Locally

### 1. Build Base Image

```bash
docker build -f Dockerfile.base -t coding-agents-base:local .
```

**What it installs:**
- System dependencies (curl, git, build tools, etc.)
- Node.js 20.x
- Python 3.11 with tomli package
- .NET SDK 8.0, 9.0, 10.0
- Rust toolchain
- GitHub CLI
- Playwright with Chromium
- Pre-installed MCP servers
- Creates non-root user `agentuser` (UID 1000)

**Build time:** ~10-15 minutes (first time)

### 2. Build All-Agents Image

```bash
docker build -f Dockerfile -t coding-agents:local .
```

**What it adds:**
- `entrypoint.sh` - Container startup script
- `setup-mcp-configs.sh` - MCP config converter wrapper
- `convert-toml-to-mcp.py` - TOML to JSON converter

**Build time:** ~1 minute

### 3. Build Specialized Images (Optional)

```bash
docker build -f Dockerfile.copilot -t coding-agents-copilot:local .
docker build -f Dockerfile.codex -t coding-agents-codex:local .
docker build -f Dockerfile.claude -t coding-agents-claude:local .
docker build -f Dockerfile.proxy -t coding-agents-proxy:local .
```

**What they add:**
- Auth validation scripts (warn if OAuth configs not mounted)
- Default CMD to launch specific agent
- `Dockerfile.proxy` builds Squid proxy sidecar used when launching with `--network-proxy squid`

**Build time:** ~30 seconds each

### All at Once

Use the build script:

```bash
chmod +x scripts/build.sh
./scripts/build.sh
```

Or use PowerShell:

```powershell
.\scripts\build.ps1
```

## Image Details

### Base Image (Dockerfile.base)

**Key decisions:**
- Ubuntu 22.04: Stable LTS base
- UID 1000: Matches first user on most Linux/WSL2 systems
- Non-root: Security best practice
- Multi-language: Node.js, Python, .NET for MCP servers

**No secrets or authentication:**
- All auth comes from runtime mounts
- Image can be published publicly

**Package installations:**
```dockerfile
# System packages via apt
curl, git, build-essential, sudo, zsh, vim, nano, jq, unzip

# Language runtimes
Node.js 20.x, Python 3.11, .NET SDK 8.0, Rust (cargo/rustc)

# Tools
GitHub CLI (gh), Playwright, MCP servers

# Python packages
tomli (for TOML parsing)
pipx, uv (package managers)
```

### All-Agents Image (Dockerfile)

**Scripts copied:**
- `/usr/local/bin/entrypoint.sh` - Startup logic
- `/usr/local/bin/setup-mcp-configs.sh` - MCP wrapper
- `/usr/local/bin/convert-toml-to-mcp.py` - TOML parser

**Behavior:**
- Checks for `/workspace/config.toml`
- Converts TOML to JSON for each agent
- Loads optional `~/.mcp-secrets.env`
- Validates git/gh authentication
- Runs user command

### Specialized Images (Dockerfile.*)

Each adds:
- Validation script in `/usr/local/bin/validate-<agent>-auth.sh`
- Checks for `~/.config/<agent>/` mount
- Warns if missing (doesn't fail)
- Changes CMD to launch agent directly

## Publishing to Registry

### Tag for GitHub Container Registry

```bash
# Tag images
docker tag coding-agents-base:local ghcr.io/novotnyllc/coding-agents-base:latest
docker tag coding-agents:local ghcr.io/novotnyllc/coding-agents:latest
docker tag coding-agents-copilot:local ghcr.io/novotnyllc/coding-agents-copilot:latest
docker tag coding-agents-codex:local ghcr.io/novotnyllc/coding-agents-codex:latest
docker tag coding-agents-claude:local ghcr.io/novotnyllc/coding-agents-claude:latest
docker tag coding-agents-proxy:local ghcr.io/novotnyllc/coding-agents-proxy:latest
```

### Push to Registry

```bash
# Login to GitHub Container Registry
echo $GITHUB_TOKEN | docker login ghcr.io -u clairernovotny --password-stdin

# Push images
docker push ghcr.io/novotnyllc/coding-agents-base:latest
docker push ghcr.io/novotnyllc/coding-agents:latest
docker push ghcr.io/novotnyllc/coding-agents-copilot:latest
docker push ghcr.io/novotnyllc/coding-agents-codex:latest
docker push ghcr.io/novotnyllc/coding-agents-claude:latest
```

### Using Published Images

Update Dockerfile ARG to use published base:

```dockerfile
ARG BASE_IMAGE=ghcr.io/novotnyllc/coding-agents-base:latest
FROM ${BASE_IMAGE}
```

Users can then:

```bash
# Pull and use directly
docker pull ghcr.io/novotnyllc/coding-agents-copilot:latest
docker run -it ghcr.io/novotnyllc/coding-agents-copilot:latest
```

## Development Workflow

### Making Changes

1. **Edit source files** (scripts, Dockerfiles, etc.)

2. **Rebuild affected images:**
   ```bash
   # If changing base image
   docker build -f Dockerfile.base -t coding-agents-base:local .
   docker build -f Dockerfile -t coding-agents:local .
   docker build -f Dockerfile.copilot -t coding-agents-copilot:local .
   
   # If only changing scripts
   docker build -f Dockerfile -t coding-agents:local .
   docker build -f Dockerfile.copilot -t coding-agents-copilot:local .
   ```

3. **Test changes:**
   ```bash
   ./launch-agent.ps1 . --agent copilot
   ```

4. **Clean up old images:**
   ```bash
   docker image prune -f
   ```

### Testing Validation Scripts

```bash
# Test without auth mounts (should warn)
docker run -it --rm coding-agents-copilot:local

# Test with auth mounts (should work)
docker run -it --rm \
  -v ~/.config/gh:/home/agentuser/.config/gh:ro \
  -v ~/.config/github-copilot:/home/agentuser/.config/github-copilot:ro \
  coding-agents-copilot:local
```

### Debugging Build Issues

**View build logs:**
```bash
docker build --progress=plain -f Dockerfile.base -t coding-agents-base:local .
```

**No cache rebuild:**
```bash
docker build --no-cache -f Dockerfile.base -t coding-agents-base:local .
```

**Inspect intermediate layer:**
```bash
# Build will show layer IDs, run specific layer
docker run -it --rm <layer-id> /bin/bash
```

## Script Files

### entrypoint.sh

**Location:** `scripts/entrypoint.sh` → `/usr/local/bin/entrypoint.sh`

**Purpose:**
- Display repository info
- Configure git credential helper (gh CLI)
- Run MCP config conversion
- Load MCP secrets
- Validate authentication
- Execute user command

**Called by:** Docker ENTRYPOINT

### setup-mcp-configs.sh

**Location:** `scripts/setup-mcp-configs.sh` → `/usr/local/bin/setup-mcp-configs.sh`

**Purpose:**
- Check for `/workspace/config.toml`
- Call Python converter script
- Exit cleanly if no config found

**Called by:** `entrypoint.sh`

### convert-toml-to-mcp.py

**Location:** `scripts/convert-toml-to-mcp.py` → `/usr/local/bin/convert-toml-to-mcp.py`

**Purpose:**
- Parse TOML config
- Extract `[mcp_servers]` section
- Generate JSON for each agent:
  - `~/.config/github-copilot/mcp/config.json`
  - `~/.config/codex/mcp/config.json`
  - `~/.config/claude/mcp/config.json`

**Called by:** `setup-mcp-configs.sh`

**Dependencies:** `tomli` package (installed in base image)

## Image Size Optimization

Current approximate sizes:
- Base: ~3-4 GB
- All-agents: +50 MB
- Specialized: +10 MB each

**Optimization tips:**

1. **Multi-stage builds** (future improvement):
   ```dockerfile
   FROM base as builder
   RUN npm install -g large-package
   
   FROM base
   COPY --from=builder /usr/local/lib/node_modules /usr/local/lib/node_modules
   ```

2. **Combine RUN commands:**
   ```dockerfile
   RUN apt-get update && \
       apt-get install -y package1 package2 && \
       rm -rf /var/lib/apt/lists/*
   ```

3. **Remove build dependencies:**
   ```dockerfile
   RUN apt-get install -y build-essential && \
       # build something && \
       apt-get remove -y build-essential && \
       apt-get autoremove -y
   ```

## Security Considerations

### Image Security

✅ **Implemented:**
- Non-root user (agentuser)
- No secrets in images
- Security opt: `no-new-privileges:true`
- Read-only mounts for auth

⚠️ **Future improvements:**
- Scan images with `docker scan` or Trivy
- Use distroless images for smaller attack surface
- Implement resource limits in Dockerfiles

### Build Security

✅ **Best practices:**
- Pin package versions for reproducibility
- Verify GPG signatures (GitHub CLI)
- Use official package repositories
- Clear apt cache after installs

### Publishing Security

⚠️ **Before publishing publicly:**
- Review all Dockerfiles for hardcoded secrets
- Scan images for vulnerabilities
- Test images thoroughly
- Use semantic versioning (not just `latest`)

## Maintenance

### Updating Dependencies

**Node.js version:**
```dockerfile
# In Dockerfile.base
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
```

**Python version:**
```dockerfile
# In Dockerfile.base
RUN apt-get install -y python3.12
```

**MCP servers:**
```dockerfile
# In Dockerfile.base
RUN npm install -g @modelcontextprotocol/server-sequential-thinking@latest
```

### Monitoring Image Health

```bash
# Check image details
docker images coding-agents-base:local

# Inspect layers
docker history coding-agents-base:local

# Check for vulnerabilities (if tool installed)
trivy image coding-agents-base:local
```

## Troubleshooting

### Build fails on apt-get

**Issue:** Package not found or network error

**Solution:**
```bash
# Update package lists
docker build --no-cache -f Dockerfile.base -t coding-agents-base:local .
```

### Python package installation fails

**Issue:** pip install fails

**Solution:**
```bash
# Upgrade pip in Dockerfile
RUN python3 -m pip install --upgrade pip
```

### Permission errors during build

**Issue:** Files owned by root

**Solution:**
```dockerfile
# Use COPY with --chown
COPY --chown=agentuser:agentuser script.sh /usr/local/bin/
```

### Script not executable

**Issue:** Permission denied

**Solution:**
```dockerfile
RUN chmod +x /usr/local/bin/script.sh
```

## CI/CD Integration

### GitHub Actions Example

```yaml
name: Build and Push Images

on:
  push:
    branches: [main]
    tags: ['v*']

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v2
      
      - name: Login to GitHub Container Registry
        uses: docker/login-action@v2
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      
      - name: Build and push base
        uses: docker/build-push-action@v4
        with:
          context: .
          file: Dockerfile.base
          push: true
          tags: ghcr.io/${{ github.repository }}-base:latest
          cache-from: type=registry,ref=ghcr.io/${{ github.repository }}-base:buildcache
          cache-to: type=registry,ref=ghcr.io/${{ github.repository }}-base:buildcache,mode=max
      
      - name: Build and push all-agents
        uses: docker/build-push-action@v4
        with:
          context: .
          file: Dockerfile
          push: true
          tags: ghcr.io/${{ github.repository }}:latest
          build-args: BASE_IMAGE=ghcr.io/${{ github.repository }}-base:latest
```

## FAQ

**Q: Why separate base and derived images?**  
A: Base image is large (~4GB) and changes rarely. Derived images are small and change frequently during development.

**Q: Can I use a different base image?**  
A: Yes, but ensure it has all required packages. Ubuntu 22.04 LTS is recommended for stability.

**Q: Why UID 1000?**  
A: Matches the first user on most Linux/WSL2 systems, preventing permission issues with mounted volumes.

**Q: Do I need all specialized images?**  
A: No. The `coding-agents:local` all-agents image can run any agent. Specialized images are convenience wrappers.

**Q: Can I add more MCP servers to the base image?**  
A: Yes, but consider if they should be pre-installed (bloats image) or installed at runtime (slower startup).

---

**Next Steps:**
- See [USAGE.md](USAGE.md) for end-user guide
- See [ARCHITECTURE.md](ARCHITECTURE.md) for system design
