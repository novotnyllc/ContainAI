# Unrestricted Mode Threat Model

## RISK-DES-01: Workspace & Git Destruction
- Category: Risk/Threat — Destruction
- Classification: Actual (prompt-injected agent can already do this)
- References: scripts/runtime/entrypoint.sh, scripts/launchers/launch-agent, scripts/utils/common-functions.sh
- Description: Agents have full write access to `/workspace`, can run arbitrary shell commands, and auto-push to the host's bare local remote on shutdown. A hostile prompt can delete repo contents, force-push rewritten history, or pollute the auto-commit/push flow. Damage is limited to the isolated copy until pushed, but the system auto-syncs agent branches back to host repos (`sync_local_remote_to_host`), so destructive actions can propagate if not noticed.

## RISK-EXF-01: Secret Exfiltration via Network
- Category: Risk/Threat — Data Exfiltration
- Classification: Actual
- References: docs/architecture.md, scripts/launchers/launch-agent, scripts/runtime/entrypoint.sh, docs/network-proxy.md
- Description: OAuth configs (`~/.config/gh`, `~/.config/github-copilot`, etc.) and MCP API keys (`.mcp-secrets.env`) are mounted read-only but fully readable in the container. In allow-all mode the container has unrestricted outbound access, so malicious prompts can curl arbitrary endpoints or abuse MCP servers to leak tokens and repo data.

## RISK-EXF-02: MCP Tool Exfiltration
- Category: Risk/Threat — Data Exfiltration
- Classification: Actual
- References: config.toml, docs/architecture.md
- Description: MCP servers such as Context7, GitHub, fetch, and Playwright can be invoked by the agent to send arbitrary payloads to their upstream services. Without request-level allowlists or logging, an injected agent can stream sensitive repo snapshots or host secrets via these tools even if raw curl is restricted.

## RISK-LAT-01: Lateral Movement with Host Credentials
- Category: Risk/Threat — Lateral Movement
- Classification: Actual
- References: scripts/launchers/launch-agent, scripts/runtime/entrypoint.sh, docs/security-credential-proxy.md
- Description: Mounted gh/Copilot configs, credential proxy sockets, and forwarded SSH/GPG agents give the container the ability to authenticate as the host user toward GitHub or any SSH target reachable over the network. Prompt-injected commands can add new deploy keys, modify other repos, or interact with internal services reachable via SSH tunnels, enabling lateral movement beyond the workspace.

## RISK-PER-01: Persistence/Backdoors in Repo Automation
- Category: Risk/Threat — Persistence/Backdoors
- Classification: Actual
- References: scripts/runtime/entrypoint.sh, docs/architecture.md, scripts/test/test-launchers.sh
- Description: Nothing prevents an agent from modifying CI scripts, MCC configs, or documentation to insert malicious logic that will run later (e.g., altering `entrypoint.sh`, build scripts, or `config.toml`). Auto-push can propagate these backdoors to host repos silently unless reviews catch them.

## RISK-SIL-01: Silent Weakening of Security Guardrails
- Category: Risk/Threat — Silent Weakening
- Classification: Actual
- References: scripts/launchers/launch-agent, scripts/utils/common-functions.sh, docs/security-credential-proxy.md
- Description: Agents can edit launcher scripts, security docs, or config defaults (e.g., removing `--cap-drop`, changing Squid allowlists, disabling credential proxies). Nothing enforces integrity of these files beyond human review, so a compromised agent working in unrestricted mode can erode future protections.

## RISK-HST-01: Container/Host Escape via Runtime Interfaces
- Category: Risk/Threat — Container/Host Escape
- Classification: Theoretical under current config
- References: scripts/launchers/launch-agent, scripts/launchers/run-agent, docker/base/Dockerfile
- Description: No docker.sock, privileged mode, or host root filesystems are mounted; containers run as non-root with `no-new-privileges`. Capabilities are only fully dropped in `run-agent`. While direct host escape requires exploiting the kernel or Docker runtime, the absence of seccomp/AppArmor profiles and capability dropping in persistent containers leaves a larger attack surface than necessary even though no current direct path exists.

## RISK-NET-01: Network Abuse for C2
- Category: Risk/Threat — Data Exfiltration / Lateral Movement
- Classification: Actual in allow-all mode, theoretical if `restricted` enforced
- References: docs/network-proxy.md, docker/proxy/entrypoint.sh
- Description: With default `allow-all` networking, an injected agent can establish long-lived C2 connections, download arbitrary tooling, or scan reachable networks. Squid mode restricts domains but still allows GitHub/NPM-style endpoints that can act as drop points. There is no egress monitoring in allow-all mode.

## RISK-UX-01: Prompt Fatigue Leading to Unsafe Approvals
- Category: Risk/Threat — UX / Silent Weakening
- Classification: Actual (behavioral)
- References: scripts/launchers/launch-agent (branch replacement prompts), docs/architecture.md
- Description: Current safeguards rely on user prompts for branch replacement or `--use-current-branch` warnings. When prompts are reduced (as requested for unrestricted mode), the safety burden shifts entirely to structural controls. Without replacements, destructive behaviors can slip through.
