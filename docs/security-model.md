# Security Model

This document defines the security architecture, trust boundaries, and isolation mechanisms of the ContainAI runtime.

## Trust Boundaries

The system is designed around three distinct trust zones:

### 1. The Host (Trusted)
The host machine (developer's laptop or CI runner) is the **Trusted Computing Base (TCB)**.
- **Assets**: Source code, SSH keys, API tokens, GPG keys.
- **Responsibilities**: Orchestration, secret sealing, audit logging.
- **Assumption**: The host is secure; if the host is compromised, the game is over.

### 2. The Agent Container (Untrusted)
The container running the AI agent is considered **Untrusted**.
- **Risk**: The AI model executes arbitrary code, processes untrusted inputs, and may hallucinate or be prompt-injected.
- **Restrictions**:
    - **Read-Only Root**: The root filesystem is read-only.
    - **No Privileges**: Runs as a non-root user (`UID 1000`) with `no-new-privileges:true`.
    - **Seccomp/AppArmor**: Restricted kernel syscalls (no `ptrace`, `mount`, etc.).
    - **Ephemeral**: The container is destroyed after the session.

### 3. The Broker & Sidecars (Trusted Bridge)
Helper processes that bridge the gap between the Host and the Container.
- **Secret Broker**: Validates requests for secrets and issues ephemeral tokens.
- **Proxy Sidecar**: Enforces network policies and logs traffic.
- **Log Forwarder**: Exfiltrates logs to a secure destination.

## Data Flow & Isolation

### Filesystem Isolation
- **Source Code**: Mounted **Read-Only** by default. The agent cannot modify the source code on the host directly.
- **Workspace**: A copy-on-write overlay or temporary volume is used for the agent's working directory.
- **Writes**: Changes are written to the container's writable layer.
- **Sync**: To persist changes, the agent performs a `git push` to a **Local Remote** (a bare repo on the host). The host then fast-forwards its working tree. This prevents the container from corrupting the host's `.git` index or locking files.

### Secret Management
**Principle**: Secrets are never passed as environment variables.

1.  **Sealing**: The Launcher collects secrets from the host (e.g., `GITHUB_TOKEN`) and encrypts/seals them into a **Capability Bundle**.
2.  **Mounting**: This bundle is mounted into the container at `/run/containai` (a RAM-backed `tmpfs`).
3.  **Access**: The agent process cannot read the bundle directly. Instead, it makes requests to the **MCP Stub**.
4.  **Unsealing**: The MCP Stub validates the request and retrieves the specific secret from the bundle only when needed.

### Network Isolation
- **Default**: Outbound access is permitted but routed through a **Squid Proxy Sidecar** for audit logging.
- **Restricted**: (`--network-proxy restricted`) The container is launched with `--network none`. No external access is possible.
- **DNS**: The container uses the host's DNS settings but cannot access localhost services unless explicitly configured.

## Threat Model

| Threat | Mitigation |
|--------|------------|
| **Malicious Model Output** | Container isolation, non-root user, read-only mounts. |
| **Secret Exfiltration** | Secrets not in ENV; traffic logged via Proxy; short-lived tokens. |
| **Filesystem Corruption** | Read-only source mount; Git-based sync mechanism. |
| **Privilege Escalation** | `no-new-privileges`, Seccomp, AppArmor, dropped capabilities. |
| **Network Scanning** | Isolated Docker network; Proxy enforcement. |

## Audit & Compliance

All security-relevant events are logged to the host's audit log (`~/.config/containai/security-events.log`):
- **Session Start**: Records the session manifest hash.
- **Secret Access**: Records which capability was requested and when.
- **Overrides**: Records if the user bypassed integrity checks (`CONTAINAI_DIRTY_OVERRIDE_TOKEN`).
- **Network Traffic**: The Squid proxy logs all HTTP/HTTPS CONNECT requests.
