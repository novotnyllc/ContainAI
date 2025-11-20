# AI Coding Agents in Containers

Run AI coding agents (GitHub Copilot, OpenAI Codex, Anthropic Claude) in isolated Docker containers with controlled network access. Each agent operates in its own workspace with branch isolation, enabling multiple agents to work on the same repository without conflicts while maintaining privacy and security.

Containers provide network restrictions (full isolation or monitored proxy access), separate git branches for each agent, and VS Code integration via Dev Containers. Agents can be launched as ephemeral instances that auto-remove on exit, or as persistent background containers for long-running tasks.

Features include MCP server support for extended capabilities, automated git operations, and configurable network policies. All agent activity is contained within Docker, keeping the host environment clean and prompts private.

## Features

- **Multiple agents, no conflicts**: Each agent runs in its own isolated container
- **OAuth authentication**: No API keys needed for agents (uses your existing subscriptions)
- **VS Code integration**: Connect to running containers with Dev Containers extension
- **Persistent workspaces**: Containers run in background, resume anytime
- **Detach & resume**: Built-in tmux sessions plus `connect-agent` let you drop and reconnect without stopping containers
- **MCP servers**: GitHub, Microsoft Docs, Playwright, Context7, Serena, and more
- **Network controls**: Restricted mode (`--network none`) or Squid proxy sidecar for monitoring
- **Broker-enforced secrets**: Session manifests + `mcp-stub` wrappers keep MCP API keys off disk and scoped per container

## Quick Start (5 Minutes)

**New to Docker or containers?** See the [detailed getting started guide](docs/getting-started.md).

**Prerequisites:**
- ✅ Docker installed and running (Desktop on macOS/Windows, Engine on Linux)
- ℹ️  Host Git credentials/config are reused automatically—no container-side setup needed

**Quick verification:**
```bash
./host/utils/verify-prerequisites.sh  # Linux/Mac
.\host\utils\verify-prerequisites.ps1 # Windows
```

**Note:** The verification script only reports what it finds. If it warns that GitHub CLI isn't installed, you can ignore it unless your host actually uses GitHub CLI for auth—the containers just inherit whatever credentials already exist on the host.

**Get running in 2 steps (images auto-pull on first launch):**

```bash
# 1. Install launchers once
./scripts/install.sh        # Linux/Mac
.\scripts\install.ps1      # Windows PowerShell

# 2. Launch an agent from any repository (image pulls automatically)
cd ~/my-project
run-copilot                  # or run-codex / run-claude
```

> **Windows note:** Every `.ps1` in this repository is a thin shim that launches the matching bash script inside your default WSL 2 distribution. Install and enable WSL (`wsl --install`, restart) before running the PowerShell commands above. `scripts\install.ps1` runs the same prerequisite + health checks via WSL and adds `host\launchers` to your user PATH so commands like `run-copilot` work from any PowerShell prompt.

That's it! You're coding with AI in an isolated container. For a deeper walkthrough (network modes, container management, VS Code), read [docs/running-agents.md](docs/running-agents.md).

Behind the scenes the launcher hashed its own files, rendered a per-session MCP manifest on the host, asked the secret broker for sealed capability tokens, copied those artifacts into a tmpfs inside the container, and ensured every MCP server launches through the trusted `mcp-stub`. No raw API keys ever touch your workspace.

**Learn more:** [Usage Guide](USAGE.md) | [Getting Started](docs/getting-started.md) | [Architecture](docs/architecture.md)

---

## Complete Setup Guide

1. **[docs/getting-started.md](docs/getting-started.md)** – full onboarding (Docker install, credential prep, first container) for new users.
2. **[docs/running-agents.md](docs/running-agents.md)** – everyday workflows covering launch patterns, container management, networking modes, and VS Code integration.
3. **[docs/local-build-and-test.md](docs/local-build-and-test.md)** – how to pull or rebuild images and run the unit/integration test suites before submitting a PR.


## Documentation

- **[USAGE.md](USAGE.md)** - Complete user guide (start here!)
- **[docs/getting-started.md](docs/getting-started.md)** - First-time setup walkthrough
- **[docs/running-agents.md](docs/running-agents.md)** - Everyday launcher workflow, networking, and VS Code tips
- **[docs/vscode-integration.md](docs/vscode-integration.md)** - Using VS Code with containers
- **[docs/cli-reference.md](docs/cli-reference.md)** - All command-line options
- **[docs/mcp-setup.md](docs/mcp-setup.md)** - MCP server configuration
- **[docs/local-build-and-test.md](docs/local-build-and-test.md)** - Pulling or rebuilding images plus running tests locally
- **[docs/build.md](docs/build.md)** - Image architecture details and publishing guidance
- **[docs/architecture.md](docs/architecture.md)** - System design and architecture
- **[docs/security-workflows.md](docs/security-workflows.md)** - Mermaid sequence diagrams for launch, secrets, and CI security gates
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

## Security Model Highlights

- **Host-rendered manifests** – `render-session-config.py` hashes trusted launcher/runtime files, merges your `config.toml`, and records a manifest SHA256 before a container is created.
- **Secret broker enforcement** – launchers stage API keys inside the broker, receive sealed capabilities, and copy them into `/run/coding-agents` (tmpfs). Only the trusted `mcp-stub` inside the container can redeem those capabilities.
- **Tight threat boundaries** – secrets live either on the host or inside stub-owned tmpfs mounts. Even if an agent workspace is compromised, it cannot read the manifest, capability bundle, or broker socket.
- **Image secret scanning** – every `coding-agents-*` image must pass `trivy --scanners secret` before tagging/publishing so leaked tokens are caught before distribution.
- **Legacy fallback logged** – the older `setup-mcp-configs.sh` converter still exists for compatibility, but it only runs if the host skips manifest rendering (which the launchers no longer do by default).

## Requirements

- **Container Runtime**: Docker Desktop (macOS/Windows) or Docker Engine (Linux)
  - Scripts require Docker 20.10+ to launch agents
- **socat**: Required for credential and GPG proxy servers
  - Linux/Mac: `apt-get install socat` or `brew install socat`
  - Windows: Available in WSL2 (install in WSL: `sudo apt-get install socat`)
- **Trivy CLI**: Required for automatic secret scanning whenever images are built locally or in tests
  - Install via package manager or `curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sudo sh -s -- -b /usr/local/bin v0.53.0`
- **Host Git credentials**: Whatever you already use (Git config, SSH keys, credential helpers) is mounted automatically—no container-specific setup needed
- **Host authentications**: If you use GitHub Copilot, Claude, Codex, etc., authenticate on the host as usual and the container will reuse those tokens/configs

## License

MIT

---

**Questions?** See [USAGE.md](USAGE.md) for detailed guide.
