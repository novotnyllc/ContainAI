# Safe Abstraction Concepts

## SA-01: `safe_sh`
- Category: Safe Abstraction — Shell
- Description: Host-provided CLI (installed in container as `/usr/local/bin/safe_sh`) that validates commands before spawning a shell. Enforces:
  - Denylist of obviously destructive patterns (`rm -rf /`, `dd if=/dev/zero of=/dev/sda`)
  - Path confinement to `/workspace` and `/tmp`
  - Automatic logging of command, working dir, git branch
  - Optional dry-run preview for multi-file `git` operations
- Implementation Hook: Wrap `agent-session` default shell so VS Code terminals and agent tool invocations hit `safe_sh` by default.

## SA-02: `safe_write`
- Category: Safe Abstraction — Filesystem
- Description: Provide MCP-level file modification API that enforces repo-root relative paths, blocks writes into `.git`, and automatically stages diffs for review. Serena editing commands already know file boundaries — integrate a guard that rejects edits touching `scripts/launchers/*` unless user flagged as Tier 3.

## SA-03: `safe_net`
- Category: Safe Abstraction — Network
- Description: Instead of raw `curl`, expose a tiny HTTP client service listening on localhost that only allows requests to Squid-allowlisted domains and redacts Authorization headers in logs. Agents request outbound calls via `safe_net request --service github --path /repos/...` so policy is centralized.

## SA-04: `safe_secret`
- Category: Safe Abstraction — Secrets
- Description: Host broker CLI pre-installed in container that exchanges a short-lived mTLS token for needed API keys. Agent must call `safe_secret request github-scope=repo:status` and the broker enforces TTL + scope. Secrets never land in plaintext files; they remain in env vars stored in tmpfs with inotify watchers to detect copying.
