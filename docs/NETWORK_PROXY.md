# Network Proxy Configuration

The coding agents can be launched with different network access policies to control outbound connectivity.

## Network Modes

### `allow-all` (Default)
- **Network Access**: Standard Docker bridge network (`--network bridge`)
- **Use Case**: Everyday development with access to the public internet (package installs, API calls, etc.)
- **Launch**: `./launch-agent .` or `./launch-agent . --network-proxy allow-all`
- **Alias**: Passing `--network-proxy none` maps to this mode for backwards compatibility

### `restricted` (No outbound network)
- **Network Access**: Container launched with `--network none` (no outbound or inbound network)
- **Use Case**: Highly locked-down scenarios, security reviews, running untrusted code
- **Limitation**: Cannot clone from Git URLs—provide a local repository path instead
- **Launch**: `./launch-agent . --network-proxy restricted`

### `squid` (Proxy with Filtering)
- **Network Access**: HTTP/HTTPS routed through Squid proxy sidecar container
- **Logging**: Requests recorded at `/var/log/squid/access.log` inside proxy container
- **Launch**: `./launch-agent . --network-proxy squid`
- **Artifacts**:
  - **Image**: `coding-agents-proxy:local`
  - **Sidecar**: `<agent>-<repo>-proxy`
  - **Network**: `<agent>-<repo>-net`
  - **Proxy URL** (in agent container): `http://<sidecar>:3128`

## Examples

```powershell
# Default (allow-all)
./launch-agent.ps1 .

# Restrict outbound network traffic
./launch-agent.ps1 . -NetworkProxy restricted

# Explicit alias for default behavior
./launch-agent.ps1 . -NetworkProxy allow-all
./launch-agent.ps1 . -NetworkProxy none

# Proxy with Squid
./launch-agent.ps1 . -NetworkProxy squid
```

```bash
# Default (allow-all)
./launch-agent .

# Restrict outbound network traffic
./launch-agent . --network-proxy restricted

# Explicit alias for default behavior
./launch-agent . --network-proxy allow-all
./launch-agent . --network-proxy none

# Proxy with Squid
./launch-agent . --network-proxy squid
```

## Configuration in config.toml

The `config.toml` file also controls network access for the MCP sandbox:

```toml
# Sandbox settings - configurable network access
[sandbox_workspace_write]
network_access = true  # Set to false when using restricted mode
allow_all = true       # Set to false when using restricted mode
```

**Note**: The `config.toml` settings control the MCP sandbox environment, while the `--network-proxy` launch parameter controls container-level network access. Align both settings for a consistent security posture.

## Security Considerations

1. **Default Mode**: Mirrors the typical developer experience with full outbound access
2. **Restricted Mode**: Eliminates outbound connectivity; ideal for analyzing untrusted code but requires local repository sources
3. **Proxy Mode**: Routes all outbound HTTP/HTTPS through Squid sidecar for auditing and filtering

## Future Enhancements

- [ ] Add domain whitelist/blacklist configuration
- [ ] Provide traffic logging and analysis tools
- [ ] Support custom proxy configurations
- [ ] Integrate with container network plugins (Calico, Weave)
