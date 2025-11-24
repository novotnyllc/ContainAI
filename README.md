# ContainAI

**Run autonomous AI agents like GitHub Copilot, OpenAI Codex, and Anthropic Claude in isolated, secure Docker containers.**

ContainAI provides a secure runtime for autonomous agents. While optimized for coding assistants, it supports any agentic workflow that requires shell access and file manipulation. It lets you run one or more "unrestricted" agents per repository, each inside its own hardened container and Git branch, integrated with your existing tools (.NET, VS Code, GitHub, etc.), with a security model that assumes the agent is untrusted and keeps your host, your secrets, and your main branches safe.

## The Problem

Once an autonomous agent can run shell commands, install dependencies, and modify files, you face critical risks:
*   **Unsafe Execution**: `rm -rf` accidents, broken dev environments, and sensitive file leaks.
*   **Multi-Agent Chaos**: Conflicting edits and unreviewable mixtures of machine and human changes.
*   **Secret Sprawl**: Hard-coding keys in containers or checking them into repos is a non-starter.

## The Solution

ContainAI answers these problems with a practical, security-first workflow:
*   **🛡️ Total Isolation**: Agents run in hardened Docker containers (non-root, seccomp, AppArmor), not on your host.
*   **🌿 Branch Management**: Each agent gets its own isolated branch (e.g., `copilot/feature-auth`). You review and merge changes like any other contributor.
*   **🔐 Secure Secrets**: Secrets live in a host-side broker and are injected into memory only when needed. They never touch the container disk.
*   **🚀 Multi-Agent Collaboration**: Run multiple autonomous agents simultaneously on the same repository without conflicts.
*   **🔌 VS Code Native**: Connect to any agent container instantly using the Dev Containers extension.
*   **dotnet First**: First-class support for .NET 8/9/10, PowerShell, and WSL2, alongside standard Linux tools.

## Installation

Install the latest release with a single command. This sets up the `run-*` and `launch-agent` tools on your system.

**Linux / macOS:**
```bash
curl -fsSL https://raw.githubusercontent.com/novotnyllc/ContainAI/main/install.sh | bash
```

**Windows (PowerShell via WSL):**
```powershell
powershell -Command "iwr https://raw.githubusercontent.com/novotnyllc/ContainAI/main/install.ps1 -OutFile install.ps1; pwsh -File install.ps1"
```

*Prerequisites: Docker Desktop (macOS/Windows) or Docker Engine (Linux).*

## Quick Start

Once installed, you can launch an agent from any git repository on your machine.

1.  **Navigate to your project:**
    ```bash
    cd ~/my-project
    ```

2.  **Launch an agent:**
    ```bash
    # Launch GitHub Copilot in an ephemeral container
    run-copilot
    ```

3.  **Start coding:**
    The agent starts in a new container, creates a dedicated branch (e.g., `copilot/session-1`), and drops you into a shell. You can also attach VS Code to this container.

4.  **Finish up:**
    When you exit, the container automatically commits your changes and pushes them to a secure local remote on your host machine before deleting itself.

## Common Workflows

### Ephemeral Sessions (`run-*`)
Best for quick tasks, bug fixes, or experiments. The container is deleted when you exit, but your work is saved.

```bash
# Run Copilot on the current repo
run-copilot

# Run Claude on a specific repo
run-claude ~/projects/backend-api

# Run without auto-pushing changes
run-codex --no-push
```

### Persistent Workspaces (`launch-agent`)
Best for long-running features or when you need to keep the environment state (e.g., installed dependencies) across sessions.

```bash
# Launch a persistent background container
launch-agent copilot

# Work on a specific feature branch
launch-agent claude --branch refactor-ui

# Connect to an existing session
connect-agent
```

## Security Philosophy

We assume the agent is **untrusted**. ContainAI enforces a defense-in-depth security model:

1.  **Isolation by Default**: Containers run as non-root users with dropped capabilities, strict seccomp profiles blocking dangerous syscalls, and AppArmor confinement.
2.  **Least Privilege**: Only the host launcher and broker are trusted. The container only sees the repo checkout and necessary tools.
3.  **No Secrets on Disk**: Secrets are brokered Just-In-Time (JIT) into memory (`tmpfs`) only when needed by a specific MCP stub.
4.  **Network Governance**:
    -   **Squid Proxy (Default)**: All outbound traffic is routed through a monitoring proxy for audit logging.
    -   **Restricted Mode**: Lock down the container to a strict allowlist of domains.
        ```bash
        run-copilot --network-proxy restricted
        ```

## Documentation

### 📚 Usage
*   **[Getting Started](docs/getting-started.md)**: Installation and first-run guide.
*   **[Launcher Workflows](docs/usage/launchers.md)**: Detailed guide on `run-*` and `launch-agent`.
*   **[VS Code Integration](docs/usage/vscode-integration.md)**: Using Dev Containers.
*   **[Network Configuration](docs/usage/network-proxy.md)**: Proxy modes and allowlists.
*   **[Troubleshooting](docs/usage/troubleshooting.md)**: Common issues and solutions.

### 🛠️ Development
*   **[Contributing](docs/development/contributing.md)**: Guide for building from source and running tests.
*   **[Build Process](docs/development/build.md)**: How images are built and published.

### 🔒 Security
*   **[Security Model](docs/security/model.md)**: Trust boundaries and isolation mechanisms.
*   **[Architecture](docs/security/architecture.md)**: System design and data flow.

## Contributing

We welcome contributions! If you want to build ContainAI from source, develop new features, or run the test suite, please read our **[Developer Guide](docs/development/contributing.md)**.

---

*ContainAI is an open-source project licensed under MIT.*
