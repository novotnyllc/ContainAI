# ContainAI

**Secure system containers for AI coding agents.**

[![Build](https://github.com/novotnyllc/containai/actions/workflows/docker.yml/badge.svg)](https://github.com/novotnyllc/containai/actions/workflows/docker.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

ContainAI runs AI agents in **system containers** - VM-like Docker containers with systemd, multiple services, and Docker-in-Docker support. Unlike application containers, system containers provide full init systems and service management while maintaining strong isolation through Sysbox.

## Why System Containers?

Traditional Docker containers run a single process. System containers run like lightweight VMs:

| Capability | App Container | System Container |
|------------|---------------|------------------|
| Init system | No | systemd as PID 1 |
| Multiple services | No | Yes (SSH, Docker, etc.) |
| Docker-in-Docker | Requires `--privileged` | Works unprivileged via Sysbox |
| User namespace isolation | Manual | Automatic |
| SSH access | Port mapping only | VS Code Remote-SSH compatible |

This makes them ideal for AI coding agents that need to build containers, run services, and access the environment via SSH.

## Quick Start

```bash
# Install
curl -fsSL https://raw.githubusercontent.com/novotnyllc/containai/main/install.sh | bash

# Set up isolation runtime (one-time)
cai setup

# Run in your project
cd /path/to/your/project
cai
```

First run? Authenticate inside the container with `claude login`.

## Key Capabilities

### System Container with systemd

Containers boot with systemd as PID 1, enabling real service management:

```bash
cai shell
systemctl status  # See running services
```

### Docker-in-Docker Without --privileged

Sysbox enables unprivileged DinD - agents can build and run containers safely:

```bash
# Inside the container
docker build -t myapp .
docker run myapp
```

No `--privileged` flag required. Sysbox handles the isolation.

### SSH Access

Connect via VS Code Remote-SSH or standard SSH:

```bash
# From host
ssh -p 2222 agent@localhost
```

Supports agent forwarding and port tunneling for development workflows.

### Automatic User Namespace Isolation

Sysbox maps container root to an unprivileged host user automatically. No manual UID/GID configuration required.

### Extensibility

Customize containers without deep Docker knowledge:

- **Startup hooks** - Drop scripts in `.containai/hooks/startup.d/` to run at container start
- **Network policies** - Configure egress rules in `.containai/network.conf`
- **Templates** - Customize Dockerfiles for different project needs

See [Configuration](docs/configuration.md) for details.

### RFC 1123 Hostnames

Containers receive RFC 1123 compliant hostnames derived from their names. This ensures compatibility with network tools and DNS. Container names with underscores become hyphens in the hostname (e.g., `my_project-main` → `my-project-main`).

## Requirements

| Requirement | Version |
|-------------|---------|
| Docker | Engine 24.0+ |
| Bash | 4.0+ (macOS: `brew install bash`) |
| Sysbox | Installed via `cai setup` |

## Common Commands

```bash
cai                      # Start or attach to sandbox
cai --restart            # Force recreate container
cai --agent gemini       # Use a different agent
cai doctor               # Check system capabilities
cai shell                # Open bash shell in running sandbox
cai import               # Sync host dotfiles to data volume
cai update               # Update ContainAI components
cai stop --all           # Stop all ContainAI containers
```

**Note:** Most commands are silent by default (Unix Rule of Silence). Use `--verbose` to see status messages, or set `CONTAINAI_VERBOSE=1` for persistent verbosity. Warnings and errors always emit to stderr. (`doctor`, `help`, and `version` always produce output.)

## Documentation

| Document | Description |
|----------|-------------|
| [Quickstart Guide](docs/quickstart.md) | Detailed setup with environment checks |
| [Architecture](docs/architecture.md) | System design and security boundaries |
| [Configuration](docs/configuration.md) | Config file options and volumes |
| [Security Model](SECURITY.md) | Threat model and vulnerability reporting |

## Security

ContainAI enforces isolation by default:

- **Credential isolation**: Host `~/.ssh`, `~/.aws`, API tokens are not accessible
- **Docker socket denied**: No container escape via host Docker socket
- **Automatic userns**: Sysbox maps container root to unprivileged host user
- **Fail-closed**: Blocks if isolation runtime unavailable

Unsafe operations require explicit CLI flags with acknowledgment.

See [SECURITY.md](SECURITY.md) for the full threat model.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup and guidelines.

## License

MIT License - see [LICENSE](LICENSE).
