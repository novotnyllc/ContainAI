# ContainAI

**Run AI coding agents without risking your system.**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

AI coding agents like Claude, Gemini, and Codex can execute arbitrary code on your machine. That's powerful—but dangerous. ContainAI puts them in a secure Docker sandbox with fail-closed defaults, so an agent can't accidentally (or maliciously) damage your system, leak credentials, or access files you didn't intend to share.

## Why ContainAI?

| Problem | ContainAI Solution |
|---------|-------------------|
| Agents can access your entire filesystem | Workspace mount limits access to your project directory |
| Agents can read your SSH keys, API tokens, cloud credentials | Credential isolation keeps host secrets out by default |
| Agents can run any command with your privileges | Sandbox runs in isolated runtime with restricted privileges |
| Agent escapes container via Docker socket | Docker socket denied by default |
| Misconfigured agents weaken security | Safe defaults enforced; dangerous config options are ignored |

## Quick Start

> **Note:** The CLI requires **bash** (not zsh or fish). If your default shell is zsh, run `bash` first.

```bash
# Clone and source the CLI (must be in bash)
git clone https://github.com/novotnyllc/containai.git && cd containai
source src/containai.sh

# Start the sandbox in your project
cd /path/to/your/project
cai
```

That's it. ContainAI detects your isolation runtime (Docker Desktop sandbox or Sysbox), mounts your current directory, and starts Claude. First run? Authenticate inside the container with `claude login`.

> **Requires bash 4.0+.** macOS ships with bash 3.2; install via `brew install bash`.

## Features

- **Sandbox-first execution** — Containers run in Docker Desktop sandbox mode or with Sysbox runtime. Fail-closed: blocks if no isolation available.
- **Multi-agent support** — Works with Claude, Gemini, Codex, Copilot, and OpenCode. Switch with `cai --agent gemini`.
- **Credential isolation** — Agent credentials stay inside the container by default. Host credentials require explicit opt-in (see Security section).
- **Workspace mounting** — Only your current project directory is mounted. Symlink traversal attacks are blocked.
- **Auto-attach** — Reconnect to existing containers automatically. `cai --restart` for a fresh start.
- **Persistent data volume** — Agent plugins, settings, and credentials survive container restarts.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Your Host Machine                       │
│                                                             │
│  ~/.ssh, ~/.aws, etc.    ← NOT accessible to agent         │
│                                                             │
│  ┌────────────────────────────────────────────────────────┐ │
│  │              Docker Desktop / Sysbox                   │ │
│  │  ┌──────────────────────────────────────────────────┐  │ │
│  │  │            ContainAI Sandbox                      │  │ │
│  │  │                                                   │  │ │
│  │  │  ~/workspace      ← Your project (read/write)     │  │ │
│  │  │  /mnt/agent-data  ← Persistent volume (creds)     │  │ │
│  │  │  AI Agent         ← Claude/Gemini/Codex           │  │ │
│  │  │                                                   │  │ │
│  │  └──────────────────────────────────────────────────┘  │ │
│  └────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

The agent sees only your project and its own data volume. Host credentials, Docker socket, and other sensitive resources are isolated by default.

## Requirements

| Requirement | Version | Notes |
|-------------|---------|-------|
| Docker | Desktop 4.50+ or Engine 24.0+ | Sandbox feature or Sysbox required |
| Bash | 4.0+ | macOS default is 3.2; use `brew install bash` |
| Git | Any | Recommended (for container naming) |

**Isolation runtime (one required):**
- **Docker Desktop** with sandbox feature enabled (Settings → Features in development), OR
- **Sysbox** runtime (`cai setup` installs it on Linux/WSL2)

## Documentation

| Document | Description |
|----------|-------------|
| [Quickstart Guide](docs/quickstart.md) | Detailed setup with environment checks |
| [Architecture](docs/architecture.md) | System design, data flow, security boundaries |
| [Configuration](docs/configuration.md) | Config file options, volume selection |
| [Technical README](src/README.md) | Image building, DinD, and CLI internals |
| [Security Model](SECURITY.md) | Threat model and vulnerability reporting |

## Common Commands

```bash
cai                      # Start or attach to sandbox
cai --restart            # Force recreate container
cai --agent gemini       # Use a different agent
cai doctor               # Check system capabilities
cai shell                # Open bash shell in running sandbox
cai import               # Sync host dotfiles to data volume
cai stop --all           # Stop all ContainAI containers
```

## Security

ContainAI enforces safe defaults that cannot be weakened via config files:

- **Credential isolation**: Host `~/.ssh`, `~/.aws`, API tokens are not accessible
- **Docker socket denied**: No container escape via Docker socket
- **TOCTOU protection**: Symlink traversal attacks blocked in entrypoint
- **Fail-closed**: Blocks if sandbox unavailable or status unknown

Unsafe operations require explicit CLI flags with acknowledgment:
- `--allow-host-credentials` + `--i-understand-this-exposes-host-credentials`
- `--allow-host-docker-socket` + `--i-understand-this-grants-root-access`

See [SECURITY.md](SECURITY.md) for the full threat model.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup and guidelines.

## License

MIT License — see [LICENSE](LICENSE).
