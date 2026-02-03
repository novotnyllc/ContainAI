# ACP Integration

ContainAI supports the [Agent Client Protocol](https://agentclientprotocol.com) (ACP) for editor integration. This allows editors like Zed and VS Code to run AI agents in secure, containerized environments.

## Quick Start

Configure your editor to use `cai --acp <agent>`:

**Zed** (`~/.config/zed/settings.json`):
```json
{
  "agent_servers": {
    "claude-sandbox": {
      "type": "custom",
      "command": "cai",
      "args": ["--acp", "claude"]
    }
  }
}
```

**VS Code** (with ACP extension):
```json
{
  "acp.executable": "cai",
  "acp.args": ["--acp", "claude"]
}
```

## How It Works

```mermaid
%%{init: {'theme': 'base', 'themeVariables': {
  'background': '#f5f5f5',
  'actorBkg': '#1a1a2e',
  'actorTextColor': '#ffffff',
  'actorBorder': '#16213e',
  'actorLineColor': '#606060',
  'signalColor': '#606060',
  'signalTextColor': '#1a1a2e',
  'labelBoxBkgColor': '#0f3460',
  'labelBoxBorderColor': '#16213e',
  'labelTextColor': '#ffffff',
  'noteBkgColor': '#0f3460',
  'noteTextColor': '#ffffff',
  'noteBorderColor': '#16213e'
}}}%%
sequenceDiagram
    participant Editor
    participant Proxy as cai --acp (Proxy)
    participant Exec as cai exec
    participant Container
    participant Agent as Agent (claude --acp)
    participant MCP as MCP Servers

    Editor->>Proxy: ACP stdio (NDJSON)
    Proxy->>Exec: Spawn container exec
    Exec->>Container: SSH/exec
    Container->>Agent: Run agent --acp
    Agent->>MCP: Connect to MCP servers
    MCP-->>Agent: Tool responses
    Agent-->>Proxy: Response
    Proxy-->>Editor: Response via stdio
```

1. Editor spawns `cai --acp claude`
2. Editor sends `initialize`, then `session/new` with workspace and MCP config
3. Proxy resolves workspace root (git root or `.containai/config.toml` parent)
4. Proxy spawns `cai exec` which handles container creation/SSH
5. Agent handles MCP servers (spawns stdio, connects to HTTP/SSE)
6. All communication proxied through

### Protocol Details

- **Framing**: NDJSON (newline-delimited JSON), not `Content-Length` headers like LSP
- **Session IDs**: Proxy namespaces session IDs to prevent collisions between agents
- **Output**: Serialized through single writer to prevent interleaved output

## Multiple Sessions

One proxy process can handle multiple editor sessions:

- Each `session/new` can target a different workspace
- Different workspaces use different containers
- Subdirectories map to their workspace root
- Messages routed by `sessionId`

### Workspace Resolution

When the editor sends a `cwd` in `session/new`, the proxy resolves it to a workspace root:

1. Find nearest `.git` directory (git repository root)
2. Find nearest `.containai/config.toml` (ContainAI project root)
3. Use `cwd` as-is (fallback)

Multiple sessions with paths in the same workspace tree share the same container.

## MCP Servers

MCP (Model Context Protocol) servers provide tools and context to the agent. The agent (not the proxy) manages MCP connections.

### What Works

| MCP Type | Works? | Notes |
|----------|--------|-------|
| HTTP/SSE (remote) | Yes | Agent connects directly from container |
| Stdio (in container) | Yes | Package must be installed in container |
| HTTP/SSE (localhost) | Limited | See "Host-Local Services" below |
| Stdio (host-only) | No | Can't spawn host processes from container |

### Installing MCP Packages in Container

For stdio MCP servers to work, their packages must be installed in the container image. You can add them to your template's Dockerfile:

```dockerfile
# In your custom template Dockerfile
RUN npm install -g @modelcontextprotocol/server-filesystem \
                   @mcp/fetch \
                   @mcp/postgres
```

Or install at runtime via shell:
```bash
cai shell
npm install -g @mcp/whatever
```

### Host-Local Services

To access MCP servers running on your host machine:

1. Create container with host networking flag:
   ```bash
   docker run --add-host=host.docker.internal:host-gateway ...
   ```

2. Configure MCP URL as `http://host.docker.internal:PORT/...`

**Note**: This requires manual container configuration. The `--add-host` flag must be added to container creation, which is not currently automated by ContainAI.

### Path Translation

Your local paths work transparently:
```
/home/user/project -> /home/agent/workspace (symlink in container)
```

MCP server args containing workspace paths are translated automatically:

| Host Path | Container Path |
|-----------|----------------|
| `/home/user/project` | `/home/agent/workspace` |
| `/home/user/project/src` | `/home/agent/workspace/src` |
| `/other/path` | `/other/path` (unchanged) |

The translation is path-aware and only applies to absolute paths that are descendants of the workspace.

## Supported Agents

ContainAI supports **any agent** that implements the ACP protocol. The agent binary must be installed in the container and support the `--acp` flag.

### Built-in Agents

| Agent | Command | Notes |
|-------|---------|-------|
| Claude Code | `cai --acp claude` | Pre-installed in default images |
| Gemini CLI | `cai --acp gemini` | Pre-installed in default images |

### Custom Agents

Any ACP-compatible agent can be used:

```bash
# Use a custom agent
cai --acp myagent

# The agent must:
# 1. Be installed in the container (in $PATH)
# 2. Support the --acp flag for ACP protocol mode
```

**Installing custom agents:** Add them to your template Dockerfile:

```dockerfile
# In your custom template Dockerfile
RUN npm install -g @mycompany/myagent
# or
RUN pip install myagent
```

Or install at runtime via shell:
```bash
cai shell
npm install -g @mycompany/myagent
```

## Editor Configuration

### Zed

Add to `~/.config/zed/settings.json`:

```json
{
  "agent_servers": {
    "claude-sandbox": {
      "type": "custom",
      "command": "cai",
      "args": ["--acp", "claude"]
    }
  }
}
```

For multiple agents:

```json
{
  "agent_servers": {
    "claude-sandbox": {
      "type": "custom",
      "command": "cai",
      "args": ["--acp", "claude"]
    },
    "gemini-sandbox": {
      "type": "custom",
      "command": "cai",
      "args": ["--acp", "gemini"]
    }
  }
}
```

See [Zed External Agents documentation](https://zed.dev/docs/ai/external-agents) for more details.

### VS Code

With an ACP-compatible extension, add to `settings.json`:

```json
{
  "acp.executable": "cai",
  "acp.args": ["--acp", "claude"]
}
```

## Troubleshooting

### Agent not starting

Verify the agent is installed in the container:
```bash
cai shell
command -v <agent>  # e.g., command -v claude or command -v myagent
<agent> --help | grep -i acp  # Verify ACP support
```

If the agent is not found, you'll see an error like:
```
Agent '<agent>' not found in container
```

**Solutions:**
- Check the agent name spelling matches the binary name
- Install the agent in your template Dockerfile
- Install at runtime: `cai shell` then install the agent (e.g., `npm install -g @mycompany/myagent`)

### MCP server not found

```bash
cai shell
which npx  # Verify npm available
npx @mcp/fetch --version  # Verify MCP package works
```

If the package is not found, install it in the container or add it to your template's Dockerfile.

### Can't reach host services

From container, verify `host.docker.internal` resolves:
```bash
cai shell
ping host.docker.internal  # Should resolve to host IP
curl http://host.docker.internal:8080/  # Test connectivity
```

If this fails, the container needs the `--add-host=host.docker.internal:host-gateway` flag.

### Multiple sessions not routing

Check that each `session/new` returned a unique `sessionId`. The proxy uses these IDs to route messages to the correct agent process.

### Protocol errors

The proxy uses NDJSON (newline-delimited JSON) framing. If you see parsing errors:

- Ensure each message is a single line
- Messages must end with newline
- No embedded newlines in JSON values

### Stdout pollution

ACP requires stdout purity - only protocol messages should appear. If you see diagnostic output:

- The proxy sets `CAI_NO_UPDATE_CHECK=1` to suppress update checks
- All ContainAI diagnostic output goes to stderr in ACP mode
- Check for shell initialization scripts that may print to stdout

### Container not created

The proxy uses `cai exec` internally. Verify it works standalone:
```bash
cai exec --workspace /path/to/project echo "hello"
```

If this fails, check your ContainAI configuration and Docker setup with `cai doctor`.

### Session timeout

The proxy waits up to 30 seconds for agent responses to `initialize` and `session/new`. If timeouts occur:

- Check container startup time (may be slow on first run)
- Verify agent is responsive: `cai exec -- claude --version`
- Check for errors in stderr output

## Environment Variables

For testing and debugging:

| Variable | Description |
|----------|-------------|
| `CAI_ACP_TEST_MODE=1` | Allow any agent name (for testing) |
| `CAI_ACP_DIRECT_SPAWN=1` | Bypass containers, spawn agent directly |
| `CAI_NO_UPDATE_CHECK=1` | Skip update checks (set automatically in ACP mode) |

## Limitations

- **Stdio transport only**: HTTP/WebSocket ACP transport not supported
- **Host MCP servers**: Stdio servers that only exist on the host cannot run in container
- **host.docker.internal**: Requires manual container configuration for host-local HTTP services
- **Agent availability**: Only agents installed in the container image are available

## References

- [ACP Specification](https://agentclientprotocol.com)
- [ACP Architecture](https://agentclientprotocol.com/overview/architecture)
- [MCP Introduction](https://modelcontextprotocol.io/introduction)
- [MCP Architecture](https://modelcontextprotocol.io/docs/learn/architecture)
- [Zed External Agents](https://zed.dev/docs/ai/external-agents)
