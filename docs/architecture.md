# ContainAI Architecture

This document provides a comprehensive overview of ContainAI's architecture, including the system container model, Sysbox runtime, SSH-based access, and security boundaries.

## Table of Contents

- [System Container Overview](#system-container-overview)
- [Why Sysbox?](#why-sysbox)
- [Architecture Layers](#architecture-layers)
- [Container Lifecycle](#container-lifecycle)
- [SSH Connection Flow](#ssh-connection-flow)
- [Systemd Service Dependencies](#systemd-service-dependencies)
- [Docker-in-Docker Architecture](#docker-in-docker-architecture)
- [Component Architecture](#component-architecture)
- [Modular Library Structure](#modular-library-structure)
- [Data Flow](#data-flow)
- [Volume Architecture](#volume-architecture)
- [Security Model](#security-model)
- [Design Decisions](#design-decisions)
- [References](#references)

## System Container Overview

ContainAI uses **system containers** - VM-like Docker containers that run systemd as PID 1 and can host multiple services. Unlike traditional application containers that run a single process, system containers provide:

| Capability | Application Container | System Container |
|------------|----------------------|------------------|
| Init system | None (process as PID 1) | systemd as PID 1 |
| Multiple services | No | Yes (sshd, dockerd, etc.) |
| Docker-in-Docker | Requires `--privileged` | Works unprivileged via Sysbox |
| User namespace isolation | Manual configuration | Automatic via Sysbox |
| SSH access | Port mapping only | VS Code Remote-SSH compatible |
| Service management | Not available | `systemctl` commands work |

This makes system containers ideal for AI coding agents that need to:
- Build and run containers (Docker-in-Docker)
- Connect via SSH for VS Code Remote-SSH and agent forwarding
- Run background services
- Access a full Linux environment

## Why Sysbox?

[Sysbox](https://github.com/nestybox/sysbox) is a container runtime that enables system containers with enhanced isolation:

### Automatic User Namespace Mapping

Sysbox automatically maps container root (UID 0) to an unprivileged host user. No manual `/etc/subuid` or `/etc/subgid` configuration required.

```mermaid
flowchart LR
    subgraph Container["System Container"]
        CRoot["root (UID 0)"]
        CAgent["agent (UID 1000)"]
    end

    subgraph Sysbox["Sysbox Runtime"]
        Userns["User Namespace<br/>Mapping"]
    end

    subgraph Host["Host System"]
        HRoot["UID 100000+"]
        HAgent["UID 101000+"]
    end

    CRoot -->|"mapped by"| Userns
    CAgent -->|"mapped by"| Userns
    Userns -->|"unprivileged"| HRoot
    Userns -->|"unprivileged"| HAgent

    style Container fill:#1a1a2e,stroke:#16213e,color:#fff
    style Sysbox fill:#0f3460,stroke:#16213e,color:#fff
    style Host fill:#16213e,stroke:#0f3460,color:#fff
```

### Procfs/Sysfs Virtualization

Sysbox virtualizes `/proc` and `/sys` so containers see only their own resources, not the host's. This enables:
- `systemctl` commands to work correctly
- Accurate resource reporting inside containers
- Isolation from host process information

### Secure Docker-in-Docker

With Sysbox, containers can run Docker without `--privileged`:
- The inner Docker daemon runs with its own isolated filesystem
- No access to host Docker socket
- No capability escalation to host

## Architecture Layers

ContainAI uses a dedicated Docker installation separate from Docker Desktop:

```mermaid
flowchart TB
    subgraph Host["Host System"]
        DD["Docker Desktop<br/>(if present, NOT used)"]
        CAI["ContainAI docker-ce<br/>Socket: /var/run/containai-docker.sock<br/>Runtime: sysbox-runc"]
    end

    subgraph SysContainer["System Container (sysbox-runc)"]
        Systemd["PID 1: systemd"]
        SSHD["ssh.service<br/>(port 22 -> 2300-2500)"]
        Dockerd["docker.service<br/>(inner Docker)"]
        Init["containai-init.service<br/>(workspace setup)"]
    end

    subgraph Inner["Inner Containers (DinD)"]
        App1["Agent builds"]
        App2["Agent runs"]
    end

    CAI -->|"--runtime=sysbox-runc"| SysContainer
    Systemd --> SSHD
    Systemd --> Dockerd
    Systemd --> Init
    Dockerd --> Inner

    style Host fill:#1a1a2e,stroke:#16213e,color:#fff
    style SysContainer fill:#0f3460,stroke:#16213e,color:#fff
    style Inner fill:#16213e,stroke:#0f3460,color:#fff
```

### Why Separate docker-ce?

1. **Docker Desktop does not support Sysbox** - The `sysbox-runc` runtime is not available in Docker Desktop
2. **System containers need Sysbox** - For systemd, DinD without `--privileged`, and VM-like behavior
3. **No conflicts** - ContainAI uses its own socket (`/var/run/containai-docker.sock`) and data directory

### ContainAI Docker Configuration

The dedicated docker-ce instance (`/etc/containai/docker/daemon.json`):

```json
{
  "runtimes": {
    "sysbox-runc": {
      "path": "/usr/bin/sysbox-runc"
    }
  },
  "default-runtime": "sysbox-runc",
  "hosts": ["unix:///var/run/containai-docker.sock"],
  "data-root": "/var/lib/containai-docker"
}
```

## Container Lifecycle

```mermaid
sequenceDiagram
    participant User
    participant CLI as cai CLI
    participant Docker as ContainAI Docker
    participant Container as System Container
    participant Systemd as systemd (PID 1)
    participant SSH as sshd
    participant Agent as AI Agent

    User->>CLI: cai run /workspace
    CLI->>Docker: docker run --runtime=sysbox-runc
    Docker->>Container: Create container
    Container->>Systemd: Start systemd as PID 1

    Note over Container: ssh-keygen.service<br/>generates host keys

    Systemd->>Container: Start containai-init.service (oneshot)
    Note over Container: Workspace setup complete

    par Service Startup
        Systemd->>SSH: Start ssh.service
        Systemd->>Container: Start docker.service
    end

    CLI->>CLI: Allocate port (2300-2500)
    CLI->>Container: Inject SSH public key
    CLI->>SSH: Wait for sshd ready
    CLI->>CLI: Update known_hosts
    CLI->>SSH: SSH connect
    SSH->>Agent: Run agent command
    Agent-->>User: Interactive session

    Note over User: Session ends or user runs cai stop

    User->>CLI: cai stop
    CLI->>Docker: docker stop (SIGRTMIN+3)
    Docker->>Systemd: Graceful shutdown signal
    Systemd->>SSH: Stop ssh.service
    Systemd->>Container: Stop docker.service
    Docker->>Container: Container stopped
    Note over CLI: SSH config retained<br/>(cleaned on --restart/removal)
```

### Container Startup Sequence

1. **Container Creation**: `docker run --runtime=sysbox-runc` creates the system container
2. **Systemd Boot**: systemd starts as PID 1, initializes the service manager
3. **SSH Key Generation**: `ssh-keygen.service` generates host keys on first boot (not baked into image)
4. **Workspace Setup**: `containai-init.service` (oneshot) runs first, creating symlinks and loading environment
5. **Service Startup**: `ssh.service` and `docker.service` start after init completes
6. **SSH Connection**: CLI allocates port, injects key, waits for sshd, then connects

### Container Naming and Hostname

Each container receives a short name in the format `{repo}-{branch_leaf}` (max 24 characters) and an RFC 1123 compliant hostname that matches a sanitized version of its name.

**Hostname Sanitization Rules:**

The `_cai_sanitize_hostname()` function ensures hostnames comply with RFC 1123:

| Rule | Example |
|------|---------|
| Convert to lowercase | `MyProject` → `myproject` |
| Replace underscores with hyphens | `my_workspace` → `my-workspace` |
| Remove invalid characters | `app@v2.0` → `appv20` |
| Collapse multiple hyphens | `app--test` → `app-test` |
| Remove leading/trailing hyphens | `-app-` → `app` |
| Truncate to 63 characters | Long names are shortened |
| Fallback if empty | Empty result becomes `container` |

**Why This Matters:**

- For broad DNS and network compatibility, ContainAI enforces RFC 1123-style hostnames
- Container names can include underscores and special characters that aren't valid hostnames
- The hostname is set via Docker's `--hostname` flag during container creation
- Inside the container, `hostname` returns this sanitized value

**Example Transformations:**

| Container Name | Hostname |
|----------------|----------|
| `my_workspace-main` | `my-workspace-main` |
| `MyProject-Feature` | `myproject-feature` |
| `test__app` | `test-app` |

## SSH Connection Flow

All container access uses SSH instead of `docker attach` or direct execution. This enables:
- VS Code Remote-SSH integration
- SSH agent forwarding
- Port tunneling for development
- Standard SSH tooling (scp, rsync)

```mermaid
sequenceDiagram
    participant User
    participant CLI as cai shell
    participant SSHConfig as ~/.ssh/containai.d/
    participant Port as Port Allocator
    participant Container as Container:22
    participant SSHD as sshd

    User->>CLI: cai shell /workspace

    CLI->>Port: Find available port (2300-2500)
    Port-->>CLI: Port 2342

    CLI->>Container: Inject public key to authorized_keys
    CLI->>Container: Wait for sshd ready (retry with backoff)

    CLI->>SSHConfig: Write containai-myproject.conf
    Note over SSHConfig: Host containai-myproject<br/>  HostName localhost<br/>  Port 2342<br/>  User agent<br/>  IdentityFile ~/.config/containai/id_containai

    CLI->>SSHD: ssh -p 2342 agent@localhost
    SSHD-->>User: Interactive shell

    Note over User: VS Code can also connect:<br/>code --remote ssh-remote+containai-myproject
```

### SSH Infrastructure Components

| Component | Path | Purpose |
|-----------|------|---------|
| Private Key | `~/.config/containai/id_containai` | ed25519 key for authentication |
| Public Key | `~/.config/containai/id_containai.pub` | Injected into containers |
| Config Directory | `~/.ssh/containai.d/` | Per-container SSH configs |
| Known Hosts | `~/.config/containai/known_hosts` | Container host key verification |
| Port Range | 2300-2500 (configurable) | SSH port allocation range |

### SSH Security

- **Key-only authentication**: Password auth disabled in sshd
- **Host key verification**: Each container generates unique host keys on first boot
- **Automatic cleanup**: Stale known_hosts entries removed on `--fresh` restart
- **Port isolation**: Each container gets a unique port from the configured range

## Systemd Service Dependencies

```mermaid
flowchart TD
    subgraph Targets["Systemd Targets"]
        LocalFS["local-fs.target"]
        Network["network.target"]
        MultiUser["multi-user.target"]
    end

    subgraph Services["ContainAI Services"]
        SSHKeygen["ssh-keygen.service<br/>(Type=oneshot)<br/>Generates host keys"]
        SSH["ssh.service<br/>(Type=notify)<br/>SSH daemon"]
        DockerSvc["docker.service<br/>(Type=notify)<br/>Docker daemon"]
        Init["containai-init.service<br/>(Type=oneshot)<br/>Workspace setup"]
    end

    LocalFS --> Init
    Network --> Init
    Init --> SSH
    Init --> DockerSvc
    SSHKeygen --> SSH

    SSH --> MultiUser
    DockerSvc --> MultiUser

    style Targets fill:#1a1a2e,stroke:#16213e,color:#fff
    style Services fill:#0f3460,stroke:#16213e,color:#fff
```

### Service Details

| Service | Type | Purpose |
|---------|------|---------|
| `ssh-keygen.service` | oneshot | Generate SSH host keys if missing (security: not baked into image) |
| `ssh.service` | notify | OpenSSH daemon for remote access |
| `docker.service` | notify | Inner Docker daemon for DinD |
| `containai-init.service` | oneshot | Volume structure, workspace symlinks, git config |

### Service Files Location

- Image: `/etc/systemd/system/` (installed from `src/services/`)
- Drop-ins: `/etc/systemd/system/<service>.service.d/`

## Docker-in-Docker Architecture

Sysbox enables secure Docker-in-Docker without `--privileged`:

```mermaid
flowchart TB
    subgraph Host["Host System"]
        HostDocker["ContainAI docker-ce<br/>Runtime: sysbox-runc"]
        HostSocket["containai-docker.sock"]
    end

    subgraph SysContainer["System Container"]
        InnerDocker["docker.service<br/>Runtime: sysbox-runc"]
        InnerSocket["/var/run/docker.sock"]
        InnerStorage["/var/lib/docker"]
    end

    subgraph InnerContainers["Inner Containers"]
        Build["docker build -t myapp ."]
        Run["docker run myapp"]
        Compose["docker compose up"]
    end

    HostDocker -->|"creates"| SysContainer
    HostSocket -.->|"NOT mounted"| SysContainer
    InnerDocker --> InnerContainers

    style Host fill:#1a1a2e,stroke:#16213e,color:#fff
    style SysContainer fill:#0f3460,stroke:#16213e,color:#fff
    style InnerContainers fill:#16213e,stroke:#0f3460,color:#fff
```

### How DinD Works with Sysbox

1. **Isolated Docker Daemon**: The inner Docker runs with its own socket and storage
2. **No Host Socket**: The host Docker socket is NOT mounted into containers
3. **Sysbox Runtime**: Both outer and inner Docker use sysbox-runc for consistent isolation
4. **Nested User Namespaces**: Each layer has its own UID mapping

### Inner Docker Configuration

Inside the system container (`/etc/docker/daemon.json`):

```json
{
  "runtimes": {
    "sysbox-runc": {
      "path": "/usr/bin/sysbox-runc"
    }
  },
  "default-runtime": "sysbox-runc"
}
```

## Component Architecture

```mermaid
flowchart LR
    subgraph CLI["CLI Layer"]
        direction TB
        Main["src/cai/Program.cs<br/>(entry point)"]
        Cmds["src/ContainAI.Cli<br/>(System.CommandLine surface)"]
    end

    subgraph Lib["Library Layer"]
        direction TB
        Runtime["NativeLifecycleCommandRuntime.cs<br/>(core command orchestration)"]
        Session["NativeSessionCommandRuntime.cs<br/>(run/shell/exec lifecycle)"]
        Container["ContainerRuntimeCommandService.cs<br/>(container-internal runtime)"]
        Manifest["ManifestTomlParser.cs<br/>(TOML parsing)"]
    end

    subgraph Runtime["Container Runtime"]
        direction TB
        Entry["entrypoint.sh"]
        Services["systemd services"]
        Dockerfile["Dockerfile layers"]
    end

    Main --> Lib
    Container --> SSH
    Container --> Entry

    style CLI fill:#1a1a2e,stroke:#16213e,color:#fff
    style Lib fill:#0f3460,stroke:#16213e,color:#fff
    style Runtime fill:#16213e,stroke:#0f3460,color:#fff
```

### CLI Command Surface

ContainAI's CLI command surface is **statically declared** in `src/ContainAI.Cli/RootCommandBuilder.cs` and related command builder files. There is no runtime discovery or plugin-based command loading; the compiled command model is the source of truth for parsing and completion.

Shell completion uses the built-in `cai completion suggest` path implemented by the CLI itself. This removes any dependency on external completion helpers such as `dotnet-suggest`.

## Modular Library Structure

The CLI is split into native C# runtime components:

| Module | Purpose | Key Types |
|--------|---------|-----------|
| `src/cai/Program.cs` | Native host entrypoint | `Program` |
| `src/ContainAI.Cli/` | Command parser/routing | `CaiCli`, `RootCommandBuilder` |
| `src/cai/NativeLifecycleCommandRuntime.cs` | Host command orchestration | `NativeLifecycleCommandRuntime` |
| `src/cai/NativeSessionCommandRuntime.cs` | Session lifecycle and SSH flow | `NativeSessionCommandRuntime` |
| `src/cai/ContainerRuntimeCommandService.cs` | Container-side init/link/runtime commands | `ContainerRuntimeCommandService` |
| `src/cai/ManifestTomlParser.cs` | TOML manifest parsing | `ManifestTomlParser` |
| `src/cai/ManifestGenerators.cs` | Derived artifact generation | `ManifestGenerators` |
| `src/cai/DevcontainerFeatureRuntime.cs` | Devcontainer feature/system integration | `DevcontainerFeatureRuntime` |
| `src/cai/ContainAiDockerProxy.cs` | Docker context mediation and setup helpers | `ContainAiDockerProxy` |
| `src/cai/AcpProxyRunner.cs` | ACP proxy process lifecycle | `AcpProxyRunner` |
| `src/AgentClientProtocol.Proxy/` | ACP transport/proxy library | `AcpProxy`, `AcpSession`, `PathTranslator` |

### Module Dependencies

```mermaid
flowchart TD
    Main["Program.cs"] --> Cli["ContainAI.Cli (System.CommandLine)"]
    Cli --> Runtime["NativeLifecycleCommandRuntime.cs"]
    Runtime --> Session["NativeSessionCommandRuntime.cs"]
    Runtime --> Container["ContainerRuntimeCommandService.cs"]
    Runtime --> Manifest["ManifestTomlParser.cs / ManifestGenerators.cs"]
    Runtime --> DockerProxy["ContainAiDockerProxy.cs"]
    Cli --> AcpRunner["AcpProxyRunner.cs"]
    AcpRunner --> AcpLib["AgentClientProtocol.Proxy"]

    style Main fill:#1a1a2e,stroke:#16213e,color:#fff
    style Runtime fill:#e94560,stroke:#16213e,color:#fff
    style AcpLib fill:#0f3460,stroke:#16213e,color:#fff
```

## Data Flow

### CLI to Container via SSH

```mermaid
sequenceDiagram
    participant User
    participant CLI as cai (Program.cs)
    participant Runtime as NativeLifecycleCommandRuntime
    participant Session as NativeSessionCommandRuntime
    participant Docker as ContainAI Docker
    participant SSHD as Container sshd

    User->>CLI: cai run [options]
    CLI->>Runtime: Parse config + route typed command
    Runtime->>Docker: docker info (verify context/runtime)
    Docker-->>Runtime: Context/runtime availability
    Runtime->>Session: Resolve/start container + SSH metadata
    Session->>Docker: docker run --runtime=sysbox-runc
    Docker-->>Session: Container ID
    Session->>SSHD: Wait for ready and connect via ssh
    Session->>SSHD: ssh agent@localhost -p PORT
    SSHD-->>User: Agent session
```

## Volume Architecture

```mermaid
flowchart LR
    subgraph Host["Host System"]
        Workspace["Workspace<br/>(/path/to/project)"]
        HostConfigs["Host Configs<br/>(~/.ssh, ~/.gitconfig)"]
    end

    subgraph Volumes["Docker Volumes"]
        DataVol["Data Volume<br/>(containai-data)"]
    end

    subgraph Container["System Container"]
        WorkMount["/home/agent/workspace<br/>(bind mount)"]
        DataMount["/mnt/agent-data<br/>(volume mount)"]

        subgraph DataStructure["Data Volume Contents"]
            Claude["/claude<br/>(credentials, settings)"]
            GH["/config/gh<br/>(GitHub CLI)"]
            VSCode["/vscode-server"]
            Shell["/shell<br/>(bash config)"]
        end
    end

    Workspace -->|"bind mount"| WorkMount
    DataVol --> DataMount
    DataMount --> DataStructure
    HostConfigs -.->|"cai import"| DataVol

    style Host fill:#1a1a2e,stroke:#16213e,color:#fff
    style Volumes fill:#16213e,stroke:#0f3460,color:#fff
    style Container fill:#0f3460,stroke:#16213e,color:#fff
```

### Volume Types

| Volume | Mount Point | Purpose | Lifecycle |
|--------|-------------|---------|-----------|
| Workspace | `/home/agent/workspace` | Project files | Bind mount per session |
| Data Volume | `/mnt/agent-data` | Agent configs, credentials | Persistent named volume |

### Data Volume Structure

```
/mnt/agent-data/
├── claude/              # Claude Code
│   ├── credentials.json
│   ├── settings.json
│   └── plugins/
├── config/
│   ├── gh/              # GitHub CLI
│   ├── git/             # Git config
│   └── tmux/
├── gemini/              # Gemini CLI
├── copilot/             # Copilot CLI
├── codex/               # Codex CLI
├── shell/
│   └── .bashrc.d/       # Shell extensions
└── vscode-server/       # VS Code Server state
```

## Security Model

### Sysbox Isolation

Sysbox provides multiple isolation layers:

```mermaid
flowchart TB
    subgraph Host["Host (TRUSTED)"]
        HostKernel["Kernel"]
        HostDocker["Docker Daemon"]
        SysboxMgr["sysbox-mgr"]
        SysboxFS["sysbox-fs"]
    end

    IsolationLayer["Sysbox Isolation Layer<br/>User Namespace + Procfs/Sysfs Virtualization"]

    subgraph Container["System Container (UNTRUSTED)"]
        ContainerRoot["Container Root<br/>(unprivileged on host)"]
        ContainerProc["/proc (virtualized)"]
        ContainerSys["/sys (virtualized)"]
        InnerDocker["Inner Docker"]
    end

    HostKernel --> SysboxMgr
    SysboxMgr --> SysboxFS
    HostDocker --> IsolationLayer
    IsolationLayer --> Container
    SysboxFS -->|"virtualizes"| ContainerProc
    SysboxFS -->|"virtualizes"| ContainerSys

    style Host fill:#16213e,stroke:#16213e,color:#fff
    style IsolationLayer fill:#0f3460,stroke:#16213e,color:#fff
    style Container fill:#e94560,stroke:#16213e,color:#fff
```

### Security Guarantees

| Protection | Implementation |
|------------|----------------|
| User namespace isolation | Sysbox auto-maps UIDs (container root = unprivileged host user) |
| Procfs virtualization | Container sees only its own processes |
| Sysfs virtualization | Container sees only its own devices |
| No host Docker socket | Socket is NOT mounted; inner Docker is isolated |
| SSH key-only auth | Password authentication disabled |
| Resource limits | cgroup limits (memory, CPU) enforced |

### Resource Limits

By default, containers receive 50% of host resources:

| Resource | Default | Configuration |
|----------|---------|---------------|
| Memory | 50% of host RAM | `[resources].memory_limit` or `--memory` |
| CPU | 50% of host cores | `[resources].cpu_limit` or `--cpus` |
| Memory swap | Same as memory limit | Prevents OOM via swap |

### What ContainAI Does NOT Protect Against

- **Malicious container images**: Use trusted base images only
- **Network isolation**: Containers can reach the internet by default
- **Kernel vulnerabilities**: Depends on Sysbox/Docker security
- **Supply chain attacks**: Verify agent CLI installations

## Design Decisions

### SSH-Based Access

**Decision**: Use SSH for all container access instead of `docker attach`.

**Rationale**:
- VS Code Remote-SSH compatibility
- SSH agent forwarding for git operations
- Port tunneling for development servers
- Standard tooling (scp, rsync) works out of the box
- More robust than PTY via Docker API

### Dedicated Docker Installation

**Decision**: Install separate docker-ce instead of using Docker Desktop.

**Rationale**:
- Docker Desktop does not support Sysbox runtime
- Avoids conflicts with existing Docker setup
- Full control over runtime configuration
- Dedicated socket prevents accidental cross-usage

### System Containers with systemd

**Decision**: Run systemd as PID 1 in containers.

**Rationale**:
- Enables real service management
- SSH daemon runs as proper service
- Docker daemon managed by systemd
- Init system handles cleanup on shutdown
- Matches production Linux environments

### Layered Dockerfile Build

**Decision**: Split Dockerfile into base/sdks/full layers.

**Rationale**:
- Faster iteration during development
- Smaller images for minimal use cases
- Clear separation of concerns
- Easier updates to individual layers

## References

- [Sysbox Documentation](https://github.com/nestybox/sysbox)
- [Sysbox Systemd Guide](https://github.com/nestybox/sysbox/blob/master/docs/user-guide/systemd.md)
- [Sysbox DinD Guide](https://github.com/nestybox/sysbox/blob/master/docs/user-guide/dind.md)
- [SSH Include Directive](https://man.openbsd.org/ssh_config)
- [Docker Contexts](https://docs.docker.com/engine/manage-resources/contexts/)
- [Configuration Reference](configuration.md)
- [Troubleshooting Guide](troubleshooting.md)
- [Security Model](../SECURITY.md)
