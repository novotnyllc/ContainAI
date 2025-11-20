# Remediation Backlog (2025-11-16)

## Item RB-06: High-Risk MCP & Fetch Governance
- **Source**: From Serena — HDN-NET-02, RISK-EXF-02, Tool Danger Matrix
- **Category**: Network Monitoring / Tool Policy
- **Description**: Route the `fetch` MCP and any generic HTTP tooling through a dedicated policy channel that enforces per-session data caps, rate limits, and detailed request logging. Attach session IDs to logs, provide host alerts when bandwidth spikes, and expose controls to pause these tools without touching the container runtime.
- **Scope**: `config.toml`, `docker/proxy/entrypoint.sh`, `agent-configs/*`, docs describing MCP safety.
- **Evidence**: HDN-NET-02 mitigation requirement plus RISK-EXF-02 and Tool Danger Matrix classification for fetch actions.
- **Severity**: High — MCP fetch can bypass proxy governance and stream arbitrary data.
- **Impact**: Medium-High — leaks repo contents or secrets via tool interfaces.
- **Likelihood**: Medium — requires the agent to intentionally abuse fetch, which is common under prompt injection.
- **Effort**: Medium — policy layer plus logging but limited surface area (single MCP server).


## Item RB-08: SSH/GPG Policy Layer & Default-Off Forwarding
- **Source**: From Serena — HDN-SEC-02, RISK-LAT-01, Safe Profile
- **Category**: Secrets / Lateral Movement
- **Description**: Wrap forwarded SSH/GPG sockets with policy daemons that restrict allowed hostnames/operations, disable forwarding by default in unrestricted mode, and require explicit Tier 3 enablement with logging. Provide host-side enforcement to block outbound SSH to non-allowlisted targets, reducing lateral movement paths.
- **Scope**: `scripts/runtime/gpg-host-proxy.sh`, `scripts/runtime/git-credential-proxy*`, launcher flags, docs.
- **Evidence**: HDN-SEC-02 proposal plus RISK-LAT-01 describing misuse of forwarded credentials.
- **Severity**: High — uncontrolled SSH/GPG forwarding can compromise other repos or infra.
- **Impact**: High — enables lateral movement and key misuse.
- **Likelihood**: Medium — requires the user to forward sockets, but common for advanced workflows.
- **Effort**: Medium — extend existing proxies with allowlists and toggles.

## Item RB-09: Safe Shell/FS/Network Abstractions
- **Source**: From Serena — HDN-TL-01, Safe Abstractions (SA-01..04), Tool Danger Matrix
- **Category**: Tool Policy / Command Mediation
- **Description**: Introduce `safe_sh`, `safe_write`, `safe_net`, and `safe_secret` wrappers that enforce path whitelists, redact sensitive arguments, and log all Tier 2 commands. Hook agent session defaults and MCP editing tools into these abstractions so destructive shell patterns and writes outside `/workspace` are blocked without prompting.
- **Scope**: `scripts/runtime/agent-session`, `scripts/utils/common-functions.sh`, `agent-configs/AGENTS.md`, documentation for new commands.
- **Evidence**: HDN-TL-01 plus Safe Abstraction memory entries outlining wrapper requirements.
- **Severity**: High — without mediation, prompt-injected shell commands have unrestricted power.
- **Impact**: High — can delete repos, read secrets, or alter security configs.
- **Likelihood**: High — shell commands are the default agent action vector.
- **Effort**: Medium-Large — requires new wrappers and integration with VS Code terminals and MCP tooling.

## Item RB-10: Tool Tier Enforcement & Tier-3 Gating
- **Source**: From Serena — Tool Danger Matrix, UX Policy, GOAL-UX-02
- **Category**: Tool Policy / Governance
- **Description**: Codify Tier 1/2/3 behavior inside launchers and MCP definitions: silent logging for Tier 2 actions (package installs, git push local), enforced prompts or blocks for Tier 3 (git push origin, altering security configs, enabling allow-all networking). Integrate with safe abstractions to ensure enforcement is centralized and auditable.
- **Scope**: `config.toml`, `agent-configs/*`, `scripts/launchers/*`, documentation of prompt policy.
- **Evidence**: Tool Danger Matrix table and UX policy memory specifying tiers.
- **Severity**: High — without enforcement, high-risk actions proceed silently.
- **Impact**: Medium-High — leads to accidental publishes or policy tampering.
- **Likelihood**: High — git push origin and policy edits are common tasks.
- **Effort**: Medium — mostly policy plumbing plus prompt UX.

## Item RB-11: Session Observability & Kill Switch Wiring
- **Source**: From Serena — GOAL-MON-01, Safe Profile, Attack Chains AC-01/AC-02
- **Category**: Monitoring / Incident Response
- **Description**: Ensure every session emits correlated telemetry: Squid logs, command logs, snapshots, and kill-switch state tied to a session ID. Provide a one-step `coding-agents kill <session>` command that tears down the container, revokes brokered secrets, preserves forensic artifacts, and sets quarantine markers for follow-up.
- **Scope**: `scripts/launchers/launch-agent`, `scripts/runtime/agent-session-runner`, proxy logging plumbing, docs in `docs/security-credential-proxy.md` and `docs/network-proxy.md`.
- **Evidence**: GOAL-MON-01, Safe Profile description of kill switch, attack chains detailing need for rapid response.
- **Severity**: Medium-High — limited observability hampers response to active compromises.
- **Impact**: Medium-High — delays containment of malicious agents.
- **Likelihood**: Medium — incidents are likely during unrestricted prompting.
- **Effort**: Medium — log wiring and CLI integration building on existing scripts.

