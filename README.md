# ContainAI

Secure Docker sandboxes for AI agent execution.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

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

### 2. Authenticate your agent

```bash
# Start the sandbox
cai

# Inside the container, log in to your agent
claude login
```

### 3. Run in your project

```bash
# Navigate to your project directory
cd /path/to/your/project

# Start the sandbox
cai
```

The sandbox mounts your current directory and starts the configured AI agent.

## Documentation

| Document | Description |
|----------|-------------|
| [Quickstart Guide](docs/quickstart.md) | Getting started guide |
| [Technical README](agent-sandbox/README.md) | Image building, testing, and internals |

## Security

ContainAI is a security-focused tool. See [SECURITY.md](SECURITY.md) for vulnerability reporting and security model details.

Key security features:
- **Sandbox-first**: Containers run in Docker Desktop sandbox mode or Sysbox runtime
- **Credential isolation**: Agent credentials stay inside the container by default
- **TOCTOU protection**: Volume mounts are protected against symlink attacks
- **Safe config parsing**: Environment files are validated before use

Unsafe operations require explicit opt-in flags (`--allow-host-credentials`, `--allow-host-docker-socket`, `--force`).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup and guidelines.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
