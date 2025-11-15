# Finding: MCP conversion tests only inspect Copilot output
- Category: Test Coverage Gap
- Files: scripts/test/integration-test-impl.sh::test_mcp_configuration_generation
- Problem: The integration test spins up a Copilot container and verifies `/home/agentuser/.config/github-copilot/mcp/config.json` only. There is no analogous assertion for `~/.config/codex/mcp/config.json` or `~/.config/claude/mcp/config.json`. Because the converter lacks Codex support, the test still passes, so regressions remain invisible.
- Expected: Extend the test to inspect all agent config locations (Copilot, Codex, Claude) and ensure each contains the configured servers. That would have caught the Codex omission immediately.