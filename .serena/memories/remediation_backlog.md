# Remediation Backlog (2025-11-16)

## Item RB-01: Persistent Container Hardening Parity
- **Source**: From Serena — HDN-CT-01, RISK-HST-01, FINDING-CA-02
- **Category**: Security / Host Isolation
- **Description**: `launch-agent` containers still retain extra Linux capabilities and writable roots compared to `run-agent`. Align all launcher modes with the hardened flag set (cap drop, `no-new-privileges`, pids/memory limits, read-only root with explicit tmpfs overlays) so unrestricted sessions do not expose a larger kernel attack surface.
- **Scope**: `scripts/launchers/launch-agent`, `scripts/launchers/connect-agent`, `scripts/launchers/launch-agent.ps1`, Docker compose snippets, documentation in `docs/architecture.md` and `docs/build.md`.
- **Evidence**: Serena findings for HDN-CT-01 and FINDING-CA-02 describe the mismatch; RISK-HST-01 notes remaining attack surface when capabilities are not dropped.
- **Severity**: Critical — leaving capabilities and writable roots dramatically increases chances of host escape.
- **Impact**: High — compromise would expose host and any mounted secrets.
- **Likelihood**: Medium — requires exploit but persistent sessions are common and long-lived.
- **Effort**: Medium — flag parity plus read-only root plumbing touches multiple launcher scripts but reuses existing patterns from `run-agent`.

## Item RB-02: Enforce Opinionated Seccomp/AppArmor Profiles
- **Source**: From Serena — HDN-CT-02, RISK-HST-01
- **Category**: Security / Host Isolation
- **Description**: Containers currently rely on Docker defaults without explicit seccomp/AppArmor. Ship curated profiles that block dangerous syscalls (ptrace, mount, clone3) and apply them from launch scripts so kernel-level escapes remain theoretical. Provide repo-stored profiles plus tests that ensure they load on Docker and Podman.
- **Scope**: `docker/base/Dockerfile`, new `docker/profiles/*.json|*.profile`, launcher scripts that add `--security-opt seccomp=... --security-opt apparmor=...`, docs updates.
- **Evidence**: HDN-CT-02 proposal and RISK-HST-01 call out the absence of hardened syscall filters.
- **Severity**: High — missing syscall filters widens the exploit surface though still requires 0-day.
- **Impact**: High — successful kernel escape compromises host.
- **Likelihood**: Medium-Low — needs advanced exploit, but defense-in-depth expected for unrestricted mode.
- **Effort**: Medium — create profiles once and reuse; requires compatibility testing across runtimes.

## Item RB-03: Snapshot-on-Launch & Rollback Automation
- **Source**: From Serena — HDN-FS-01, RISK-DES-01, RISK-PER-01
- **Category**: Filesystem / Git Safety
- **Description**: Automatically snapshot the host repo (commit/tag + metadata) before copying into `/workspace`, persist the session SHA, and deliver a `rollback-agent` helper so destructive agents cannot silently wipe host history. Integrate auto-snapshot metadata into entrypoint logging and ensure auto-push references the snapshot ID.
- **Scope**: `scripts/launchers/launch-agent`, `scripts/utils/common-functions.sh`, `scripts/runtime/entrypoint.sh`, docs in `docs/architecture.md` and `docs/cli-reference.md`.
- **Evidence**: HDN-FS-01 design plus RISK-DES-01 and RISK-PER-01 describe how destructive edits propagate today.
- **Severity**: High — without snapshots a malicious agent can permanently delete repo history when auto-push fires.
- **Impact**: High — affects host repo integrity and CI pipelines.
- **Likelihood**: High — prompt-injected destructive commands are easy to trigger.
- **Effort**: Medium — new snapshot helper and metadata plumbing but relies on git operations already available.

## Item RB-04: Writable-Path Whitelist & Safe Package Zones
- **Source**: From Serena — HDN-FS-02, RISK-SIL-01, AC-02
- **Category**: Filesystem Isolation / Build Safety
- **Description**: Convert the container root to read-only, expose only a small, auditable set of writable mounts (workspace, tmpfs). Provide dedicated overlays or env-var-configured cache dirs (`/tool-scratch`) and a `safe_pkg` wrapper so package managers can install dependencies without opening sensitive paths (launchers, scripts). Enforce deny rules for `/scripts` and other policy files, preventing silent weakening by malicious prompts.
- **Scope**: Dockerfiles for agent images, `scripts/runtime/entrypoint.sh`, build docs, package wrapper scripts under `scripts/utils`.
- **Evidence**: HDN-FS-02 plan plus AC-02 attack chain showing launcher tampering risk.
- **Severity**: High — unrestricted writes allow stealthy backdoors in launcher/runtime files.
- **Impact**: High — tampered launchers compromise all future sessions.
- **Likelihood**: Medium — requires malicious prompt but attack path already demonstrated.
- **Effort**: Large — read-only root plus wrapper design touches container build, runtime scripts, and documentation.

## Item RB-05: Proxy-First Networking with Tiered Allowlists
- **Source**: From Serena — HDN-NET-01, RISK-EXF-01, RISK-NET-01, GOAL-NET-01
- **Category**: Network / Exfiltration Control
- **Description**: Make Squid proxy mode the default for unrestricted sessions, expand allowlists per tier (core dev domains, MCP-only domains), block RFC1918/metadata ranges, and ensure logs stream to host. `allow-all` becomes an explicit Tier 3 override with clear warnings.
- **Scope**: `scripts/launchers/launch-agent`, `docker/proxy/entrypoint.sh`, `docs/network-proxy.md`, configuration defaults in `config.toml`.
- **Evidence**: HDN-NET-01 design plus risks RISK-EXF-01/RISK-NET-01 highlight current unrestricted egress.
- **Severity**: Critical — unrestricted egress enables immediate secret exfiltration and C2.
- **Impact**: High — affects host secrets and customer code.
- **Likelihood**: High — allow-all is the current default, so abuse is trivial.
- **Effort**: Medium — proxy mode already exists; need configuration flips, expanded lists, and logging hookups.

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

## Item RB-07: Secret Broker for Shared Credentials
- **Source**: From Serena — HDN-SEC-01, RISK-EXF-01, RISK-LAT-01
- **Category**: Secrets Handling / Lateral Movement
- **Description**: Replace direct mounting of `~/.config/gh`, `.mcp-secrets.env`, etc., with a broker that hands out short-lived scoped tokens per session. Inject secrets via env vars stored on tmpfs, record broker audit logs, and ensure tokens are revoked on kill-switch. Maintain compatibility with existing OAuth flows while preventing long-lived credentials from residing in the container filesystem.
- **Scope**: Host-side service (likely under `scripts/runtime`), launcher changes to request tokens, entrypoint teardown hooks, documentation in `docs/security-credential-proxy.md`.
- **Evidence**: HDN-SEC-01 design and risks RISK-EXF-01/RISK-LAT-01 on credential exposure.
- **Severity**: Critical — exposed OAuth tokens enable immediate exfil and lateral movement.
- **Impact**: High — compromise extends beyond repo to GitHub/org resources.
- **Likelihood**: High — agent can already `cat` mounted files or use proxied sockets.
- **Effort**: Large — new broker service, lifecycle hooks, and UX changes.

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

---

## Groupings
- **Host Isolation & Sandboxing**: RB-01, RB-02, RB-04
- **Filesystem & Git Safety**: RB-03, RB-04
- **Network Governance & Exfiltration Control**: RB-05, RB-06
- **Secrets & Credential Mediation**: RB-07, RB-08
- **Tool Policy & Safe Abstractions**: RB-09, RB-10
- **Monitoring & Response**: RB-11 (depends on data from RB-03/RB-05/RB-07)

## Dependencies
- RB-04 depends on RB-01 (need hardened container flags/read-only roots first).
- RB-02 builds on RB-01 but can ship in parallel once baseline flag parity exists.
- RB-06 depends on RB-05 (proxy-first infra needed to mediate fetch traffic).
- RB-07 is a prerequisite for RB-08 (policy layer assumes broker-managed secrets) and RB-11 (kill switch must revoke brokered tokens).
- RB-09 enables RB-10 (tier enforcement hooks into the safe abstractions).
- RB-11 relies on telemetry produced by RB-03 (snapshot IDs) and RB-05 (proxy logs).

---

## Prioritized Backlog (Ranked)
| Priority | Item | Category | Severity / Impact / Likelihood / Effort | Dependencies | Rationale |
| --- | --- | --- | --- | --- | --- |
| **P0.1** | RB-05 Proxy-First Networking | Network | Critical / High / High / Medium | None | Immediate egress control without prompts closes the fastest exfil path and enables downstream monitoring work.
| **P0.2** | RB-07 Secret Broker | Secrets | Critical / High / High / Large | None | Removing long-lived credentials from containers drastically limits blast radius even before other defenses land.
| **P0.3** | RB-01 Container Hardening Parity | Host Isolation | Critical / High / Medium / Medium | Enables RB-04/RB-02 | Ensures every session (not just `run-agent`) benefits from the safest runtime flags before agents continue using unrestricted mode.
| **P1.4** | RB-03 Snapshot & Rollback | FS Safety | High / High / High / Medium | None | Provides recoverability if P0 controls fail; easy to implement using git primitives.
| **P1.5** | RB-04 Writable Whitelist & Safe Package Zones | FS Safety | High / High / Medium / Large | Depends on RB-01 | Blocks launcher tampering attack chain and enables read-only roots.
| **P1.6** | RB-02 Seccomp/AppArmor Profiles | Host Isolation | High / High / Med-Low / Medium | Builds on RB-01 | Shrinks host escape surface once container flags are consistent.
| **P2.7** | RB-06 Fetch Governance | Network Tooling | High / Med-High / Medium / Medium | Depends on RB-05 | Adds fine-grained throttles for the riskiest MCP channel after proxy default is in place.
| **P2.8** | RB-09 Safe Abstractions | Tool Policy | High / High / High / Med-Large | None | Central command mediation reduces reliance on prompts and underpins policy enforcement.
| **P2.9** | RB-10 Tool Tier Enforcement | Tool Policy | High / Med-High / High / Medium | Depends on RB-09 | Turns policy definitions into enforcement once safe abstractions exist.
| **P3.10** | RB-08 SSH/GPG Policy Layer | Secrets | High / High / Medium / Medium | Depends on RB-07 | Once brokered secrets exist, clamp forwarded sockets and require intentional enablement.
| **P3.11** | RB-11 Observability & Kill Switch | Monitoring | Med-High / Med-High / Medium / Medium | Depends on RB-03/RB-05/RB-07 | Completes the loop with correlated telemetry and incident response once upstream data sources exist.

---

## Phased Implementation Plan

### Phase 0 — Immediate Safeguards (Now)
- **Goals**: Clamp outbound exfiltration, remove long-lived secrets from containers, and equalize container hardening so unrestricted mode cannot worsen host risk.
- **Items**: RB-05, RB-07, RB-01.
- **Expected Outcome**: Default sessions run behind a logging proxy with no unrestricted egress, tokens are short-lived and attributable, and all containers drop capabilities + use read-only roots.

### Phase 1 — Structural Safety Enhancements (Next)
- **Goals**: Provide automatic recovery (snapshots), enforce writable-path controls, and layer syscall filtering to shrink the kernel attack surface.
- **Items**: RB-03, RB-04, RB-02.
- **Expected Outcome**: Destructive edits become reversible, launchers/runtime files cannot be modified silently, and containers gain defense-in-depth via seccomp/AppArmor.

### Phase 2 — Tool Policy & Secret Governance (Later)
- **Goals**: Tighten MCP/high-risk tool channels, mediate shell/network/file operations via safe abstractions, and enforce Tier 3 gating without user fatigue.
- **Items**: RB-06, RB-09, RB-10, RB-08.
- **Expected Outcome**: High-volume fetch operations are throttled/logged, commands flow through policy-aware wrappers, Tier 3 actions surface clear confirmations, and SSH/GPG forwarding follows strict allowlists.

### Phase 3 — Observability & Response (Sustain)
- **Goals**: Correlate telemetry across subsystems and give operators a reliable kill switch that revokes brokered credentials.
- **Items**: RB-11 (consumes telemetry from earlier phases).
- **Expected Outcome**: Every session has audit-quality logs tied to session IDs, and suspicious agents can be terminated with automatic token revocation and forensic preservation.

---

## Cross-Check Notes (2025-11-16)
- **RB-05**: `scripts/launchers/launch-agent` lines ~325–347 still default to Docker bridge (`NETWORK_MODE="bridge"`, `NETWORK_PROXY` default `allow-all`), so unrestricted egress remains the norm unless the user explicitly chooses Squid.
- **RB-07**: `scripts/launchers/launch-agent` lines ~468–505 mount `~/.config/gh`, `~/.config/github-copilot`, and `.mcp-secrets.env` directly into the container, confirming the broker does not exist yet.
- **RB-01**: `scripts/launchers/launch-agent` final arg block (lines ~600–635) lacks `--memory-swap`, `--read-only`, and tmpfs mounts that `scripts/launchers/run-agent` (lines ~600–635) already apply, so parity remains incomplete.
- **RB-03**: No references to “snapshot” or rollback helpers exist in `scripts/launchers/launch-agent`, `scripts/runtime/entrypoint.sh`, or supporting scripts, confirming automatic snapshots have not been implemented.
