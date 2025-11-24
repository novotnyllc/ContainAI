# ContainAI

**Run AI agents like GitHub Copilot, OpenAI Codex, and Anthropic Claude in isolated, secure Docker containers.**

ContainAI provides a secure runtime for AI coding agents. Each agent operates in its own isolated container with a dedicated workspace and git branch, preventing conflicts and keeping your host environment clean. It enforces strict network policies, manages secrets securely without exposing them to the container filesystem, and integrates seamlessly with VS Code.

## Why ContainAI?

- **🛡️ Total Isolation**: Agents run in Docker containers, not on your host machine. No messy config files or accidental overwrites.
- **🔐 Secure by Default**: Secrets are injected into memory only when needed. Network traffic is monitored via a sidecar proxy.
- **🌿 Branch Management**: Agents automatically work on isolated branches (e.g., `copilot/feature-auth`), keeping your main branch clean.
- **🚀 Multi-Agent Collaboration**: Run Copilot, Claude, and Codex simultaneously on the same repository without them fighting over files.
- **🔌 VS Code Native**: Connect to any agent container instantly using the Dev Containers extension.

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

## Security & Network Control

ContainAI puts you in control of what agents can access.

-   **Squid Proxy (Default)**: All outbound traffic is routed through a monitoring proxy. You can audit logs to see exactly what the agent is accessing.
-   **Restricted Mode**: Lock down the container to a strict allowlist of domains (GitHub, package registries).
    ```bash
    run-copilot --network-proxy restricted
    ```
-   **Secret Safety**: API keys and credentials are never stored in the container image or written to the container's disk. They are streamed from your host only when requested by a verified process.

## Documentation

*   **[Usage Guide](USAGE.md)**: Detailed command reference and workflows.
*   **[Getting Started](docs/getting-started.md)**: In-depth setup and first-run guide.
*   **[Network Configuration](docs/network-proxy.md)**: Details on proxy modes and allowlists.
*   **[VS Code Integration](docs/vscode-integration.md)**: How to use the Dev Containers extension.
*   **[Troubleshooting](TROUBLESHOOTING.md)**: Solutions for common issues.

## Contributing

We welcome contributions! If you want to build ContainAI from source, develop new features, or run the test suite, please read our **[Developer Guide](CONTRIBUTING.md)**.

---

*ContainAI is an open-source project licensed under MIT.*
