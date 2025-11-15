# Finding: convert-toml-to-mcp.py never generates Codex MCP config
- Category: Missing Functionality
- Files: scripts/utils/convert-toml-to-mcp.py (loop starting near line 32)
- Problem: Docs (docs/build.md, docs/mcp-setup.md) state TOML converter must emit MCP JSON for Copilot, Codex, and Claude, but the implementation only iterates over `{"github-copilot", "claude"}`. Codex users never get `~/.config/codex/mcp/config.json`, so MCP servers configured in config.toml are silently ignored whenever run-codex is used.
- Impact: Codex containers run without any configured MCP servers despite config.toml providing them, breaking parity with other agents and confusing users (no warning).
- Expected: Include Codex in the agents list, expanding `~/.config/codex/mcp` and writing the same mcpServers block there (or emitting an explicit warning if Codex intentionally unsupported).