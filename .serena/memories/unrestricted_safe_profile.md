# Safe-Unrestricted Mode Profile

- **Default Container Flags**: `--cap-drop=ALL`, `--security-opt no-new-privileges:true`, `--pids-limit=4096`, `--memory=<user>` + `--memory-swap=<same>`, read-only root filesystem, tmpfs for `/tmp` and `/home/agentuser/.cache`.
- **Filesystem Strategy**: Copy repo into `/workspace`, record snapshot commit/branch name, enforce whitelist writes via `safe_write`. Auto-create `coding-agents/snapshots/<timestamp>` tag and store metadata in `.coding-agents/session.json`.
- **Network Mode**: Squid proxy (tiered allowlist) always on; allow-all requires explicit Tier 3 override and produces warning banner. Proxy logs streamed to host for auditing.
- **Secrets**: Host broker injects scoped tokens and wipes them on shutdown; credential/GPG proxies remain read-only; SSH agent forwarding disabled by default unless user toggles Tier 3 permission.
- **Monitoring**: Launchers emit session ID used across proxy logs, git commits, and Serena entries. `agent-session` exposes `/tmp/coding-agents/kill-switch` FIFO; writing `stop` triggers container shutdown and broker token revocation.
