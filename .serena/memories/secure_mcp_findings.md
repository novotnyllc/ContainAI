# MCP Security Findings (2025-11-17)

1. **Container fallback bypasses broker** – `scripts/runtime/entrypoint.sh` still runs `/usr/local/bin/setup-mcp-configs.sh` when `HOST_SESSION_CONFIG_ROOT` is absent, pulling secrets from `/workspace/config.toml` and `.mcp-secrets.env`, bypassing the broker guarantees.
2. **Session configs reference raw MCP commands** – `scripts/utils/render-session-config.py` copies the `[mcp_servers]` stanza verbatim, so agents execute MCP binaries directly instead of a trusted stub; capability tokens are never redeemed.
3. **No MCP stub wrapper implementation** – There is no shim/binary in the repo that redeems capability tokens and injects secrets before launching the real MCP server. Need to add one and ensure configs invoke it.
