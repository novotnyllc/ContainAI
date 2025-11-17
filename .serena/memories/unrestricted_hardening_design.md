# Structural Hardening Design

## HDN-CT-01: Align Persistent Containers with Ephemeral Hardening
- Category: Design Pattern — Container Hardening
- Mitigates: RISK-HST-01, RISK-LAT-01
- References: scripts/launchers/launch-agent, scripts/launchers/run-agent
- Proposal: Port the `run-agent` safety flags (`--cap-drop=ALL`, `--pids-limit=4096`, `--memory-swap=$MEMORY`) to `launch-agent` so both persistent and auto-attached sessions run with identical capability surfaces. Keep `--security-opt no-new-privileges:true` and add `--read-only` root filesystem with explicit writable tmpfs for `/workspace`, `/home/agentuser`, and `/tmp`. UX impact is silent; container image already contains all tools.

## HDN-CT-02: Enforce Seccomp/AppArmor Profiles
- Category: Design Pattern — Container Hardening
- Mitigates: RISK-HST-01
- References: docker/base/Dockerfile, scripts/launchers/launch-agent
- Proposal: Ship opinionated seccomp and AppArmor profiles (stored under `docker/profiles/`) that drop dangerous syscalls (`ptrace`, `mount`, `clone3` with CLONE_NEWUSER, etc.) and enforce them via `--security-opt seccomp=... --security-opt apparmor=...`. Profiles can default to Docker's `seccomp.json` variant tuned for dev workloads. Silent UX; prompts not needed once profile is in place.

## HDN-FS-01: Snapshot-on-Launch & Auto-Revert Branch Flow
- Category: Design Pattern — Filesystem/Git Safety
- Mitigates: RISK-DES-01, RISK-PER-01
- References: scripts/runtime/entrypoint.sh, scripts/launchers/launch-agent
- Proposal: Before copying `/tmp/source-repo` into `/workspace`, create a git commit/tag in the host repo (e.g., `coding-agents/snapshots/<timestamp>`). Track this snapshot inside the container (store commit SHA in `/workspace/.coding-agents/session.json`). Provide a `scripts/launchers/rollback-agent` helper to reset the host branch to this snapshot if destruction detected. No prompts required; snapshots automatic and reversible.

## HDN-FS-02: Writable Paths Whitelist + Package Safe Zones
- Category: Design Pattern — Filesystem Isolation
- Mitigates: RISK-SIL-01 while preserving dev builds
- References: docker/base/Dockerfile, docs/architecture.md
- Proposal: Keep root filesystem largely read-only but carve out dedicated writable overlays for directories build tooling legitimately touches:
  - Mount tmpfs volumes for `/tmp`, `/var/tmp`, `/var/cache/apt`, `/var/lib/apt/lists`, `/var/lib/dpkg`, and language-specific caches (e.g., `/home/agentuser/.cache`, `/home/agentuser/.npm`, `/home/agentuser/.nuget`, `/home/agentuser/.local`)
  - Provide optional bind-mounted “tooling scratch” volume (e.g., `/tool-scratch`) that package managers can target via env vars (`PIP_CACHE_DIR`, `NPM_CACHE_DIR`).
  - Add a `safe_pkg` wrapper that temporarily bind-mounts additional writable overlays (using `mount --bind` inside the namespace) only for approved directories when commands like `apt install` or `dotnet workload install` run, ensuring dev builds that invoke package managers continue to work without granting blanket root write access.
  - Document required env overrides in `docs/build.md` so project builds know where caches live.

## HDN-NET-01: Default to Logged Proxy Mode with Tiered Allowlist
- Category: Design Pattern — Network
- Mitigates: RISK-EXF-01/02, RISK-NET-01
- References: docs/network-proxy.md, docker/proxy/entrypoint.sh
- Proposal: Make Squid (or a hardened egress proxy) the default for unrestricted mode. Expand `SQUID_ALLOWED_DOMAINS` to tiered sets: Tier A (always on): GitHub, Microsoft docs, package registries; Tier B (MCP-specific): allow per-config entries (Context7, Serena git). Block RFC1918/metadata ranges explicitly. Log every request to host (mount proxy logs read-only for analysis). Provide optional `--network-proxy allow-all` but gate it as Tier 3 (prompt or admin knob). Silent for default flows because safe domains already cover typical dev needs.

## HDN-NET-02: Outbound Token Bucket
- Category: Design Pattern — Network Monitoring
- Mitigates: RISK-EXF-01/02, RISK-NET-01
- References: docker/proxy/entrypoint.sh
- Proposal: Add egress byte throttling per container via the proxy (Squid delay pools or tc in sidecar). Trigger alerts/logs when transfer volume exceeds configurable thresholds. No prompts; actions logged for review.

## HDN-SEC-01: Secret Broker Service (Shared-Cred Compatible)
- Category: Design Pattern — Secrets
- Mitigates: RISK-EXF-01, RISK-LAT-01
- References: scripts/launchers/launch-agent, docs/security-credential-proxy.md
- Proposal: Even when third-party services cannot issue per-agent tokens, avoid mounting `~/.config/gh` or `.mcp-secrets.env` by having a host-side broker hand out short-lived *session copies* of the shared secrets. Launchers request a time-limited blob (tagged with session ID) that is injected via env vars and wiped on shutdown/kill-switch. All `gh` operations continue to flow through the credential proxy, but the real credential never resides on disk inside the container, and broker logs provide attribution for every exposure of the shared token.

## HDN-SEC-02: SSH/GPG Policy Layer
- Category: Design Pattern — Secrets
- Mitigates: RISK-LAT-01
- References: scripts/launchers/launch-agent, scripts/runtime/entrypoint.sh
- Proposal: When forwarding SSH or GPG sockets, wrap them in policy daemons that restrict allowed hosts/operations (e.g., only git remotes matching the workspace’s origin). Deny agent-initiated SSH to arbitrary hosts unless user explicitly approves once outside the session (Tier 3 prompt). Logging only for allowed operations.

## HDN-TL-01: Safe Shell & FS Abstractions
- Category: Safe Abstraction
- Mitigates: Multiple risks
- References: scripts/runtime/agent-session, scripts/utils/common-functions.sh
- Proposal: Introduce host-side wrappers (e.g., `safe_sh`, `safe_write`) that enforce path whitelists and scrub commands before execution. Agents request operations through these wrappers rather than direct `bash`. Implementation could hook into MCP tool definitions (Serena’s editing, file create) to prevent `rm -rf /`. UX impact minimal because wrappers map to same semantics unless command is clearly dangerous.
