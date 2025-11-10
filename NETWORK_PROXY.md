# Network Proxy Configuration

The coding agents can be launched with different network access policies to control outbound connectivity.

## Network Modes

### `none` (Default - Restricted)
- **Status**: Default behavior
- **Network Access**: Container has network access controlled by Docker
- **Use Case**: Standard development where you trust the agent with network access
- **Configuration**: No special configuration needed
- **Launch**: `./launch-agent . --network-proxy none`

### `allow-all` (Unrestricted)
- **Status**: Fully implemented
- **Network Access**: Explicitly allows all network traffic (same as Docker default)
- **Use Case**: When you need unrestricted internet access for package installation, API calls, etc.
- **Configuration**: Sets `NETWORK_POLICY=allow-all` environment variable
- **Launch**: `./launch-agent . --network-proxy allow-all`

### `squid` (Proxy with Filtering)
- **Status**: Not yet implemented (TODO)
- **Network Access**: All traffic routed through Squid proxy sidecar container
- **Use Case**: 
  - Monitor and log all network requests
  - Block specific domains or patterns
  - Corporate environments requiring traffic inspection
  - Security-conscious deployments
- **Future Implementation**:
  - Launch Squid proxy container alongside agent container
  - Configure agent to use proxy for all HTTP/HTTPS traffic
  - Provide configuration for allowed/blocked domains
  - Log all network requests
- **Launch**: `./launch-agent . --network-proxy squid` (will show "not yet implemented" warning)

## Examples

```powershell
# Default (restricted mode)
./launch-agent.ps1 .

# Explicit restricted mode
./launch-agent.ps1 . -NetworkProxy none

# Allow all network traffic
./launch-agent.ps1 . -NetworkProxy allow-all

# With Squid proxy (future)
./launch-agent.ps1 . -NetworkProxy squid
```

```bash
# Default (restricted mode)
./launch-agent .

# Explicit restricted mode
./launch-agent . --network-proxy none

# Allow all network traffic
./launch-agent . --network-proxy allow-all

# With Squid proxy (future)
./launch-agent . --network-proxy squid
```

## Configuration in config.toml

The `config.toml` file also controls network access for the MCP sandbox:

```toml
# Sandbox settings - configurable network access
[sandbox_workspace_write]
network_access = true  # Change to false for restricted mode
allow_all = true       # Change to false for restricted mode
```

**Note**: The `config.toml` settings control the MCP sandbox environment, while the `--network-proxy` launch parameter controls container-level network access. Both should be aligned for consistent security posture.

## Security Considerations

1. **Default Mode**: Containers have network access via Docker's default bridge network
2. **Trust Model**: If you don't trust the agent or code being analyzed, use `squid` mode (once implemented) to monitor traffic
3. **Corporate Environments**: May require proxy configuration to comply with security policies
4. **Logging**: Squid mode (future) will provide detailed traffic logs for audit/compliance

## Future Enhancements

- [ ] Implement Squid proxy sidecar container
- [ ] Add domain whitelist/blacklist configuration
- [ ] Provide traffic logging and analysis tools
- [ ] Support custom proxy configurations
- [ ] Add network policy enforcement at container level
- [ ] Integrate with container network plugins (Calico, Weave)
