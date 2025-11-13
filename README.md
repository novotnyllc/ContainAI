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

### 2. Launch an agent

```powershell
# PowerShell
.\launch-agent.ps1

# Bash
./launch-agent
```

### 3. Connect from VS Code

1. Install **Dev Containers** extension
2. Click remote button (bottom-left)
3. Select "Attach to Running Container"
4. Choose your container

## Documentation

- **[USAGE.md](USAGE.md)** - Complete user guide (start here!)
- **[docs/BUILD.md](docs/BUILD.md)** - Building and publishing images
- **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** - System design and architecture
- **[docs/NETWORK_PROXY.md](docs/NETWORK_PROXY.md)** - Network modes and Squid proxy
- **[docs/TEST_PLAN.md](docs/TEST_PLAN.md)** - Comprehensive testing procedures

## Examples

Launch Copilot on current directory:
```powershell
.\launch-agent.ps1 . --agent copilot
```

Multiple agents on same repo:
```powershell
.\launch-agent.ps1 . -b auth --agent copilot
.\launch-agent.ps1 . -b database --agent codex
```

Network controls:
```powershell
# Restrict outbound traffic
.\launch-agent.ps1 . --network-proxy restricted

# Proxy with logging
.\launch-agent.ps1 . --network-proxy squid
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
