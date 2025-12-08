# MCP Configuration Test Fixtures

Test fixtures for verifying MCP configuration generation.

## MCP Server Types

### Remote Servers (URL-based)
- Have a `url` field pointing to an external MCP endpoint
- Rewritten to use a local helper proxy (http://127.0.0.1:port)
- Helper proxy forwards requests through Squid and injects bearer tokens

### Local Servers (command-based)  
- Have a `command` field specifying a local executable
- Wrapped for secret injection at runtime
- Wrapper spec at `~/.config/containai/wrappers/<name>.json`
- Agent config points to `mcp-wrapper-<name>` which reads the spec

## Existing Config Rewriting

Pre-existing MCP server configs are **rewritten** to go through the proxy mechanism:
- Existing remote servers get routed through helper proxy (new port allocated)
- Existing local servers get wrapped for secret injection
- This ensures ALL MCP traffic goes through security controls

## Structure

```
mcp-config/
├── input/
│   ├── config.toml              # Source TOML configuration
│   ├── mcp-secrets.env          # Mock secrets for testing
│   └── existing-mcp-config.json # Pre-existing config (gets rewritten)
└── expected/
    ├── agent-config.json        # Expected output (existing-server rewritten)
    ├── helpers.json             # Helper manifest (includes existing-server)
    └── wrapper-local-tool.json  # Wrapper spec
```

## Updating Snapshots

```bash
cd /path/to/CodingAgents

mkdir -p /tmp/mcp-test/.config/{github-copilot,codex,claude}/mcp
mkdir -p /tmp/mcp-test/.config/containai/{wrappers,capabilities}

cp scripts/test/fixtures/mcp-config/input/existing-mcp-config.json \
   /tmp/mcp-test/.config/github-copilot/mcp/config.json

HOME=/tmp/mcp-test \
MCP_SECRETS_FILE=scripts/test/fixtures/mcp-config/input/mcp-secrets.env \
python3 host/utils/convert-toml-to-mcp.py scripts/test/fixtures/mcp-config/input/config.toml

jq --sort-keys . /tmp/mcp-test/.config/github-copilot/mcp/config.json \
  > scripts/test/fixtures/mcp-config/expected/agent-config.json

jq --sort-keys 'del(.source)' /tmp/mcp-test/.config/containai/helpers.json \
  > scripts/test/fixtures/mcp-config/expected/helpers.json

jq --sort-keys . /tmp/mcp-test/.config/containai/wrappers/local-tool.json \
  > scripts/test/fixtures/mcp-config/expected/wrapper-local-tool.json
```

## Notes

- `source` field in `helpers.json` contains input path (stripped in tests)
- `CONTAINAI_WRAPPER_SPEC` path varies by home directory (normalized in tests)
- Bearer tokens in expected outputs are fake test values
