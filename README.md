# ContainAI

Secure Docker sandboxes for AI agent execution.

ContainAI provides isolated, secure containers for running AI coding agents like Claude, Gemini, Codex, Copilot, and OpenCode. It enforces sandbox-first execution with fail-closed security defaults.

## Table of Contents

- [Features](#features)
- [Quick Start](#quick-start)
- [Documentation](#documentation)
- [Security](#security)
- [Contributing](#contributing)
- [License](#license)

## Features

- **Sandbox-first execution** - Containers run in Docker Desktop sandbox mode or with Sysbox runtime
- **Multi-agent support** - Works with Claude, Gemini, Codex, Copilot, and OpenCode
- **Credential isolation** - Agent credentials stay inside the container by default
- **Workspace mounting** - Mount your project directory securely into the sandbox
- **Auto-attach behavior** - Reconnect to existing containers automatically

## Quick Start

> **Note:** The CLI requires **bash**. If your default shell is zsh or fish, run `bash` first.

### 1. Source the CLI

```bash
# Clone the repository
git clone https://github.com/novotnyllc/containai.git
cd containai

# Source the ContainAI CLI (adds cai/containai commands)
source agent-sandbox/containai.sh
```

### 2. Check your environment

```bash
cai doctor
```

This detects your Docker configuration and confirms sandbox availability.

### 3. Start and authenticate

```bash
# Navigate to your project directory
cd /path/to/your/project

# Start the sandbox
cai

# On first run, authenticate inside the container
# (e.g., run 'claude login' for Claude)
```

The sandbox mounts your current directory and starts the configured AI agent.

## Documentation

For detailed documentation, see the [Technical README](agent-sandbox/README.md), which covers:

- Prerequisites and installation
- Commands and usage
- Volume management
- Port forwarding
- Security model
- Troubleshooting
- Image building and testing

## Security

ContainAI is a security-focused tool with fail-closed defaults:

- **Sandbox-first**: Containers run in Docker Desktop sandbox mode or Sysbox runtime
- **Credential isolation**: Agent credentials stay inside the container by default
- **TOCTOU protection**: Volume mounts are protected against symlink attacks
- **Safe config parsing**: Environment files are validated before use

Unsafe operations require explicit opt-in flags (`--allow-host-credentials`, `--allow-host-docker-socket`, `--force`).

## Contributing

Contributions are welcome. To get started:

1. Fork the repository
2. Create a feature branch
3. Make your changes with tests
4. Submit a pull request

See the [Technical README](agent-sandbox/README.md) for development setup.

## License

This project is licensed under the MIT License.
