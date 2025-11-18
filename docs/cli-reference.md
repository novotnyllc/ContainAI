# Command-Line Reference

Complete reference for all CodingAgents launcher scripts and their arguments.

## Table of Contents

- [Quick Launch Scripts](#quick-launch-scripts)
  - [run-copilot](#run-copilot)
  - [run-codex](#run-codex)
  - [run-claude](#run-claude)
- [Advanced Launch Script](#advanced-launch-script)
  - [launch-agent](#launch-agent)
- [Management Scripts](#management-scripts)
  - [list-agents](#list-agents)
  - [remove-agent](#remove-agent)
  - [connect-agent](#connect-agent)
- [Setup Scripts](#setup-scripts)
  - [verify-prerequisites](#verify-prerequisites)
  - [install](#install)
- [Build Scripts](#build-scripts)
  - [build](#build)

---

## Quick Launch Scripts

Ephemeral containers that auto-remove on exit. Best for quick coding sessions.

> **Auto-update:** Launchers check whether the CodingAgents repository is behind its upstream before starting and prompt you to sync. Configure the behavior via `~/.config/coding-agents/host-config.env` (Linux/macOS) or `%USERPROFILE%\.config\coding-agents\host-config.env` (Windows) by setting `LAUNCHER_UPDATE_POLICY=prompt|always|never`.

### run-copilot

Launch GitHub Copilot CLI in the current directory.

**Location:** `scripts/launchers/run-copilot` (bash), `run-copilot.ps1` (PowerShell)

#### Synopsis

```bash
run-copilot [REPO_PATH] [OPTIONS]
```

```powershell
.\run-copilot.ps1 [[-RepoPath] <String>] [OPTIONS]
```

#### Arguments

**Positional:**

| Argument | Type | Default | Description |
|----------|------|---------|-------------|
| `REPO_PATH` (bash)<br>`-RepoPath` (PowerShell) | string | `.` (current directory) | Path to git repository to mount |

**Options:**

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `-b, --branch BRANCH` (bash)<br>`-Branch BRANCH` (PowerShell) | string | none | Branch name (creates `<agent>/<branch>`) |
| `--name NAME` (bash)<br>`-Name NAME` (PowerShell) | string | none | Custom container name |
| `--dotnet-preview CHANNEL` (bash)<br>`-DotNetPreview CHANNEL` (PowerShell) | string | none | .NET preview SDK channel (e.g., `11.0`) |
| `--network-proxy MODE` (bash)<br>`-NetworkProxy MODE` (PowerShell) | string | `allow-all` | Network mode: `allow-all`, `restricted`, `squid` |
| `--cpu NUM` (bash)<br>`-Cpu NUM` (PowerShell) | string | `4` | CPU limit (e.g., `2`, `4`, `8`, `0.5`) |
| `--memory SIZE` (bash)<br>`-Memory SIZE` (PowerShell) | string | `8g` | Memory limit (e.g., `4g`, `8g`, `16g`) |
| `--gpu SPEC` (bash)<br>`-Gpu SPEC` (PowerShell) | string | none | GPU specification (e.g., `all`, `device=0`, `device=0,1`) |
| `--no-push` (bash)<br>`-NoPush` (PowerShell) | flag | false | Skip auto-push to git remote on exit |
| `--use-current-branch` (bash)<br>`-UseCurrentBranch` (PowerShell) | flag | false | Use current branch (no isolation) |
| `-y, --force` (bash)<br>`-Force` (PowerShell) | flag | false | Replace existing branch without prompt |
| `-h, --help` (bash)<br>`-Help` (PowerShell) | flag | false | Show help message |

#### Examples

**Basic usage:**
```bash
# Launch in current directory
run-copilot

# Launch in specific directory
run-copilot ~/my-project
run-copilot /path/to/repo

# Windows
.\run-copilot.ps1 C:\Projects\MyApp
```

**With branch isolation:**
```bash
# Create copilot/feature branch
run-copilot -b feature

# Use current branch (no isolation)
run-copilot --use-current-branch

# Windows
.\run-copilot.ps1 -Branch feature
.\run-copilot.ps1 -UseCurrentBranch
```

**With custom name:**
```bash
# Custom container name
run-copilot --name my-session

# Windows
.\run-copilot.ps1 -Name my-session
```

**With network controls:**
```bash
# Restricted network (no internet)
run-copilot --network-proxy restricted

# Monitored proxy
run-copilot --network-proxy squid

# Windows
.\run-copilot.ps1 -NetworkProxy restricted
```

**With resource limits:**
```bash
# More CPUs and memory
run-copilot --cpu 8 --memory 16g

# Minimal resources
run-copilot --cpu 2 --memory 4g

# Windows
.\run-copilot.ps1 -Cpu 8 -Memory 16g
```

**With GPU:**
```bash
# Use all GPUs
run-copilot --gpu all

# Specific GPU
run-copilot --gpu device=0

# Windows
.\run-copilot.ps1 -Gpu all
```

**Disable auto-push:**
```bash
# Skip git push on exit
run-copilot --no-push

# Windows
.\run-copilot.ps1 -NoPush
```

**Combined options:**
```bash
# Full example
run-copilot ~/my-project -b feature-api --cpu 8 --memory 16g --network-proxy squid

# Windows
.\run-copilot.ps1 C:\Projects\MyApp -Branch feature-api -Cpu 8 -Memory 16g -NetworkProxy squid
```

#### Behavior

1. Validates repository path exists and is a git repository
2. Pulls latest `coding-agents-copilot:local` image
3. Creates ephemeral container with:
   - Repository mounted at `/workspace`
   - **Branch isolation** (if `-b` specified) or current branch (default)
   - Git authentication from host (if configured)
   - Auto-commit and push on exit (unless `--no-push`)
4. Starts a managed tmux session so you can detach/reconnect (`Ctrl+B`, then `D`)
5. Drops you into interactive shell with Copilot CLI
6. On exit (`Ctrl+D` or `exit`):
   - Auto-commits changes
  - Pushes to the secure local remote (bare repo) so work is preserved even if the container is removed
   - Container auto-removes

> **Auto-push storage:** For local repositories, commits are written to `~/.coding-agents/local-remotes/<repo-hash>.git`. Fetch from that bare repo to bring changes back into your working tree, or set `CODING_AGENTS_LOCAL_REMOTES_DIR` before launching to change the location.

> **Upstream access:** The container starts without any GitHub origin remote. Only the managed `local` remote is configured so you must publish from the host repository (or explicitly add a remote yourself inside the container).

> **Host sync:** After every push to `local`, the host working tree fast-forwards automatically unless you set `CODING_AGENTS_DISABLE_AUTO_SYNC=1`.

**Reattach later:** `connect-agent --name <container>` reconnects to the tmux session if the container is still running (for example, if you detached with `Ctrl+B`, `D`).

**Branch Behavior:**
- Without `-b`: Works on current branch (same as `--use-current-branch`)
- With `-b feature`: Creates `copilot/feature` branch for isolation
- Branch management same as [`launch-agent`](#launch-agent)

#### Container Details

- **Name:** `copilot-{repo}-{branch}`
- **Image:** `coding-agents-copilot:local`
- **Working Dir:** `/workspace`
- **Network:** Bridge (internet access)
- **Security:** `no-new-privileges:true`, seccomp `docker/profiles/seccomp-coding-agents.json`, AppArmor profile `coding-agents` (if supported)
- **Removal:** Automatic on exit (`--rm`)

---

### run-codex

Launch OpenAI Codex in the current directory.

**Location:** `scripts/launchers/run-codex` (bash), `run-codex.ps1` (PowerShell)

#### Synopsis

```bash
run-codex [REPO_PATH] [OPTIONS]
```

```powershell
.\run-codex.ps1 [[-RepoPath] <String>] [OPTIONS]
```

#### Arguments and Options

See [run-copilot](#run-copilot) - identical arguments and options, just different agent.

Supports all options:
- `-b, --branch` - Branch isolation
- `--name` - Custom container name
- `--dotnet-preview` - .NET preview SDK
- `--network-proxy` - Network controls
- `--cpu`, `--memory`, `--gpu` - Resource limits
- `--no-push` - Skip auto-push
- `--use-current-branch` - No isolation
- `-y, --force` - Force branch replacement

#### Examples

All [run-copilot](#run-copilot) examples apply - just replace `run-copilot` with `run-codex`.

#### Container Details

- **Name:** `codex-{repo}-{branch}` or `codex-{name}`
- **Image:** `coding-agents-codex:local`
- Same behavior as `run-copilot`

---

### run-claude

Launch Anthropic Claude in the current directory.

**Location:** `scripts/launchers/run-claude` (bash), `run-claude.ps1` (PowerShell)

#### Synopsis

```bash
run-claude [REPO_PATH] [OPTIONS]
```

```powershell
.\run-claude.ps1 [[-RepoPath] <String>] [OPTIONS]
```

#### Arguments and Options

See [run-copilot](#run-copilot) - identical arguments and options, just different agent.

Supports all options:
- `-b, --branch` - Branch isolation
- `--name` - Custom container name  
- `--dotnet-preview` - .NET preview SDK
- `--network-proxy` - Network controls
- `--cpu`, `--memory`, `--gpu` - Resource limits
- `--no-push` - Skip auto-push
- `--use-current-branch` - No isolation
- `-y, --force` - Force branch replacement

#### Examples

All [run-copilot](#run-copilot) examples apply - just replace `run-copilot` with `run-claude`.

#### Container Details

- **Name:** `claude-{repo}-{branch}` or `claude-{name}`
- **Image:** `coding-agents-claude:local`
- Same behavior as `run-copilot`

---

## Advanced Launch Script

Persistent containers for long-running work with VS Code integration.

### launch-agent

Launch an agent in a persistent background container with branch isolation.

**Location:** `scripts/launchers/launch-agent` (bash), `launch-agent.ps1` (PowerShell)

#### Synopsis

```bash
launch-agent AGENT [SOURCE] [OPTIONS]
```

```powershell
launch-agent <AGENT> [<SOURCE>] [OPTIONS]
```

#### Arguments

**Positional (Required):**

| Argument | Type | Values | Description |
|----------|------|--------|-------------|
| `AGENT` | string | `copilot`, `codex`, `claude` | Agent type to launch |
| `SOURCE` | string | Path or URL | Repository path or Git URL (default: `.`) |

**Options:**

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `-b, --branch BRANCH` (bash)<br>`-Branch BRANCH` (PowerShell) | string | auto-generated | Branch name (creates `{agent}/{branch}`) |
| `--name NAME` (bash)<br>`-Name NAME` (PowerShell) | string | auto-generated | Custom container name |
| `--dotnet-preview CHANNEL` (bash)<br>`-DotNetPreview CHANNEL` (PowerShell) | string | none | .NET preview SDK channel (e.g., `11.0`) |
| `--network-proxy MODE` (bash)<br>`-NetworkProxy MODE` (PowerShell) | string | `allow-all` | Network mode: `allow-all`, `restricted`, `squid` |
| `--cpu NUM` (bash)<br>`-Cpu NUM` (PowerShell) | string | `4` | CPU limit |
| `--memory SIZE` (bash)<br>`-Memory SIZE` (PowerShell) | string | `8g` | Memory limit |
| `--gpu SPEC` (bash)<br>`-Gpu SPEC` (PowerShell) | string | none | GPU specification |
| `--no-push` (bash)<br>`-NoPush` (PowerShell) | flag | false | Disable auto-push on container shutdown |
| `--use-current-branch` (bash)<br>`-UseCurrentBranch` (PowerShell) | flag | false | Use current branch (unsafe, skips isolation) |
| `-y, --force` (bash)<br>`-Force` (PowerShell) | flag | false | Replace existing branch without prompt |
| `-h, --help` (bash)<br>`-Help` (PowerShell) | flag | false | Show help |

#### Branch Behavior

**Default (no `-b` flag):**
- If current branch matches agent pattern (`copilot/*`): Use it
- Otherwise: Create unique `{agent}/session-N` branch

**With `-b` flag:**
- Creates `{agent}/{branch}` branch
- Prompts if branch exists (unless `-y` flag)
- Archives old branch if it has unmerged commits

**With `--use-current-branch`:**
- ⚠️ Dangerous: Works directly on current branch
- No isolation
- Not recommended

#### Network Modes

| Mode | Network Access | Use Case |
|------|---------------|----------|
| `allow-all` | Full internet | Default, maximum flexibility |
| `restricted` | None (`--network none`) | Maximum security, no external access |
| `squid` | Monitored proxy | Audit network requests, domain whitelist |

#### Integrity, Audit, and Overrides

- **Trusted file enforcement:** Before starting a container, `launch-agent` checks that `scripts/launchers/**`, stub helpers, and `docker/profiles/**` match `HEAD`. If anything is dirty, the launch aborts unless you create an override token at `~/.config/coding-agents/overrides/allow-dirty` (configurable via `CODING_AGENTS_DIRTY_OVERRIDE_TOKEN`). Every override is logged.
- **Session manifest logging:** The host renders a per-session config, computes its SHA256, exports it via `CODING_AGENTS_SESSION_CONFIG_SHA256`, and writes a `session-config` event to the audit log. Compare this hash with what helper tooling reports to ensure configs were not tampered with in transit.
- **Audit log location:** Structured JSON events (`session-config`, `capabilities-issued`, `override-used`) are appended to `~/.config/coding-agents/security-events.log`. Override via `CODING_AGENTS_AUDIT_LOG=/path/to/file` if you need alternate storage. All events are also forwarded to `systemd-cat -t coding-agents-launcher` when available.
- **Helper sandbox controls:** By default helper containers run with `--network none`, tmpfs-backed `/tmp` + `/var/tmp`, `--cap-drop ALL`, and the ptrace-blocking seccomp profile. Tune with environment variables before launching:
  - `CODING_AGENTS_HELPER_NETWORK_POLICY=loopback|none|host|bridge|<docker-network>`
  - `CODING_AGENTS_HELPER_PIDS_LIMIT` (default `64`)
  - `CODING_AGENTS_HELPER_MEMORY` (default `512m`)

To inspect recent events quickly:

```bash
tail -f ~/.config/coding-agents/security-events.log
```

Run `bash scripts/test/test-launchers.sh` (or `pwsh scripts/test/test-launchers.ps1`) after modifying launcher logic to confirm helper network isolation and audit logging regressions are still covered.

#### Examples

**Basic usage:**
```bash
# Copilot in current directory
launch-agent copilot

# Codex with custom branch
launch-agent codex ~/my-project -b refactor-db

# Clone from URL
launch-agent copilot https://github.com/user/repo

# Windows
launch-agent copilot C:\Projects\MyApp -Branch feature-auth
```

**Custom container name:**
```bash
# Useful for multiple instances
launch-agent copilot . --name backend-api
launch-agent copilot . --name frontend-ui

# Windows
launch-agent copilot . -Name backend-api
```

**Network isolation:**
```bash
# No internet access
launch-agent copilot . --network-proxy restricted

# Monitored proxy
launch-agent copilot . --network-proxy squid

# Windows
launch-agent copilot . -NetworkProxy restricted
```

**Resource limits:**
```bash
# High-performance configuration
launch-agent copilot . --cpu 16 --memory 32g --gpu all

# Low-resource configuration
launch-agent copilot . --cpu 2 --memory 4g

# Windows
launch-agent copilot . -Cpu 16 -Memory 32g -Gpu all
```

**Branch management:**
```bash
# Auto-replace existing branch
launch-agent copilot . -b feature -y

# Use current branch (no isolation)
launch-agent copilot . --use-current-branch

# Windows
launch-agent copilot . -Branch feature -Force
launch-agent copilot . -UseCurrentBranch
```

**Advanced combinations:**
```bash
# Production-like environment
launch-agent copilot ~/production-repo \
  -b hotfix-security \
  --network-proxy restricted \
  --cpu 8 \
  --memory 16g \
  --no-push

# Development with .NET preview
launch-agent copilot . \
  -b feature-dotnet11 \
  --dotnet-preview 11.0 \
  --gpu all

# Windows
launch-agent copilot C:\production-repo `
  -Branch hotfix-security `
  -NetworkProxy restricted `
  -Cpu 8 `
  -Memory 16g `
  -NoPush
```

#### Behavior
  # Build only Copilot + proxy
  ./scripts/build/build.sh --agents copilot,proxy


1. Validates source (path or URL)
2. Determines branch name (auto or specified)
3. Checks for branch conflicts (prompts if exists)
4. Creates container in background (`-d`)
5. Sets up repository inside container
6. Starts a managed tmux session so you can attach later without restarting
7. Returns to terminal (container keeps running)
  # Build only Copilot + proxy
  .\scripts\build\build.ps1 -Agents copilot,proxy


**Connect to container:**
- VS Code: Dev Containers → Attach to Running Container
- Terminal: `scripts/launchers/connect-agent --name {container-name}` (preferred) or `docker exec -it {container-name} bash`

**Stop container:**
```bash
docker stop {container-name}
# Auto-commits and pushes changes (unless --no-push)
```

#### Container Details

- **Name:** `{agent}-{repo}-{branch}` or `{agent}-{name}`
- **Image:** `coding-agents-{agent}:local`
- **Working Dir:** `/workspace`
- **Command:** `sleep infinity` (runs in background)
- **Removal:** Manual (`docker rm`) after stop
- **Persistence:** Data survives container restarts

---

## Management Scripts

### list-agents

List all running agent containers.

**Location:** `scripts/launchers/list-agents` (bash), `list-agents.ps1` (PowerShell)

#### Synopsis

```bash
list-agents [OPTIONS]
```

```powershell
list-agents [OPTIONS]
```

#### Options

| Option | Type | Description |
|--------|------|-------------|
| `-a, --all` (bash)<br>`-All` (PowerShell) | flag | Include stopped containers |
| `-h, --help` (bash)<br>`-Help` (PowerShell) | flag | Show help |

#### Examples

```bash
# List running agents
list-agents

# List all agents (including stopped)
list-agents --all

# Windows
list-agents
list-agents -All
```

#### Output

```
AGENT     CONTAINER                    STATUS      REPOSITORY    BRANCH
copilot   copilot-myapp-feature        running     myapp         copilot/feature
codex     codex-api-refactor           running     api           codex/refactor
claude    claude-docs-update           exited      docs          claude/update
```

---

### remove-agent

Remove agent container(s).

**Location:** `scripts/launchers/remove-agent` (bash), `remove-agent.ps1` (PowerShell)

#### Synopsis

```bash
remove-agent [CONTAINER_NAME] [OPTIONS]
```

```powershell
remove-agent [<CONTAINER_NAME>] [OPTIONS]
```

#### Arguments

| Argument | Type | Description |
|----------|------|-------------|
| `CONTAINER_NAME` | string | Container name or pattern to remove |

**If not specified:** Interactive selection or all containers

#### Options

| Option | Type | Description |
|--------|------|-------------|
| `-a, --all` (bash)<br>`-All` (PowerShell) | flag | Remove all agent containers |
| `-f, --force` (bash)<br>`-Force` (PowerShell) | flag | Force removal without confirmation |
| `-h, --help` (bash)<br>`-Help` (PowerShell) | flag | Show help |

#### Examples

```bash
# Remove specific container
remove-agent copilot-myapp-feature

# Remove with pattern
remove-agent "copilot-*"

# Remove all agents (with confirmation)
remove-agent --all

# Force remove without confirmation
remove-agent copilot-myapp-feature --force

# Windows
remove-agent copilot-myapp-feature
remove-agent -All
remove-agent copilot-myapp-feature -Force
```

---

### connect-agent

Attach to the tmux session inside a running agent container.

**Location:** `scripts/launchers/connect-agent` (bash), `connect-agent.ps1` (PowerShell)

#### Synopsis

```bash
connect-agent [OPTIONS] [CONTAINER_NAME]
```

```powershell
connect-agent.ps1 [[-Name] <String>] [OPTIONS]
```

#### Arguments & Options

| Parameter | Type | Description |
|-----------|------|-------------|
| `CONTAINER_NAME` | string | Container name to attach to (optional if only one running) |
| `-n, --name NAME` (bash)<br>`-Name NAME` (PowerShell) | string | Explicit container name |
| `-h, --help` (bash)<br>`-Help` (PowerShell) | flag | Show help |

#### Behavior

1. Validates Docker/Podman is running
2. Detects running agent containers (label `coding-agents.type=agent`)
3. If multiple containers are running, prompts for explicit `--name`
4. Executes `agent-session attach` inside the container so you land in the managed tmux session
5. Falls back to `docker exec -it ... bash` if the helper is missing (older containers)

Detach any time with `Ctrl+B`, then `D`. Repeat `connect-agent` whenever you want to hop back in.

#### Examples

```bash
# Attach to the only running container
connect-agent

# Attach to a specific container
connect-agent --name copilot-myapp-feature

# Windows
connect-agent.ps1 -Name copilot-myapp-feature
```

---

## Setup Scripts

### verify-prerequisites

Check that all prerequisites are installed and configured.

**Location:** `scripts/verify-prerequisites.sh` (bash), `verify-prerequisites.ps1` (PowerShell)

#### Synopsis

```bash
./scripts/verify-prerequisites.sh
```

```powershell
.\scripts\verify-prerequisites.ps1
```

#### No Arguments

This script takes no arguments.

#### Checks

**Required:**
- ✅ Docker or Podman installed and version ≥20.10.0 (Docker) or ≥3.0.0 (Podman)
- ✅ Container daemon running
- ✅ Git installed
- ✅ Git `user.name` configured
- ✅ Git `user.email` configured
- ✅ Disk space ≥5GB available

**Optional (but recommended):**
- ℹ️  GitHub CLI (`gh`) - Only needed if using GitHub Copilot or GitHub-hosted repositories with authentication
- ℹ️  VS Code - For Dev Containers integration
- ℹ️  jq/yq - For advanced scripting

#### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | All prerequisites met |
| 1 | One or more prerequisites missing |

#### Example Output

```
⏳ Checking prerequisites...
✓ Docker installed (version 25.0.0)
  OR
✓ Podman installed (version 4.5.0)
✓ Container daemon is running
✓ Git installed (version 2.43.0)
✓ Git user.name configured: John Doe
✓ Git user.email configured: john@example.com
⚠ GitHub CLI not installed (optional - only needed for GitHub Copilot/authentication)
✓ Disk space available: 42.5 GB

✅ Core prerequisites met! You're ready to use CodingAgents.
⚠ 1 optional tool missing (see above)
```

---

### install

Add launcher scripts to PATH.

**Location:** `scripts/install.sh` (bash), `scripts/install.ps1` (PowerShell)

#### Synopsis

```bash
./scripts/install.sh [OPTIONS]
```

```powershell
.\scripts\install.ps1 [OPTIONS]
```

#### Options

| Option | Type | Description |
|--------|------|-------------|
| `-h, --help` (bash)<br>`-Help` (PowerShell) | flag | Show help |

#### Behavior

**Linux/Mac:**
- Detects shell (bash or zsh)
- Adds `export PATH="$REPO/scripts/launchers:$PATH"` to rc file
- Prints instructions to reload shell

**Windows:**
- Adds `$REPO\scripts\launchers` to User PATH (registry)
- Changes take effect in new PowerShell windows

#### Examples

```bash
# Install on Linux/Mac
./scripts/install.sh

# Then reload shell
source ~/.bashrc  # or ~/.zshrc

# Install on Windows
.\scripts\install.ps1

# Then restart PowerShell
```

#### Manual Installation

If script fails, manually add to PATH:

**Linux (bash):**
```bash
echo 'export PATH="/path/to/CodingAgents/scripts/launchers:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

**Mac (zsh):**
```bash
echo 'export PATH="/path/to/CodingAgents/scripts/launchers:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

**Windows (PowerShell - Temporary):**
```powershell
$env:PATH += ";E:\dev\CodingAgents\scripts\launchers"
```

**Windows (PowerShell - Permanent):**
```powershell
[Environment]::SetEnvironmentVariable(
    "Path",
    "$env:PATH;E:\dev\CodingAgents\scripts\launchers",
    [EnvironmentVariableTarget]::User
)
```

---

## Build Scripts

### build

Build container images from source.

**Location:** `scripts/build/build.sh` (bash), `scripts/build/build.ps1` (PowerShell)

#### Synopsis

```bash
./scripts/build/build.sh [OPTIONS]
```

```powershell
.\scripts\build\build.ps1 [OPTIONS]
```

#### Options

| Option | Type | Description |
|--------|------|-------------|
| `-a, --agents LIST` (bash)<br>`-Agents LIST` (PowerShell) | string | Comma-separated list of targets to build. Accepts `copilot`, `codex`, `claude`, `proxy`, or `all`. Default: all targets. |
| `-h, --help` (bash)<br>`-Help` (PowerShell) | flag | Show help |

**Notes:**
- The base-image prompt only appears when at least one agent image (`copilot`, `codex`, `claude`) is selected.
- Specialized images depend on `coding-agents:local` and will trigger its build automatically.

#### Interactive Prompts

**Base Image Selection:**
```
Base image: Pull ghcr.io or build locally?
1) Pull from GitHub Container Registry (recommended, faster)
2) Build locally (slower, for development)
Choice [1-2]:
```

**Pull:** Downloads pre-built base image (~1 minute)
**Build:** Builds from Dockerfile (~10 minutes)

#### Build Order (per requested targets)

1. **Base image** (`coding-agents-base:local`) – only when building agent images
2. **All-agents image** (`coding-agents:local`) – prerequisite for agent-specific images
3. **Selected specialized images** – `coding-agents-copilot:local`, `coding-agents-codex:local`, `coding-agents-claude:local`
4. **Proxy image** (`coding-agents-proxy:local`) – built when requested

#### Examples

```bash
# Build all images (Linux/Mac)
./scripts/build/build.sh

# Build all images (Windows)
.\scripts\build\build.ps1

# With BuildKit (faster, better caching)
DOCKER_BUILDKIT=1 ./scripts/build/build.sh

# Windows with BuildKit
$env:DOCKER_BUILDKIT=1
.\scripts\build\build.ps1
```

#### Build Time

- **Pull base:** ~5 minutes total
- **Build base:** ~20 minutes total

**Breakdown (build locally):**
- Base image: ~10 minutes
- All-agents: ~2 minutes
- Each specialized: ~2 minutes
- Proxy: ~1 minute

#### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | All images built successfully |
| 1 | Build failed |

#### Success Output

```
✅ Build complete!

Images created:
  coding-agents-base:local
  coding-agents:local
  coding-agents-copilot:local
  coding-agents-codex:local
  coding-agents-claude:local
  coding-agents-proxy:local

Next steps:
  1. Install launchers: ./scripts/install.sh
  2. Launch an agent:   run-copilot
```

---

## Common Patterns

### Resource Limit Syntax

**CPU Limits:**
- Fractional: `0.5`, `1.5`, `2.5`
- Whole numbers: `1`, `2`, `4`, `8`, `16`
- Examples: `--cpu 4`, `-Cpu 8`

**Memory Limits:**
- Bytes: `536870912` (not recommended)
- Kilobytes: `524288k`
- Megabytes: `512m`, `1024m`
- Gigabytes: `1g`, `4g`, `8g`, `16g`, `32g`
- Examples: `--memory 8g`, `-Memory 16g`

**GPU Specifications:**
- All GPUs: `all`
- Specific device: `device=0`, `device=1`
- Multiple devices: `device=0,1`, `device=0,2`
- With capabilities: `"device=0,capabilities=gpu"`
- Examples: `--gpu all`, `-Gpu "device=0"`

### Branch Name Rules

**Valid:**
- Alphanumeric: `feature`, `bugfix123`
- Slashes: `feature/auth`, `fix/issue-42`
- Underscores: `feature_auth`, `my_branch`
- Dashes: `feature-auth`, `my-branch`
- Dots: `v1.0`, `release-1.2.3`

**Invalid:**
- Start with special char: `-feature`, `.branch`
- Special characters: `feature@auth`, `bug#42`
- Spaces: `my feature`

**Pattern:** `[a-zA-Z0-9][a-zA-Z0-9/_.-]*`

### Container Naming

**Auto-generated:**
- Format: `{agent}-{repo}-{branch}`
- Branch sanitized: `/` → `-`, special chars removed
- Example: `copilot-myapp-feature-auth`

**Custom:**
- Format: `{agent}-{name}`
- Example: `copilot-backend` (with `--name backend`)

**Rules:**
- Start with alphanumeric
- Contain only: `a-z`, `A-Z`, `0-9`, `_`, `.`, `-`
- Docker imposes restrictions on container names

### Exit Behavior

**Ephemeral (`run-*`):**
1. On exit, trap executes
2. Checks if container still exists
3. Commits changes: `git add -A`, `git commit`
4. Pushes to the per-repo bare remote under `~/.coding-agents/local-remotes` (unless `--no-push`)
5. Container auto-removes (`--rm`)

4. Starts a managed tmux session so you can detach/reconnect (`Ctrl+B`, then `D`)
1. Container keeps running in background
2. On `docker stop`:
   - Entrypoint receives SIGTERM
   - Commits changes
  - Pushes to the secure bare remote (unless `--no-push`)
3. Container stops but persists
4. Manual removal: `docker rm`

**Note:** Git now pushes to the managed bare repo path automatically. Fetch from that path (or set `CODING_AGENTS_LOCAL_REMOTES_DIR` to customize the location) to bring changes into your working tree.

---

## Environment Variables

Scripts respect these environment variables:

| Variable | Used By | Purpose |
|----------|---------|---------|
| `DOCKER_BUILDKIT` | build scripts | Enable BuildKit for faster builds |
| `TZ` | all launchers | Timezone (auto-detected if not set) |
| `PATH` | all scripts | Must include launcher directory |
| `HOME` | all scripts | User home directory for configs |
| `USERPROFILE` | Windows scripts | User profile directory |
| `CODING_AGENTS_SECCOMP_PROFILE` | launchers | Override path to seccomp JSON profile |
| `CODING_AGENTS_DISABLE_SECCOMP` | launchers | Set to `1` to skip seccomp (not recommended) |
| `CODING_AGENTS_APPARMOR_PROFILE_NAME` | Linux launchers | Override AppArmor profile name |
| `CODING_AGENTS_APPARMOR_PROFILE_FILE` | Linux launchers | Override AppArmor profile file path |
| `CODING_AGENTS_DISABLE_APPARMOR` | Linux launchers | Set to `1` to skip AppArmor enforcement |

### Setting Environment Variables

**Linux/Mac (temporary):**
```bash
export DOCKER_BUILDKIT=1
export TZ=America/New_York
```

**Linux/Mac (permanent):**
```bash
echo 'export DOCKER_BUILDKIT=1' >> ~/.bashrc
source ~/.bashrc
```

**Windows (temporary):**
```powershell
$env:DOCKER_BUILDKIT = 1
$env:TZ = "America/New_York"
```

**Windows (permanent):**
```powershell
[Environment]::SetEnvironmentVariable("DOCKER_BUILDKIT", "1", "User")
```

---

## Further Reading

- [Getting Started Guide](getting-started.md) - First-time setup
- [Usage Guide](../USAGE.md) - Detailed usage patterns
- [MCP Setup](mcp-setup.md) - Configure MCP servers
- [Troubleshooting](../TROUBLESHOOTING.md) - Common issues
- [Architecture](architecture.md) - How it works
- [Contributing](../CONTRIBUTING.md) - Development guide
