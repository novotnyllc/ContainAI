# Security & Workflow Diagrams

The following sequence diagrams illustrate how launchers enforce security boundaries, how secrets move through the system, and how CI gates protect published images.

## 1. Launcher Boot Flow

```mermaid
sequenceDiagram
    autonumber
    participant User
    participant Launcher
    participant SecretBroker
    participant Docker
    participant Container

    User->>Launcher: run-copilot / launch-agent
    Launcher->>Launcher: Verify prerequisites (docker info, repo status)
    Launcher->>Docker: Pull tagged images (base/all/agent/proxy)
    Launcher->>Launcher: Render session manifest + MCP configs
    Launcher->>SecretBroker: Request sealed capability bundle
    SecretBroker-->>Launcher: Capability payload (no raw secrets)
    Launcher->>Docker: docker run ... (mount repo, broker sockets, tmpfs)
    Docker-->>Container: Start container + tmux session
    Container-->>User: Shell/VS Code ready, agent tools start inside tmux
```

**Key takeaways**
- Hashes of launch scripts and runtime assets are recorded before container creation.
- Every launch path pulls published images by default; `--from-source` is reserved for contributors.
- The broker handshake happens on the host so containers never see plaintext secrets at rest.

## 2. Secret Handling & MCP Enforcement

```mermaid
sequenceDiagram
    autonumber
    participant Launcher
    participant SecretBroker
    participant CapabilityBundle
    participant Container
    participant MCPStub
    participant MCPServer

    Launcher->>SecretBroker: Register requested MCP servers + scopes
    SecretBroker-->>CapabilityBundle: Issue sealed tokens on tmpfs
    Launcher->>Container: Bind-mount /run/coding-agents with bundle
    Container->>MCPStub: Start server via trusted wrapper
    MCPStub->>CapabilityBundle: Redeem sealed token (one-time)
    CapabilityBundle-->>MCPStub: Ephemeral credentials
    MCPStub->>MCPServer: Establish session using scoped creds
    MCPServer-->>MCPStub: Responses routed to agent tools
```

**Defenses**
- Capabilities live in tmpfs with `0700` permissions owned by the stub user.
- Tokens are single-use and audience-bound, so exfiltrated blobs are worthless.
- Launchers optionally merge `~/.config/coding-agents/mcp-secrets.env` for hosts that prefer .env-style inputs.

## 3. CI Build & Security Gates

```mermaid
sequenceDiagram
    autonumber
    participant GitHubActions as GitHub Actions
    participant Buildx as Docker Buildx
    participant Trivy
    participant Attestor as Build Provenance
    participant GHCR

    GitHubActions->>Buildx: Build base image (linux/amd64, arm64)
    Buildx-->>GitHubActions: Digest + metadata
    GitHubActions->>Trivy: Scan image (secret scanner HIGH/CRITICAL)
    Trivy-->>GitHubActions: Pass/fail
    GitHubActions->>Buildx: Build specialized images referencing base digest
    GitHubActions->>Attestor: Generate SLSA provenance (non-PR only)
    Attestor-->>GitHubActions: Signed statement
    GitHubActions->>GHCR: Push tags when not a pull request
    GHCR-->>Users: Latest published images for launcher syncs
```

**Highlights**
- Pull requests still build and scan images but skip pushes/attestations.
- Build matrices ensure the Squid proxy and each agent image share the same vetted base digest.
- The `scripts/build` helpers mirror this workflow locally so developers can test the same steps before opening a PR.
