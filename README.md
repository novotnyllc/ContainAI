# ContainAI

[![Build](https://github.com/novotnyllc/containai/actions/workflows/docker.yml/badge.svg)](https://github.com/novotnyllc/containai/actions/workflows/docker.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

AI coding agents need to build containers, run services, and operate freely - but without risking your host system. ContainAI gives them **VM-like isolation without `--privileged`**, **your shell preferences synced in**, and **ephemeral or persistent environments** - all for free, using the same Sysbox technology that powers Docker Desktop's paid Enhanced Container Isolation.

```bash
# Install and run in 30 seconds
curl -fsSL https://raw.githubusercontent.com/novotnyllc/containai/main/install.sh | bash
cai setup    # One-time isolation setup
cd /path/to/project && cai   # Agent starts in isolated container
```

**Why ContainAI vs alternatives?**

| | Docker Sandbox | Plain Containers | ContainAI |
|---|---|---|---|
| User namespace isolation | No | Manual | Automatic |
| Docker-in-Docker | Host socket only | Requires `--privileged` | Unprivileged via Sysbox |
| Your dotfiles/preferences | No | No | Synced automatically |
| systemd/services | No | No | Full init system |
| Cost | Free | Free | Free |

See the [full security comparison](docs/security-comparison.md) for Docker ECI, Anthropic SRT, gVisor, and microVMs.

**Jump to:** [Users](docs/quickstart.md) | [Contributors](CONTRIBUTING.md) | [Security Auditors](SECURITY.md)

## What Makes ContainAI Different

**1. VM-like isolation without `--privileged`** - Sysbox maps container root to an unprivileged host user automatically. Agents can run `docker build`, `systemctl`, and root commands safely - a container escape still lands in an unprivileged context.

**2. Your preferences, synced** - Git config, shell aliases, and editor settings carry into the container. The environment feels like your local machine, not a sterile sandbox.

**3. Ephemeral or persistent - your choice** - Spin up disposable containers for untrusted code, or keep a long-lived dev environment with persistent volumes. Switch modes with a flag.

## Quick Start

After installation (see above), run `cai` in your project directory. First run? Authenticate inside the container with `claude login`.

For detailed setup with environment checks, see the [Quickstart Guide](docs/quickstart.md).

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
