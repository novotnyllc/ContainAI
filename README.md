# AI Coding Agents in Containers

Run AI coding agents (GitHub Copilot, OpenAI Codex, Anthropic Claude) in isolated Docker containers with OAuth authentication and MCP server support.

## Features

- **Multiple agents, no conflicts**: Each agent runs in its own isolated container
- **OAuth authentication**: No API keys needed for agents (uses your existing subscriptions)
- **VS Code integration**: Connect to running containers with Dev Containers extension
- **Persistent workspaces**: Containers run in background, resume anytime
- **MCP servers**: GitHub, Microsoft Docs, Playwright, Context7, Serena, and more
- **Network controls**: Restricted mode (`--network none`) or Squid proxy sidecar for monitoring

## Quick Start

### 1. Setup (one time)

```bash
# Authenticate GitHub CLI
gh auth login

# Configure git
git config --global user.name "Your Name"
git config --global user.email "your@email.com"

# Build images (or use pre-built)
./scripts/build.sh
```

### 2. Add launchers to PATH (optional but recommended)

This lets you run launchers from anywhere:

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

**Quick ephemeral container (auto-removes on exit):**

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

**Persistent container (runs in background):**

```bash
# Navigate to your project
cd ~/my-project

# Launch with default agent (copilot)
launch-agent

# Launch specific agent
launch-agent --agent codex

# Launch on specific branch
launch-agent --branch feature-auth
```

**Container naming:** Containers are named `{agent}-{repo}-{branch}` for easy identification:
- `copilot-myapp-main` - Copilot on myapp repository, main branch
- `codex-website-feature` - Codex on website repository, feature branch
- `claude-api-develop` - Claude on api repository, develop branch

**Auto-push safety:** All containers automatically push uncommitted changes to your local repository before shutting down. Use `--no-push` to disable:
```bash
run-copilot --no-push
launch-agent --no-push
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
- **[docs/BUILD.md](docs/BUILD.md)** - Building and publishing images
- **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** - System design and architecture
- **[docs/NETWORK_PROXY.md](docs/NETWORK_PROXY.md)** - Network modes and Squid proxy
- **[docs/TEST_PLAN.md](docs/TEST_PLAN.md)** - Comprehensive testing procedures

## Examples

**Quick ephemeral sessions:**
```bash
cd ~/my-project
run-copilot              # Launch and work, auto-removes on exit
run-codex --no-push      # Launch without auto-push
```

**Persistent workspaces:**
```bash
cd ~/my-project
launch-agent                           # Default: Copilot on current branch
launch-agent --agent codex             # Codex on current branch
launch-agent --branch feature-auth     # Copilot on feature-auth branch
```

**Multiple agents on same repo:**
```bash
cd ~/my-project
launch-agent --branch main --agent copilot    # copilot-myproject-main
launch-agent --branch auth --agent codex      # codex-myproject-auth
launch-agent --branch api --agent claude      # claude-myproject-api
```

**Container management:**
```bash
list-agents                            # Show all running containers
remove-agent copilot-myproject-main    # Remove with auto-push
remove-agent codex-myproject-auth --no-push  # Remove without push
```

**Network controls:**
```bash
launch-agent --network-proxy restricted   # Block outbound traffic
launch-agent --network-proxy squid        # Proxy with logging
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

- Docker with WSL2 backend (Windows) or Docker Desktop (Mac/Linux)
- GitHub CLI authenticated (`gh auth login`)
- Git configured
- (Optional) Agent-specific OAuth: Copilot, Codex, Claude

## License

MIT

---

**Questions?** See [USAGE.md](USAGE.md) for detailed guide.
