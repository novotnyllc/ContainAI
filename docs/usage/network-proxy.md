# Network Proxy Configuration

The agents can be launched with different network access policies to control outbound connectivity.

## Network Modes

The following diagram illustrates the traffic flow for each network mode.

```mermaid
flowchart TB
    subgraph container["Agent Container"]
        agent["Agent Process"]
    end

    subgraph internet["Internet"]
        github["GitHub / PyPI / npm"]
        malicious["Malicious Site"]
    end

    subgraph proxy["Squid Proxy Sidecar"]
        squid["Squid Process"]
    end

    %% Traffic Flow
    agent ==>|HTTP/HTTPS| squid
    squid ==>|Allowed| github
    squid -.->|Blocked (Restricted Mode)| malicious
    squid ==>|Allowed (Default Mode)| malicious

    style container fill:#fff3cd,stroke:#856404
    style proxy fill:#e2e3e5,stroke:#383d41
    style internet fill:#e1f5ff,stroke:#0366d6
```

### `squid` (Default)
- **Network Access**: Full outbound HTTP/HTTPS access routed through Squid proxy sidecar
- **Logging**: Requests recorded at `/var/log/squid/access.log` inside proxy container
- **Launch**: `./host/launchers/entrypoints/launch-agent-dev copilot --network-proxy squid`
- **Artifacts**:
  - **Image**: `containai-proxy:local`
  - **Sidecar**: `<agent>-<repo>-proxy`
  - **Network**: `<agent>-<repo>-net`
  - **Proxy URL** (in agent container): `http://<sidecar>:3128`

### `restricted` (Allowlist Only)
- **Network Access**: Outbound traffic routed through Squid but restricted to specific domains
- **Default Allowlist**: GitHub, Microsoft, PyPI, npm, NuGet, Docker Registry
- **Customization**: Set `CONTAINAI_ALLOWED_DOMAINS` environment variable to override the allowlist
- **Use Case**: Locked-down scenarios, security reviews, running untrusted code
- **Launch**: `./host/launchers/run-agent copilot --network-proxy restricted`

## Examples

**Ephemeral containers (recommended):**

```bash
# Default (squid proxy)
run-copilot-dev

# Restrict outbound network traffic
run-copilot-dev --network-proxy restricted

# Proxy with Squid logging (explicit)
run-copilot-dev --network-proxy squid
```

```powershell
# Default (squid proxy)
.\host\launchers\entrypoints\run-copilot-dev.ps1

# Restrict outbound network traffic
.\host\launchers\entrypoints\run-copilot-dev.ps1 -NetworkProxy restricted

# Proxy with Squid logging (explicit)
.\host\launchers\entrypoints\run-copilot-dev.ps1 -NetworkProxy squid
```

**Persistent containers (advanced):**

```bash
# Default (squid proxy)
./host/launchers/entrypoints/launch-agent-dev copilot

# Explicit proxy mode
./host/launchers/entrypoints/launch-agent-dev copilot --network-proxy squid
```

```powershell
# Default (squid proxy)
./host/launchers/entrypoints/launch-agent-dev.ps1 copilot

# Explicit proxy mode
./host/launchers/entrypoints/launch-agent-dev.ps1 copilot -NetworkProxy squid
```

## Configuration in config.toml

The `config.toml` file also controls network access for the MCP sandbox:

```toml
# Sandbox settings - configurable network access
[sandbox_workspace_write]
network_access = true  # Set to false when using restricted mode
```

**Note**: The `config.toml` settings control the MCP sandbox environment, while the `--network-proxy` launch parameter controls container-level network access. Align both settings for a consistent security posture.

## Security Considerations

1. **Default Mode**: Mirrors the typical developer experience with full outbound access
2. **Restricted Mode**: Eliminates outbound connectivity; ideal for analyzing untrusted code but requires local repository sources
3. **Proxy Mode**: Routes all outbound HTTP/HTTPS through Squid sidecar for auditing and filtering
