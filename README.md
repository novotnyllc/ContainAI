# ContainAI

Secure Docker sandboxes for AI agent execution.

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

ContainAI provides isolated, secure containers for running AI coding agents like Claude, Gemini, Codex, Copilot, and OpenCode. It enforces sandbox-first execution with fail-closed security defaults.

## Table of Contents

- [Features](#features)
- [Quick Start](#quick-start)
- [Documentation](#documentation)
- [Security](#security)
- [Contributing](#contributing)

## Features

- **Sandbox-first execution** - Containers run in Docker Desktop sandbox mode or with Sysbox runtime
- **Multi-agent support** - Works with Claude, Gemini, Codex, Copilot, and OpenCode
- **Credential isolation** - Agent credentials stay inside the container by default
- **Workspace mounting** - Mount your project directory securely into the sandbox
- **Auto-attach behavior** - Reconnect to existing containers automatically

## Quick Start

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

### 3. Start a sandbox

```bash
# Navigate to your project directory
cd /path/to/your/project

# Start the sandbox
cai
```

The sandbox mounts your current directory and starts the configured AI agent.

> **Note:** On first run, you may need to authenticate your agent inside the container (e.g., `claude login`).

## Documentation

| Document | Description |
|----------|-------------|
| [Quickstart Guide](docs/quickstart.md) | Detailed setup with runtime decision tree |
| [Configuration Reference](docs/configuration.md) | TOML config schema and options |
| [Troubleshooting](docs/troubleshooting.md) | Common issues and solutions |
| [Architecture](docs/architecture.md) | System design and security model |
| [Technical README](agent-sandbox/README.md) | Image building, testing, and internals |

## Security

ContainAI is a security-focused tool. See [SECURITY.md](SECURITY.md) for:

- Security guarantees and threat model
- Unsafe opt-in flags and their risks
- Vulnerability reporting process

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup and guidelines.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
