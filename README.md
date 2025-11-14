# AI Coding Agents in Containers

Run AI coding agents (GitHub Copilot, OpenAI Codex, Anthropic Claude) in isolated Docker containers with controlled network access. Each agent operates in its own workspace with branch isolation, enabling multiple agents to work on the same repository without conflicts while maintaining privacy and security.

Containers provide network restrictions (full isolation or monitored proxy access), separate git branches for each agent, and VS Code integration via Dev Containers. Agents can be launched as ephemeral instances that auto-remove on exit, or as persistent background containers for long-running tasks.

Features include MCP server support for extended capabilities, automated git operations, and configurable network policies. All agent activity is contained within Docker, keeping the host environment clean and prompts private.

## Features

- **Multiple agents, no conflicts**: Each agent runs in its own isolated container
- **OAuth authentication**: No API keys needed for agents (uses your existing subscriptions)
- **VS Code integration**: Connect to running containers with Dev Containers extension
- **Persistent workspaces**: Containers run in background, resume anytime
- **MCP servers**: GitHub, Microsoft Docs, Playwright, Context7, Serena, and more
- **Network controls**: Restricted mode (`--network none`) or Squid proxy sidecar for monitoring

## Quick Start (5 Minutes)

**New to Docker or containers?** See the [detailed getting started guide](docs/getting-started.md).

**Prerequisites:**
- ✅ Docker (or Podman) installed and running
- ✅ Git configured (`user.name`, `user.email`)
- ℹ️  GitHub CLI authenticated (`gh auth login`) - **Only if using GitHub Copilot or GitHub-hosted repos**

**Quick verification:**
```bash
./scripts/verify-prerequisites.sh  # Linux/Mac
.\scripts\verify-prerequisites.ps1 # Windows
```

**Note:** The verification script will warn if GitHub CLI is missing, but this is only required for GitHub Copilot. Other agents work without it.

**Get running in 3 steps:**

```bash
# 1. Pull image (1 minute)
docker pull ghcr.io/novotnyllc/coding-agents-copilot:latest

# 2. Install launchers (30 seconds)
./scripts/install.sh        # Linux/Mac
.\scripts\install.ps1       # Windows PowerShell

# 3. Launch agent (instant)
cd ~/my-project
run-copilot
```

That's it! You're coding with AI in an isolated container.

**Learn more:** [Usage Guide](USAGE.md) | [Getting Started](docs/getting-started.md) | [Architecture](docs/architecture.md)

---

## Complete Setup Guide

### 1. Prerequisites (one time)

**Required:**

```bash
# Configure git
git config --global user.name "Your Name"
git config --global user.email "your@email.com"
```

**For GitHub Copilot (optional):**

```bash
# Authenticate GitHub CLI - only needed for GitHub Copilot
gh auth login
```

**For other agents (optional):**

Authenticate on your host machine if you want to use these agents:

```bash
# For OpenAI Codex (if you have access)
# Follow authentication instructions for the Codex CLI
# Config stored at ~/.config/codex/

# For Anthropic Claude (if you have access)  
# Follow authentication instructions for the Claude CLI
# Config stored at ~/.config/claude/
```

> **Note:** Agent authentication configs are mounted read-only into containers. You must authenticate on your host machine first.

**Get the images:**

```bash
# Option 1: Pull pre-built (recommended)
docker pull ghcr.io/novotnyllc/coding-agents-copilot:latest

# Option 2: Build locally
./scripts/build.sh  # Linux/macOS
.\scripts\build.ps1 # Windows
```

### 2. Add launchers to PATH (optional but recommended)

This lets you run launchers from anywhere:

```bash
# Linux/macOS
./scripts/install.sh

# Windows (PowerShell)
.\scripts\install.ps1
```

Or manually add to PATH:

**Windows (PowerShell):**
```powershell
# Temporary (current session)
$env:PATH += ";$PWD\scripts\launchers"

# Permanent: Add to System Environment Variables via GUI
# Or add to PowerShell profile
```

**Linux/macOS:**
```bash
# Temporary (current session)
export PATH="$PWD/scripts/launchers:$PATH"

# Permanent: Add to ~/.bashrc or ~/.zshrc
echo 'export PATH="$HOME/coding-agents/scripts/launchers:$PATH"' >> ~/.bashrc
```

### 3. Launch an agent

**Recommended: Quick ephemeral container (auto-removes on exit):**

```bash
# Navigate to your project
cd ~/my-project

# Launch agent (defaults to current directory)
run-copilot    # GitHub Copilot
run-codex      # OpenAI Codex
run-claude     # Anthropic Claude

# PowerShell equivalent
run-copilot.ps1
```

**Advanced: Persistent container (runs in background):**

For long-running tasks or when you need advanced features like branch management or network controls:

```bash
# Navigate to your project
cd ~/my-project

# Launch with specific agent (required)
launch-agent copilot

# Launch different agent
launch-agent codex

# Launch on specific branch
launch-agent copilot --branch feature-api
```

**Branch isolation:** Agents work on isolated branches (e.g., `copilot/session-1`, `codex/feature-api`) to keep agent work separate from your current branch.

**Container naming:** Containers are named `{agent}-{repo}-{branch}` for easy identification:
- `copilot-myapp-main` - Copilot on myapp repository, main branch
- `codex-website-feature` - Codex on website repository, feature branch
- `claude-api-develop` - Claude on api repository, develop branch

**Auto-push safety:** All containers automatically push uncommitted changes to your local repository before shutting down. Use `--no-push` to disable:
```bash
run-copilot --no-push
launch-agent copilot --no-push
```

### 4. Manage containers

```bash
# List all running agent containers
list-agents

# Remove a container (auto-pushes changes first)
remove-agent copilot-myapp-main

# Skip auto-push when removing
remove-agent copilot-myapp-main --no-push
```

### 5. Connect from VS Code

1. Install **Dev Containers** extension
2. Click remote button (bottom-left)
3. Select "Attach to Running Container"
4. Choose your container (e.g., `copilot-myapp-main`)

## Documentation

- **[USAGE.md](USAGE.md)** - Complete user guide (start here!)
- **[docs/getting-started.md](docs/getting-started.md)** - First-time setup walkthrough
- **[docs/vscode-integration.md](docs/vscode-integration.md)** - Using VS Code with containers
- **[docs/cli-reference.md](docs/cli-reference.md)** - All command-line options
- **[docs/mcp-setup.md](docs/mcp-setup.md)** - MCP server configuration
- **[docs/build.md](docs/build.md)** - Building and publishing images
- **[docs/architecture.md](docs/architecture.md)** - System design and architecture
- **[docs/network-proxy.md](docs/network-proxy.md)** - Network modes and Squid proxy
- **[scripts/test/README.md](scripts/test/README.md)** - Automated test suite (CI and local)
- **[CONTRIBUTING.md](CONTRIBUTING.md)** - Development guidelines

## Examples

**Recommended: Quick ephemeral sessions:**
```bash
cd ~/my-project
run-copilot              # Launch and work, auto-removes on exit
run-codex --no-push      # Launch without auto-push
run-claude ~/other-proj  # Launch on specific directory
```

**Advanced: Persistent workspaces (for long-running tasks):**
```bash
cd ~/my-project
launch-agent copilot                      # Copilot on current branch
launch-agent codex                        # Codex on current branch
launch-agent copilot --branch feature-api  # Copilot on feature-api branch
```

**Multiple agents on same repo:**
```bash
cd ~/my-project
launch-agent copilot --branch main     # copilot-myproject-main
launch-agent codex --branch api-v2     # codex-myproject-api-v2
launch-agent claude --branch refactor  # claude-myproject-refactor
```

**Advanced: Network controls:**
```bash
launch-agent copilot --network-proxy restricted   # Block outbound traffic
launch-agent copilot --network-proxy squid        # Proxy with logging
```

**Container management (for persistent containers):**
```bash
list-agents                            # Show all running containers
remove-agent copilot-myproject-main    # Remove with auto-push
remove-agent codex-myproject-auth --no-push  # Remove without push
```

See [USAGE.md](USAGE.md) for complete examples and advanced scenarios.

## What's Different

Unlike running agents directly on your machine:

- ✅ **Isolated**: Each agent has its own workspace
- ✅ **No conflicts**: Multiple agents can work on same repo
- ✅ **Clean**: Delete container when done, no leftovers
- ✅ **Reproducible**: Same environment everywhere
- ✅ **Connectable**: VS Code Remote works out of the box

## Requirements

- **Container Runtime**: Docker or Podman
  - Docker Desktop (with WSL2 on Windows) or Podman Desktop/CLI
  - Scripts auto-detect available runtime
- GitHub CLI authenticated (`gh auth login`)
- Git configured
- (Optional) Agent-specific OAuth: Copilot, Codex, Claude

## License

MIT

---

**Questions?** See [USAGE.md](USAGE.md) for detailed guide.
