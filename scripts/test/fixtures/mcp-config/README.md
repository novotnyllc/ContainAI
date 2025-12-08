# MCP Configuration Test Fixtures

This directory contains test fixtures for verifying MCP configuration generation.

## Structure

```
mcp-config/
├── input/
│   ├── config.toml         # Source TOML configuration
│   └── mcp-secrets.env     # Mock secrets for deterministic testing
└── expected/
    ├── agent-config.json   # Expected output for all agents (copilot/codex/claude)
    └── helpers.json        # Expected helper proxy manifest
```

## Usage

The integration tests use these fixtures to verify that:
1. The `convert-toml-to-mcp.py` script produces deterministic output
2. Generated configs match the expected snapshots
3. All three agent config files are identical

## Updating Snapshots

If the config format changes intentionally:

```bash
# Generate new expected outputs
cd /path/to/CodingAgents
mkdir -p /tmp/mcp-test-output/.config/{github-copilot,codex,claude}/mcp /tmp/mcp-test-output/.config/containai

HOME=/tmp/mcp-test-output \
MCP_SECRETS_FILE=scripts/test/fixtures/mcp-config/input/mcp-secrets.env \
python3 host/utils/convert-toml-to-mcp.py scripts/test/fixtures/mcp-config/input/config.toml

# Copy and normalize outputs
jq --sort-keys . /tmp/mcp-test-output/.config/github-copilot/mcp/config.json \
  > scripts/test/fixtures/mcp-config/expected/agent-config.json

jq --sort-keys . /tmp/mcp-test-output/.config/containai/helpers.json \
  > scripts/test/fixtures/mcp-config/expected/helpers.json
```

## Notes

- The `source` field in `helpers.json` contains the input path, which may vary
- Bearer tokens in expected outputs are test values, not real secrets
- All agents receive identical config (verified by the test)
