# Command-Line Reference

Complete reference for all ContainAI launcher scripts and their arguments.

> **Windows note:** `.ps1` entrypoints are shims that invoke the bash scripts inside your default WSL 2 distro. They no longer implement independent PowerShell parameter parsing—pass the same GNU-style flags documented for bash (for example `--prompt`, `--network-proxy squid`). When running from PowerShell, prepend `--%` before the first flag so PowerShell stops interpreting the arguments: `pwsh host\launchers\entrypoints\run-copilot-dev.ps1 --% --prompt "Status"`. Running `scripts\install.ps1` adds the shim directory to your PATH so these commands are available globally.
>
> **Channels:** Launcher entrypoints live under `host/launchers/entrypoints`. In repo clones use the `-dev` names (e.g., `run-copilot-dev`), prod bundles drop the suffix (`run-copilot`), and nightly builds use `-nightly`. Use `host/utils/prepare-entrypoints.sh --channel nightly|prod` when you need to generate alternate names.

## Table of Contents

- [Quick Launch Scripts](#quick-launch-scripts)
  - [run-copilot-dev](#run-copilot-dev) (use run-copilot/run-copilot-nightly in packaged channels)
  - [run-codex-dev](#run-codex-dev)
  - [run-claude-dev](#run-claude-dev)
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

> **Auto-update:** Launchers check whether the ContainAI repository is behind its upstream before starting and prompt you to sync. Configure the behavior via `~/.config/containai/host-config.env` (Linux/macOS) or `%USERPROFILE%\.config\containai\host-config.env` (Windows) by setting `LAUNCHER_UPDATE_POLICY=prompt|always|never`.

### run-copilot-dev

Launch GitHub Copilot CLI in the current directory.

**Location:** `host/launchers/entrypoints/run-copilot-<channel>` (bash), `host/launchers/entrypoints/run-copilot-<channel>.ps1` (PowerShell) where `<channel>` is `dev` in repo clones, empty in prod bundles, or `nightly` for nightly builds.

#### Synopsis

```bash
run-copilot-dev [REPO_PATH] [OPTIONS]
```

```powershell
.\host\launchers\entrypoints\run-copilot-dev.ps1 [[-RepoPath] <String>] [OPTIONS]
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
| `--network-proxy MODE` (bash)<br>`-NetworkProxy MODE` (PowerShell) | string | `squid` | Network mode: `squid`, `restricted` |
| `--cpu NUM` (bash)<br>`-Cpu NUM` (PowerShell) | string | `4` | CPU limit (e.g., `2`, `4`, `8`, `0.5`) |
| `--memory SIZE` (bash)<br>`-Memory SIZE` (PowerShell) | string | `8g` | Memory limit (e.g., `4g`, `8g`, `16g`) |
| `--gpu SPEC` (bash)<br>`-Gpu SPEC` (PowerShell) | string | none | GPU specification (e.g., `all`, `device=0`, `device=0,1`) |
| `--no-push` (bash)<br>`-NoPush` (PowerShell) | flag | false | Skip auto-push to git remote on exit |
| `--use-current-branch` (bash)<br>`-UseCurrentBranch` (PowerShell) | flag | false | Use current branch (no isolation) |
| `--prompt PROMPT` (bash)<br>`-Prompt PROMPT` (PowerShell) | string | none | Non-interactive prompt run (auto CLI execution, reuses repo when available, automatic shutdown) |
| `-y, --force` (bash)<br>`-Force` (PowerShell) | flag | false | Replace existing branch without prompt |
| `-h, --help` (bash)<br>`-Help` (PowerShell) | flag | false | Show help message |

#### Examples

**Basic usage:**
```bash
# Launch in current directory
run-copilot-dev

# Launch in specific directory
run-copilot-dev ~/my-project
run-copilot-dev /path/to/repo

# Windows
.\host\launchers\entrypoints\run-copilot-dev.ps1 C:\Projects\MyApp
```

**With branch isolation:**
```bash
# Create copilot/feature branch
run-copilot-dev -b feature

# Use current branch (no isolation)
run-copilot-dev --use-current-branch

# Windows
.\host\launchers\entrypoints\run-copilot-dev.ps1 -Branch feature
.\host\launchers\entrypoints\run-copilot-dev.ps1 -UseCurrentBranch
```

**With custom name:**
```bash
# Custom container name
run-copilot-dev --name my-session

# Windows
.\host\launchers\entrypoints\run-copilot-dev.ps1 -Name my-session
```

**With network controls:**
```bash
# Restricted network (no internet)
run-copilot-dev --network-proxy restricted

# Monitored proxy
run-copilot-dev --network-proxy squid

# Windows
.\host\launchers\entrypoints\run-copilot-dev.ps1 -NetworkProxy restricted
```

**With resource limits:**
```bash
# More CPUs and memory
run-copilot-dev --cpu 8 --memory 16g

# Minimal resources
run-copilot-dev --cpu 2 --memory 4g

# Windows
.\host\launchers\entrypoints\run-copilot-dev.ps1 -Cpu 8 -Memory 16g
```

**With GPU:**
```bash
# Use all GPUs
run-copilot-dev --gpu all

# Specific GPU
run-copilot-dev --gpu device=0

# Windows
.\host\launchers\entrypoints\run-copilot-dev.ps1 -Gpu all
```

**Disable auto-push:**
```bash
# Skip git push on exit
run-copilot-dev --no-push

# Windows
.\host\launchers\entrypoints\run-copilot-dev.ps1 -NoPush
```

**Combined options:**
```bash
# Full example
run-copilot-dev ~/my-project -b feature-api --cpu 8 --memory 16g --network-proxy squid

# Windows
.\host\launchers\entrypoints\run-copilot-dev.ps1 C:\Projects\MyApp -Branch feature-api -Cpu 8 -Memory 16g -NetworkProxy squid

# Ask a one-off question (no repo required)
run-copilot-dev --prompt "Return the words: host secrets OK."
# Equivalent Codex/Claude examples
run-codex-dev --prompt "Summarize CONTRIBUTING.md"
run-claude-dev --prompt "List repo services that need MCP"
```

#### Behavior

1. Validates the path exists and is a git repository whenever a repo is involved (prompt sessions reuse the same validation and only fall back to an empty workspace when no repo is detected)
2. Pulls latest `containai-copilot:local` image
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

> **Auto-push storage:** For local repositories, commits are written to `~/.containai/local-remotes/<repo-hash>.git`. Fetch from that bare repo to bring changes back into your working tree, or set `CONTAINAI_LOCAL_REMOTES_DIR` before launching to change the location.

> **Upstream access:** The container starts without any GitHub origin remote. Only the managed `local` remote is configured so you must publish from the host repository (or explicitly add a remote yourself inside the container).

> **Host sync:** After every push to `local`, the host working tree fast-forwards automatically unless you set `CONTAINAI_DISABLE_AUTO_SYNC=1`.

**Prompt sessions (all agents):** Passing `--prompt "<prompt>"` (bash) or `-Prompt "<prompt>"` (PowerShell) auto-runs the agent-specific CLI (`github-copilot-cli exec "$prompt"`, `codex exec "$prompt"`, or `claude -p "$prompt"`). When you launch it from inside a Git repository (or pass a repo/SOURCE argument), the workspace mirrors a normal session with branch isolation, auto-commit, and auto-push (unless you explicitly pass `--no-push`). If no repo exists, the launcher falls back to a synthetic empty workspace, disables auto-push because there is nowhere to push, and still tears down the container as soon as the CLI returns—perfect for diagnostics and the `--with-host-secrets` integration path.

**Reattach later:** `connect-agent --name <container>` reconnects to the tmux session if the container is still running (for example, if you detached with `Ctrl+B`, `D`).

**Branch Behavior:**
- Without `-b`: Works on current branch (same as `--use-current-branch`)
- With `-b feature`: Creates `copilot/feature` branch for isolation
- Branch management same as [`launch-agent`](#launch-agent)

#### Container Details

- **Name:** `copilot-{repo}-{branch}`
- **Image:** `containai-copilot:local`
- **Working Dir:** `/workspace`
- **Network:** Bridge (internet access)
- **Security:** `no-new-privileges:true`, seccomp `host/profiles/seccomp-containai-agent.json`, AppArmor profile `containai-agent-<channel>` 
- **Removal:** Automatic on exit (`--rm`)

---

### run-codex

Launch OpenAI Codex in the current directory.

**Location:** `host/launchers/run-codex` (bash), `host/launchers/run-codex.ps1` (PowerShell)

#### Synopsis

```bash
run-codex [REPO_PATH] [OPTIONS]
```

```powershell
.\run-codex.ps1 [[-RepoPath] <String>] [OPTIONS]
```

#### Arguments and Options

See [run-copilot-dev](#run-copilot-dev) - identical arguments and options, just different agent.

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

All [run-copilot-dev](#run-copilot-dev) examples apply - just replace `run-copilot-dev` with `run-codex-dev`.

#### Container Details

- **Name:** `codex-{repo}-{branch}` or `codex-{name}`
- **Image:** `containai-codex:local`
- Same behavior as `run-copilot`

---

### run-claude

Launch Anthropic Claude in the current directory.

**Location:** `host/launchers/run-claude` (bash), `host/launchers/run-claude.ps1` (PowerShell)

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

All [run-copilot-dev](#run-copilot-dev) examples apply - just replace `run-copilot-dev` with `run-claude-dev`.

#### Container Details

- **Name:** `claude-{repo}-{branch}` or `claude-{name}`
- **Image:** `containai-claude:local`
- Same behavior as `run-copilot`

---

## Advanced Launch Script

Persistent containers for long-running work with VS Code integration.

### launch-agent

Launch an agent in a persistent background container with branch isolation.

**Location:** `host/launchers/launch-agent` (bash), `host/launchers/launch-agent.ps1` (PowerShell)

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
| `--network-proxy MODE` (bash)<br>`-NetworkProxy MODE` (PowerShell) | string | `squid` | Network mode: `squid`, `restricted` |
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
| `squid` | Monitored proxy | Default, audit network requests, full access |
| `restricted` | Allowlist only | Maximum security, restricted domains only |

#### Integrity, Audit, and Overrides

- **Trusted file enforcement:** Before starting a container, `launch-agent` checks that `host/launchers/**`, stub helpers, and `host/profiles/**` match `HEAD`. If anything is dirty, the launch aborts unless you create an override token at `~/.config/containai/overrides/allow-dirty` (configurable via `CONTAINAI_DIRTY_OVERRIDE_TOKEN`). Every override is logged.
- **Session manifest logging:** The host renders a per-session config, computes its SHA256, exports it via `CONTAINAI_SESSION_CONFIG_SHA256`, and writes a `session-config` event to the audit log. Compare this hash with what helper tooling reports to ensure configs were not tampered with in transit.
- **Audit log location:** Structured JSON events (`session-config`, `capabilities-issued`, `override-used`) are appended to `~/.config/containai/security-events.log`. Override via `CONTAINAI_AUDIT_LOG=/path/to/file` if you need alternate storage. All events are also forwarded to `systemd-cat -t containai-launcher` when available.
- **Helper sandbox controls:** By default helper containers run with `--network none`, tmpfs-backed `/tmp` + `/var/tmp`, `--cap-drop ALL`, and the ptrace-blocking seccomp profile. Tune with environment variables before launching:
  - `CONTAINAI_HELPER_NETWORK_POLICY=loopback|none|host|bridge|<docker-network>`
  - `CONTAINAI_HELPER_PIDS_LIMIT` (default `64`)
  - `CONTAINAI_HELPER_MEMORY` (default `512m`)

To inspect recent events quickly:

```bash
tail -f ~/.config/containai/security-events.log
```

Run `bash scripts/test/test-launchers.sh --list` to discover available launcher tests, then provide `all` or explicit names (for example, `bash scripts/test/test-launchers.sh test_agent_data_packager test_helper_network_isolation`) after modifying launcher logic. PowerShell users can do the same with `pwsh scripts/test/test-launchers.ps1 -List` and `pwsh scripts/test/test-launchers.ps1 Test-SecretBrokerCli`.

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
  ./scripts/build/build-dev.sh --agents copilot,proxy


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
- Terminal: `host/launchers/connect-agent --name {container-name}` (preferred) or `docker exec -it {container-name} bash`

**Stop container:**
```bash
docker stop {container-name}
# Auto-commits and pushes changes (unless --no-push)
```

#### Container Details

- **Name:** `{agent}-{repo}-{branch}` or `{agent}-{name}`
- **Image:** `containai-{agent}:local`
- **Working Dir:** `/workspace`
- **Command:** `sleep infinity` (runs in background)
- **Removal:** Manual (`docker rm`) after stop
- **Persistence:** Data survives container restarts

---

## Management Scripts

### list-agents

List all running agent containers.

**Location:** `host/launchers/list-agents` (bash), `host/launchers/list-agents.ps1` (PowerShell)

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

**Location:** `host/launchers/remove-agent` (bash), `host/launchers/remove-agent.ps1` (PowerShell)

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

**Location:** `host/launchers/connect-agent` (bash), `host/launchers/connect-agent.ps1` (PowerShell)

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

1. Validates Docker is running
2. Detects running agent containers (label `containai.type=agent`)
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

**Location:** `host/utils/verify-prerequisites.sh` (bash), `host/utils/verify-prerequisites.ps1` (PowerShell)

#### Synopsis

```bash
./host/utils/verify-prerequisites.sh
```

```powershell
.\host\utils\verify-prerequisites.ps1
```

#### No Arguments

This script takes no arguments.

#### Checks

**Required:**
- ✅ Docker installed and version ≥20.10.0
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
✓ Container daemon is running
✓ Git installed (version 2.43.0)
✓ Git user.name configured: John Doe
✓ Git user.email configured: john@example.com
⚠ GitHub CLI not installed (optional - only needed for GitHub Copilot/authentication)
✓ Disk space available: 42.5 GB

✅ Core prerequisites met! You're ready to use ContainAI.
⚠ 1 optional tool missing (see above)
```

---

### install

Add launcher scripts to PATH or install from a packaged release.

**Locations:**
- Bootstrap (curlable): `install.sh` (bash) - downloads the release bundle and runs the installer
- Dev/local: `scripts/setup-local-dev.sh` (bash), `scripts/setup-local-dev.ps1` (PowerShell)

#### Synopsis

```bash
# End-user install (latest release)
curl -fsSL https://raw.githubusercontent.com/ContainAI/ContainAI/main/install.sh | bash

# Pin a version
curl -fsSL https://raw.githubusercontent.com/ContainAI/ContainAI/main/install.sh | bash -s -- --version vX.Y.Z

# Dev/local install from a checked-out repo
./scripts/setup-local-dev.sh [OPTIONS]
```

```powershell
.\scripts\install.ps1 [OPTIONS]
```

#### Options

| Option | Type | Description |
|--------|------|-------------|
| `-h, --help` (bash)<br>`-Help` (PowerShell) | flag | Show help |

#### Behavior
**Bootstrap (install.sh):**
- Downloads `containai-<version>.tar.gz` from GitHub Releases (defaults to latest tag)
- Extracts payload and runs the bundled `host/utils/install-release.sh` with the local assets (no repo/git required)
- Installs into `/opt/containai` by default (override via `CONTAINAI_INSTALL_ROOT` or `--install-root`)

**Linux/Mac:**
- Detects shell (bash or zsh)
- Adds `export PATH="$REPO/host/launchers:$PATH"` to rc file
- Prints instructions to reload shell

**Windows:**
- Adds `$REPO\host\launchers` to User PATH (registry)
- Changes take effect in new PowerShell windows

#### Examples

```bash
# Install on Linux/Mac
./scripts/setup-local-dev.sh

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
echo 'export PATH="/path/to/ContainAI/host/launchers:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

**Mac (zsh):**
```bash
echo 'export PATH="/path/to/ContainAI/host/launchers:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

**Windows (PowerShell - Temporary):**
```powershell
$env:PATH += ";E:\dev\ContainAI\host\launchers"
```

**Windows (PowerShell - Permanent):**
```powershell
[Environment]::SetEnvironmentVariable(
    "Path",
    "$env:PATH;E:\dev\ContainAI\host\launchers",
    [EnvironmentVariableTarget]::User
)
```

---

## Build Scripts

### build

Build container images from source.

**Location:** `scripts/build/build-dev.sh` (bash), `scripts/build/build-dev.ps1` (PowerShell) — dev-only; prod builds are CI-managed.

#### Synopsis

```bash
./scripts/build/build-dev.sh [OPTIONS]
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
- Specialized images depend on `containai:local` and will trigger its build automatically.

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

1. **Base image** (`containai-base:local`) – only when building agent images
2. **All-agents image** (`containai:local`) – prerequisite for agent-specific images
3. **Selected specialized images** – `containai-copilot:local`, `containai-codex:local`, `containai-claude:local`
4. **Proxy image** (`containai-proxy:local`) – built when requested

#### Examples

```bash
# Build all images (Linux/Mac)
./scripts/build/build-dev.sh

# Build all images (Windows)
.\scripts\build\build.ps1

# With BuildKit (faster, better caching)
DOCKER_BUILDKIT=1 ./scripts/build/build-dev.sh

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
  containai-base:local
  containai:local
  containai-copilot:local
  containai-codex:local
  containai-claude:local
  containai-proxy:local

Next steps:
  1. Install launchers: ./scripts/setup-local-dev.sh
  2. Launch an agent:   run-copilot-dev (use run-copilot in prod bundles)
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
4. Pushes to the per-repo bare remote under `~/.containai/local-remotes` (unless `--no-push`)
5. Container auto-removes (`--rm`)

4. Starts a managed tmux session so you can detach/reconnect (`Ctrl+B`, then `D`)
1. Container keeps running in background
2. On `docker stop`:
   - Entrypoint receives SIGTERM
   - Commits changes
  - Pushes to the secure bare remote (unless `--no-push`)
3. Container stops but persists
4. Manual removal: `docker rm`

**Note:** Git now pushes to the managed bare repo path automatically. Fetch from that path (or set `CONTAINAI_LOCAL_REMOTES_DIR` to customize the location) to bring changes into your working tree.

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

AppArmor and seccomp enforcement are mandatory for every launch. The built-in
 profiles under `host/profiles/` must exist on the host; rerun
`scripts/setup-local-dev.sh` if the assets are missing.

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
- [Usage Guide](../../USAGE.md) - Detailed usage patterns
- [MCP Setup](mcp-setup.md) - Configure MCP servers
- [Troubleshooting](troubleshooting.md) - Common issues
- [Architecture](architecture.md) - How it works
- [Contributing](../../CONTRIBUTING.md) - Development guide
