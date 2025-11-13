# CodingAgents Project Overview

## Purpose
Run AI coding agents (GitHub Copilot, OpenAI Codex, Anthropic Claude) in isolated Docker/Podman containers with OAuth authentication and MCP (Model Context Protocol) server support.

## Key Features
- **Multiple agents without conflicts**: Each agent runs in isolated containers
- **OAuth authentication**: Uses existing subscriptions, no API keys needed
- **VS Code integration**: Connect via Dev Containers extension
- **Persistent workspaces**: Background containers, resume anytime
- **MCP servers**: GitHub, Microsoft Docs, Playwright, Context7, Serena, Sequential Thinking
- **Network controls**: Restricted mode or Squid proxy sidecar for monitoring
- **Auto-push safety**: Automatically pushes uncommitted changes before shutdown

## Tech Stack
- **Container Runtime**: Docker or Podman (auto-detected)
- **Scripting**: Bash (Linux/Mac/WSL) and PowerShell (Windows) with full parity
- **Base Image**: Ubuntu 22.04 LTS
- **Config Format**: TOML (config.toml) converted to agent-specific JSON
- **Version Control**: Git with dual remotes (local + origin)
- **Testing**: Bash and PowerShell unit tests + bash integration tests

## Repository Structure
```
coding-agents/
├── agent-configs/       # Custom instructions for AI agents (deployed to containers)
├── docker/             # Container definitions and compose files
│   ├── base/          # Base image Dockerfile
│   └── agents/        # Per-agent Dockerfiles (copilot, codex, claude)
├── scripts/
│   ├── launchers/     # User-facing scripts (bash + PowerShell)
│   ├── utils/         # Shared functions libraries
│   ├── runtime/       # Container entrypoint and startup scripts
│   ├── test/          # Unit and integration tests
│   └── build/         # Build scripts
├── docs/              # Documentation (ARCHITECTURE.md, BUILD.md, etc.)
├── config.toml        # MCP server configuration template
├── AGENTS.md          # Repository-specific agent instructions
├── README.md          # User guide
├── USAGE.md           # Detailed usage documentation
└── CONTRIBUTING.md    # Development guidelines
```

## System
- **Platform**: Cross-platform (Windows, Linux, macOS)
- **Windows**: WSL2 required for best compatibility
- **PowerShell**: 7+ recommended
- **Bash**: 4.0+ required
