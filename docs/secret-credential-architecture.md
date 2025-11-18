# Secret Credential Isolation Architecture

This document explains how Coding Agents restricts access to long-lived credentials (Copilot/Codex/Context7, MCP bearer tokens, GitHub PATs, etc.) while still allowing immutable MCP binaries to run unmodified. It is written from the perspective of the trusted launcher (`scripts/launchers/*`) and the host-resident secret broker they coordinate with.

## Objectives

1. **Enforce trust boundaries** – Only launcher-managed stubs may ever ask for MCP or agent credentials.
2. **Prevent accidental disclosure** – Secrets never hit command lines, disk, or shared sidecars; they live in per-process tmpfs or `memfd` regions.
3. **Contain compromise** – An agent process can only exfiltrate the credentials it legitimately owns for that session. Capabilities, tmpfs mounts, and broker policy keep the blast radius per agent/MCP.
4. **Provide audit + revocation** – Every credential issuance is linked to a session ID, hash measurement, and PID namespace so kill switches can revoke fast and operators can reconstruct events.

## Components and Trust Boundaries

| Component | Trust Level | Responsibility |
| --- | --- | --- |
| `launch-agent` / `run-agent` (host) | Trusted | Builds containers, hashes stubs, requests broker capabilities, wires tmpfs mounts.
| Secret Broker (host daemon) | Trusted | Stores master secrets, validates capabilities, streams secrets via one-time handles.
| Git tree attestation (`scripts/launchers/**`, stubs) | Trusted data | Launcher verifies these paths are clean vs. `HEAD` (and records the tree hash) before secrets are issued, so bits exactly match the current commit.
| Agent container runtime | Partially trusted | Runs untrusted code but with seccomp/AppArmor, read-only roots, and dedicated tmpfs for sensitive material.
| MCP Stub Wrappers | Trusted binaries inside container | Immutable helpers responsible for redeeming capabilities and launching MCPs.
| Squid proxy | Shared service | Provides egress filtering/logging only; never stores credentials.

## Automatic Initialization & Health Guarantees

Any launcher command that issues, stores, redeems, or health-checks secrets triggers `_ensure_broker_files`, which performs the following idempotent operations:

```mermaid
flowchart TB
    start["Launcher / Broker CLI"] --> ensureDir["Create broker.d directory (chmod 700)"] --> keyStore["Seed keys.json (per stub HMAC keys)"] --> stateFile["Seed state.json (rate limits + used tokens)"] --> secretsFile["Seed secrets.json (sealed store)"] --> lock["Optionally chattr +i for immutability"]

    classDef stage fill:#d4edda,stroke:#28a745,color:#111;
    class start,ensureDir,keyStore,stateFile,secretsFile,lock stage;
```

- Existing files are preserved; missing stubs silently gain keys so new MCP helpers can be added via config alone.
- `secret-broker.py health` and launcher audit hooks rely on the same helper to confirm the files exist before continuing, ensuring drift or accidental deletion is caught immediately.
- Because initialization happens lazily, CI and developers never have to remember a bootstrap command—running any launcher is enough.

## Launch-Time Capability Provisioning

```mermaid
sequenceDiagram
    autonumber
    participant Host as "Host launch-agent"
    participant Git as "Git (HEAD state)"
    participant Broker
    participant Container as "Agent Container"

    Host->>Git: "Verify launchers/stubs are clean vs HEAD"
    Host->>Git: "Record tree hash for audit log"
    Host->>Host: "Hash bundled agent + MCP stub binaries"
    Host->>Broker: "Request capability tokens (session + stub IDs)"
    Broker-->>Host: "Scoped, single-use capability blobs"
    Host->>Container: "Start container (seccomp/AppArmor, readonly root)"
    Host->>Container: "Bind per-stub tmpfs mounts + drop capability blobs"
    Note over Container: No untrusted code has run yet&#59; only launcher and stubs exist
```

This sequence only runs after the host and container runtimes pass the security preflight described in `docs/architecture.md`. If seccomp/AppArmor cannot be guaranteed, the broker never receives a capability request, preventing secrets from leaving the host.

Key points:

- Capability tokens encode session ID, target stub hash, cgroup/pid namespace, and expiry.
- Tokens are stored in broker-managed tmpfs directories with `chmod`/`chown` locking them to the stub user; general agent workloads cannot read them.
- If any launcher or stub file is dirty relative to `HEAD` (or its tree hash shifts unexpectedly), `launch-agent` refuses to start the container until the git state is restored.
- Agent containers set `kernel.yama.ptrace_scope=3` (via privileged helper) and rely on `seccomp`/AppArmor profiles that block `ptrace`, `process_vm_*`, and `/proc/<pid>/mem` access against stub UIDs, preventing credential snooping even from processes in the same namespace.

## Host-Synthesized Session Configs

`config.toml` remains user-editable, but the launcher renders a session-specific view before any containerized code starts:

1. Read `config.toml` plus CLI overrides on the host.
2. Merge runtime facts (session ID, network mode, tmpfs mount points, capability token paths).
3. Write the merged config into the agent tmpfs (`nosuid,nodev,noexec,0700`) and record its SHA256 in the audit log (`session-config` event) for traceability.
4. Pass the config path to the agent entrypoint. Because it is generated anew each launch, changes to `config.toml` are picked up automatically without relaxing integrity checks on trusted scripts.

## Mutual Authentication & Session-Derived Secrets

- During installation (or first run), the broker creates random per-stub shared keys under `~/.config/coding-agents/broker.d/secrets.json` and never places them in git or containers.
- When a stub redeems a capability, it signs the request with `HMAC(shared_key, nonce || capability_id)`; the broker validates before streaming any secret.
- Static upstream secrets (e.g., Context7) are envelope-encrypted per session: `session_key = HMAC(master_secret, session_id || timestamp)`. The broker transmits `Enc(session_key, api_secret)` plus the nonce so that leaking a tmpfs only reveals ciphertext tied to that session.
- All tmpfs mounts that hold configs, shared keys, or decrypted secrets are mounted as private, `nosuid,nodev,noexec`, and use dedicated UIDs so other processes—even within the same container—cannot traverse them.
- SSE/HTTPS helper processes run under unique UIDs with dedicated seccomp/AppArmor profiles that only permit loopback IPC plus outbound HTTPS to the intended MCP endpoint; they cannot access host files beyond their tmpfs.

## Additional Hardening Controls

- **Syscall + namespace isolation** – Every stub and helper runs inside its own PID namespace with `ptrace` fully disabled and `procfs` mount options `hidepid=2,gid=agentproc` so agent workloads cannot inspect other processes.
- **Broker sandboxing** – The broker executes as a `systemd --user` service with `ProtectSystem=strict`, `ProtectHome=read-only`, `NoNewPrivileges=yes`, `PrivateTmp=yes`, and a custom seccomp filter limited to file/socket syscalls. Per-stub mutual-auth keys reside in `~/.config/coding-agents/broker.d/` with `chmod 600` and `chattr +i` so only the host user can edit them.
- **Rate limiting & watchdog** – The broker enforces per-session capability quotas and exponential backoff on repeated failures; a host-side watchdog halts new launches if the broker exits, loses its seccomp/AppArmor profiles, or detects tampering with the shared-key store.
- **Immutable audit trail** – Issuance events (including generated config SHA256, git tree hash, capability IDs) are logged to `journald` with persistent storage and mirrored to an append-only file. Optional off-host shipping (scp/HTTPS) provides tamper-evident history.
- **Dev overrides** – If developers need to run with modified launchers/stubs, they create a host-only override token (e.g., `~/.config/coding-agents/overrides/allow-dirty`). Launcher requires the token and logs its use so deviations are explicit.

### Helper Sandbox Policies

- **Network policy:** Helper runners default to `--network none`, exposing only loopback IPC. Override with `CODING_AGENTS_HELPER_NETWORK_POLICY=host|bridge|<docker-network>` if a specific helper truly requires egress.
- **Tmpfs isolation:** `/tmp` and `/var/tmp` inside helper containers are tmpfs mounts (`nosuid,nodev,noexec`) sized 64MB/32MB to prevent secrets from ever touching disk.
- **Resource clamps:** `CODING_AGENTS_HELPER_PIDS_LIMIT` (default `64`) and `CODING_AGENTS_HELPER_MEMORY` (default `512m`) bound helper processes so compromised helpers cannot starve the host.
- **Seccomp/AppArmor parity:** `resolve_seccomp_profile_path` injects the same ptrace-denying profile used by the main agent, and AppArmor (when available) assigns helpers to the `coding-agents` profile to block filesystem escapes.

### Audit Trail & Override Workflow

- **Log location:** Unless overridden via `CODING_AGENTS_AUDIT_LOG`, launchers append newline-delimited JSON to `~/.config/coding-agents/security-events.log` and mirror each event to `systemd-cat -t coding-agents-launcher`.
- **Event taxonomy:**
    - `session-config` – session ID, manifest SHA256, git `HEAD`, trusted tree hashes
    - `capabilities-issued` – session ID, requested stubs, capability IDs emitted by the broker
    - `override-used` – repo path, label, and list of trusted files that were dirty when the override token was honored
- **Operational use:** Tail the file during development (`tail -f ~/.config/coding-agents/security-events.log`) to capture manifest hashes for change-management tickets, or feed it into your SIEM/log shipper.
- **Override tokens:** A launch only succeeds on dirty trusted files if `~/.config/coding-agents/overrides/allow-dirty` (configurable via `CODING_AGENTS_DIRTY_OVERRIDE_TOKEN`) exists. Deleting the token immediately restores strict enforcement, and every use is auditable via the log above.

## Secret Redemption and MCP Launch Flow

```mermaid
flowchart TD
        subgraph Command MCP
                AC[Vendor agent] -->|execve intercepted| RC[agent-task-runner]
                RC -->|capability request| BR[Secret Broker]
                BR -->|memfd secret| ST[Per-MCP stub (UID mcp_X)]
                ST -->|STDIO bridge| AC
                ST -->|sandboxed network| NET1[Allowed domains]
        end
        subgraph HTTPS/SSE MCP
                AV[Vendor agent (agentcli namespace)] -->|read config secret| CFG[Generated MCP config]
                AV -->|HTTPS request with secret| NET2[Remote MCP endpoint]
                AV -.->|spawn helper?| RC2[agent-task-runner denies access to /run/agent-secrets]
        end
```

Key points:

- MCP entries come in two flavors:
    1. **Command-based** (e.g., Serena, Playwright). These follow the exec-intercept + stub flow shown above: the runner launches the stub under a dedicated UID, secrets live inside stub tmpfs, and STDIO/IPC is bridged back to the vendor agent.
    2. **HTTPS/SSE endpoints** (e.g., Context7, GitHub MCP, Microsoft Learn). The vendor agent process itself performs the HTTPS call using the API key embedded in the generated config. No stub process exists; instead the config file is readable only inside the `agentcli` namespace.
- Even for HTTPS/SSE entries, exec interception matters because any helper the agent spawns while handling responses still goes through the runner and therefore cannot read `/run/agent-secrets` or the config directories. The vendor agent remains the only process with access to those secrets.
- Command-based MCPs retain stubs to provide per-server UIDs, tmpfs cleanup, network/seccomp policy enforcement, and broker-audited lifecycle management. HTTPS MCPs rely on the vendor agent’s namespace isolation to keep secrets away from untrusted subprocesses while still allowing the agent to embed tokens in outbound requests.

### Why MCP Stubs Still Exist (Command Mode)

For command-based MCPs, the seccomp intercept removes the need for vendor binaries to spawn helper processes directly, but the stub layer continues to provide guarantees the vendor agent does not implement. Treat the vendor agent as “trusted for intent” and the stub as “trusted for containment”:

1. **Per-MCP identities and namespaces** – Each stub runs under a unique Unix user/AppArmor label (`mcp_context7`, `mcp_serena`, etc.) with its own mount + network namespace. If a server-side binary (often npm/pip modules) is compromised, it can only access the tmpfs and network rules assigned to that server, not the rest of the agent environment.
2. **Broker integration and revocation** – Stubs redeem sealed capabilities, log issuance, zeroize memfds, and revoke permissions when a session ends. Letting the vendor agent consume raw API keys for command-based servers would bypass those controls and force secrets to live indefinitely in its workspace.
3. **Transport mediation** – Many command MCPs actually chain to host helpers (e.g., SSE bridges) or require bespoke startup logic (`npx`, `uvx`, `python`). Stubs encapsulate that logic and expose only STDIO/JSON to the agent, keeping the transport surface auditable.
4. **Fine-grained outbound policy** – Stubs ship with server-specific seccomp filters, DNS allow-lists, TLS pinning, filesystem visibility, and rate-limiters. Rebuilding those rules inside each vendor binary would be brittle and difficult to audit.
5. **Lifecycle hygiene + auditing** – When a stub exits, it scrubs tmpfs, closes broker descriptors, emits audit events, and can revoke the capability. Without that cleanup, command MCPs would leak decrypted secrets and disappear from the security log.

HTTPS/SSE MCPs do not require a stub because the vendor agent itself makes the network call and already sits inside the restricted `agentcli` namespace. The intercept layer ensures only that process can read the generated config and send authenticated traffic; everything it spawns still goes through the task runner and therefore cannot reach the secrets.

## Handling Static Secrets (e.g., Context7)

Static API keys cannot be rotated on demand, so safeguards focus on limiting exposure:

1. **Selective capability issuance** – Only sessions configured to use Context7 receive tokens that can request that key. Other agents cannot even ask.
2. **Per-session tmpfs** – The key is streamed into a tmpfs exclusive to the requesting stub; lateral movement within the container cannot read it without compromising that stub.
3. **Session envelope encryption** – Broker sends `Enc(HMAC(master, session data), api_key)` so even if the tmpfs is copied, the ciphertext cannot unlock future sessions without the master kept on the host.
4. **Audit + rotation** – Broker logs include session ID + timestamp; if compromise is suspected, operators rotate the upstream Context7 key once and rely on the broker to re-distribute it to trusted sessions.

## GitHub PATs

1. Host `launch-agent` calls `gh auth token --scopes repo:read` (or fine-grained PAT CLI) scoped to the active repository and public repos.
2. The resulting PAT is stored only in broker encrypted memory.
3. MCP stubs redeem capability tokens for the PAT just like any other secret.
4. Tokens expire within an hour; launchers refresh on demand. Revoking on the host (via `gh auth logout` or deleting the PAT) immediately invalidates future broker requests.

## Revocation and Monitoring

- **Kill switch** (`coding-agents kill <session>`): Signals the broker to revoke all capabilities for that session, wipe tmpfs mounts, and stop the container.
- **Telemetry**: Broker emits structured logs for issuance, redemption, and policy failures; Squid provides complementary outbound request logs for correlation.
- **Anomaly detection**: Excess secret requests, mismatched PID namespaces, or attempts to use expired tokens trigger automatic revocation and optional container teardown.

## IO Models vs. User Isolation

Agents interact with MCPs through multiple transports (STDIO, SSE, HTTPS) while each MCP stub runs under its own Unix user. The launcher wires these pieces together as follows:

1. **STDIO MCPs (in-container)**
    - Each MCP stub is executed under a dedicated UID (for example `mcp_context7`).
    - The stub forks the immutable MCP binary and keeps its stdin/stdout pipes connected to the requesting agent process (`agentuser`). Linux permissions allow this because the pipes are created before dropping privileges; only the stub-owned tmpfs with secrets/config is protected via ownership + `chmod 600`.
    - Result: untrusted agent code can still speak STDIO, but it cannot read the MCP’s credential storage area.

2. **SSE or HTTPS MCPs (host helpers)**
    - `launch-agent` spawns host-side helpers under per-MCP system users (or `systemd --user` slices). Helpers redeem their capability tokens, keep secrets in their private tmpfs, and expose only an authenticated Unix socket or localhost HTTPS endpoint to the agent container.
    - The container connects over that socket/TLS channel (optionally through the Squid proxy for auditing). Since only the helper’s UID can access the tmpfs and capability, secrets never enter the agent namespace.

3. **Mixed mode / chained MCPs**
    - Some agents launch additional MCPs from within the first MCP (e.g., tool runners). Each requested MCP still has its own UID + capability; the first stub merely acts as a broker client and never gains direct read access to the secondary MCP secrets.

In every transport, the data path (pipes, sockets, HTTP) remains compatible with the MCP’s expectations, while the credential path is locked to the stub’s UID via tmpfs ownership and broker-issued capabilities.

## Agent CLI Secret Flows

The previous sections focus on MCP secrets. Individual agents (Copilot, Codex, Claude) also rely on long-lived CLI auth files that must originate on the host. Today the launchers only mount optional config directories, so the agent-specific secrets never actually cross the trust boundary. The diagrams and work items below define how to make those flows real.

### GitHub Copilot CLI (`~/.copilot/config.json`)

```mermaid
flowchart LR
    host["Host ~/.copilot/config.json\n(copilot_tokens, logged_in_users)"]
    launcher["run-agent / launch-agent\n(secret preflight)"]
    broker["secret-broker.py\n(issue capability)"]
    bundle["/run/coding-agents/copilot\ncapability + tmpfs"]
    stub["prepare-copilot-secrets\n(container helper)"]
    cli["github-copilot-cli\n(token cache ready)"]

    host --> launcher --> broker --> bundle --> stub --> cli
```

**Current gap**
- Launchers only mount `~/.config/github-copilot` / `~/.config/gh`; the actual Copilot CLI state lives under `~/.copilot/config.json`, so tokens never enter the container.
- `init-copilot-config.sh` tries to copy from `$HOME/.copilot`, but that directory points to the container home volume, not the host mount.

**Implementation plan**
1. Extend `run-agent` / `launch-agent` (bash & PowerShell) to detect `${HOME}/.copilot/config.json` on the host, hash it, and request a capability from `secret-broker.py` (new stub `agent_copilot_cli`). Store the sealed blob plus manifest metadata under `/run/coding-agents/copilot/<session>.cap` (tmpfs, `0700`).
2. Add a bind mount for the capability directory and a tmpfs destination (e.g., `/run/agent-secrets/copilot`) in the Docker arguments so only the helper UID can read it. Stop mounting the entire host `~/.copilot` tree once the broker path is live.
3. Replace `init-copilot-config.sh` with a helper (`prepare-copilot-secrets.sh`) that redeems the capability, extracts `copilot_tokens`, `last_logged_in_user`, and `logged_in_users`, writes them into `/home/agentuser/.copilot/config.json` (`chmod 600`), and invokes the existing `merge-copilot-tokens.py` for backward compatibility.
4. Teach the helper to fall back to broker-provided GitHub CLI tokens if Copilot config is missing, while logging an audit event so operators know which identity was used.
5. Add unit/integration tests (`scripts/test/test-launchers.{sh,ps1}`) that create a fake `~/.copilot/config.json`, run the launcher with `--with-host-secrets`, and assert the container manifest contains a Copilot capability mount. Tests should also verify that the helper refuses to run unless the capability hash matches the broker response.

### OpenAI Codex CLI (`~/.codex/auth.json`)

```mermaid
flowchart LR
    hostCodex["Host ~/.codex/auth.json\n(refresh + access tokens)"]
    launcherCodex["run-agent / launch-agent\n(agent=codex)"]
    brokerCodex["secret-broker.py\n(issue agent_codex_cli)"]
    bundleCodex["/run/coding-agents/codex\ncapability, manifest"]
    stubCodex["prepare-codex-secrets\n(container helper)"]
    codexCli["codex CLI\nready to exec"]

    hostCodex --> launcherCodex --> brokerCodex --> bundleCodex --> stubCodex --> codexCli
```

**Current gap**
- Launchers only mount `~/.config/codex`, but Codex CLI stores OAuth tokens under `~/.codex/auth.json`. No code copies those tokens into the container, so `codex exec` always prompts for auth.
- Secret broker is never invoked for Codex, so there is no audit trail for when host tokens would be consumed.

**Implementation plan**
1. Define a Codex credential descriptor (JSON pointer to `refresh_token`, `access_token`, `expires_at`) and teach `run-agent` / `launch-agent` to read `~/.codex/auth.json` and call `secret-broker.py issue --stub agent_codex_cli --path ~/.codex/auth.json --json-schema codex_auth`.
2. Mount the resulting capability (e.g., `/run/coding-agents/codex/<session>.cap`) plus an empty tmpfs destination (`/run/agent-secrets/codex`) into the container with dedicated ownership.
3. Add a container helper (`prepare-codex-secrets.sh`), invoked from the entrypoint before the CLI launches, that redeems the capability, reconstructs `auth.json`, writes it to `/home/agentuser/.codex/auth.json`, and sets `chmod 600`. The helper should also populate `/home/agentuser/.config/codex/` with any non-secret defaults.
4. Modify `docker/agents/codex/Dockerfile` CMD to run the helper + validation script before `codex`. Remove the expectation that users must bind-mount their entire host config tree.
5. Extend launcher tests to assert that Codex sessions fail fast (with actionable messages) when `~/.codex/auth.json` is absent or when the broker rejects the capability, ensuring we never launch Codex without secrets wired correctly.

### Anthropic Claude CLI (`~/.claude/.credentials.json`)

```mermaid
flowchart LR
    hostClaude["Host ~/.claude/.credentials.json\nor CLAUDE_API_KEY"]
    launcherClaude["run-agent / launch-agent\n(agent=claude)"]
    brokerClaude["secret-broker.py\n(issue agent_claude_cli)"]
    bundleClaude["/run/coding-agents/claude\ncapability"]
    stubClaude["prepare-claude-secrets\n(container helper)"]
    claudeCli["claude CLI"]

    hostClaude --> launcherClaude --> brokerClaude --> bundleClaude --> stubClaude --> claudeCli
```

**Current gap**
- `init-claude-config.sh` expects `$HOME/.claude/.credentials.json`, yet launchers never mount the host `~/.claude` directory. Launches therefore proceed without credentials even though `validate-claude-auth.sh` warns.
- There is no consistent way to feed raw `CLAUDE_API_KEY` env vars through the broker when developers prefer not to store JSON files on disk.

**Implementation plan**
1. Expand launcher preflights to look for either `~/.claude/.credentials.json` or `CLAUDE_API_KEY` on the host. Whichever is present gets sealed through the broker via the `agent_claude_cli` stub; if both exist, prefer the JSON file but note the choice in the audit log.
2. Deliver the capability to `/run/coding-agents/claude/<session>.cap` and mount a tmpfs target (`/run/agent-secrets/claude`) into the container under a helper-specific UID.
3. Replace `init-claude-config.sh` with `prepare-claude-secrets.sh` that redeems the capability, writes `.credentials.json` (or synthesizes it from `CLAUDE_API_KEY`), and ensures `/home/agentuser/.claude` never leaves tmpfs. Validation should now fail closed if the capability is missing or unreadable.
4. Update the Claude Dockerfile entrypoint to run `prepare-claude-secrets.sh && validate-claude-auth.sh && claude`, ensuring credentials always exist before the CLI boots.
5. Add launcher tests that simulate both file-based and env-based Claude secrets, verifying that only the selected form appears inside the container tmpfs and that audit logs record the fallback path.

Across all three agents, the broker-issued capability flow keeps long-lived host secrets resident on the host while still letting the containerized CLI authenticate. The steps above bring the implementation in line with the documented security model and give operators traceability for every time an agent consumes a host identity.

### Host Agent Data Synchronization & Isolation

Authenticating the CLI is only half of the story; each agent also relies on non-secret working data that should persist across sessions (logs, conversation history, cached sessions) and needs stronger isolation than a blanket `-v ~/.agent:/home/agentuser/.agent`. We will treat secrets and durable data separately:

| Agent | Host root | Files to import at launch | Files to export on shutdown | Merge rule |
| --- | --- | --- | --- | --- |
| Copilot | `~/.copilot/` | `config.json` (read-only tokens), `sessions/*.json`, `logs/*.log`, `telemetry/*.jsonl` | Same globs plus any new session folders | Append by session directory name; for logs without IDs, append while truncating older than 14 days |
| Codex | `~/.codex/` | `auth.json` (via broker), `sessions/*.json`, `logs/**/*.log`, `history.jsonl` | Same plus generated `history.jsonl` | Session folders copied wholesale; `history.jsonl` merged by timestamp + dedupe on SHA256 |
| Claude | `~/.claude/` + `~/.claude.json` | `.credentials.json` (via broker), root-level `.claude.json`, `logs/**/*.log`, `sessions/*`, `attachments/*` | Same globs plus updated `.claude.json` | Preserve per-session directories; attachments copied only for `session-*` prefixes to avoid arbitrary host writes |

Design principles:

1. **Immutable import envelope** – Host launcher packs allowed files into a tarball, records SHA256 per entry, and places it in `/run/coding-agents/<agent>/data-import.tar` (tmpfs, `chmod 600`).
2. **Dedicated data tmpfs** – Containers mount `/run/agent-data/<agent>` as tmpfs owned by a new UID `agentcli` with `chmod 700`. The helper unpacks the import tar here before launching the CLI.
3. **Export tokens** – On shutdown, the helper re-packages only whitelisted paths into `/run/agent-data-export/<agent>/<session>.tar`, signs the manifest (HMAC with broker-issued per-agent key), and notifies the host via a shutdown hook (existing auto-push path).
4. **Host merge worker** – After the container exits, the launcher copies the export tar back to the host, validates the signature + file hashes, and merges into the real `~/.agent/` tree:
   - Session-scoped directories (`session-*`, `run-*`) replace any existing directory with the same name.
   - Log/history files without session IDs are merged line-wise with `tsv-append` semantics while dropping duplicates.
5. **No passthrough mounts** – We deliberately avoid bind-mounting the entire host directory so untrusted code cannot tamper with host state or glean unrelated files.

#### Preventing Unauthorized Access Inside the Container

- **Split identities:** The interactive shell continues to run as `agentuser`, but the CLI binary starts under `agentcli` using `setpriv --reuid agentcli --regid agentcli --init-groups --no-new-privs`. Only `agentcli` owns `/run/agent-data/<agent>` and `/run/agent-secrets/<agent>`.
- **Seccomp/AppArmor overlays:** Extend the existing profiles with path rules that confine `agentcli` to `/run/agent-*` plus `/home/agentuser/.config/<agent>` and prevent `agentuser` (and child processes it spawns) from traversing those directories. Linux `chmod 700` already blocks sibling UIDs; the profiles add enforcement even if privilege escalation is attempted.
- **PID namespace guard:** Launch the CLI inside its own PID namespace (`unshare --pid --fork --mount-proc`) so tools started by developers (or malicious scripts) cannot `ptrace` or inspect `/proc/<pid>` to locate the data tmpfs.
- **Helper-mediated IPC only:** Child processes spawned by the CLI inherit the `agentcli` UID, so they can still operate. Any other background tasks (running as `agentuser`) must go through the helper’s Unix socket if they need read-only access (e.g., to tail logs).

**Why the CLI still runs as `agentcli`:** We treat the CLI front-end as a control plane that may read/write its private cache, but we no longer allow it (or its descendants) to execute arbitrary repo commands inside that namespace. The wrapper script performs these steps atomically:

1. `prepare-<agent>-secrets.sh` runs as root, wires tmpfs, and marks the mount tree `MS_PRIVATE|MS_UNBINDABLE` so it cannot be propagated to child namespaces.
2. It executes `unshare --mount --pid --fork --mount-proc -- setpriv --reuid agentcli --regid agentcli --init-groups --no-new-privs --reset-env /usr/local/bin/<agent>-cli-wrapper`.
3. The wrapper starts the CLI and replaces its traditional "spawn shell" logic with RPC calls to `/run/agent-task-runner.sock` (see below). The CLI process never `exec`s user commands directly, so it has no children that inherit the secret/data mounts.
4. The AppArmor profile for `agentcli` grants access only to `/run/agent-*/<agent>` and the CLI binary. Even if untrusted repo code tricks the CLI into running `!bash`, the connection is proxied, not executed locally, so the sandbox remains sealed.

#### Task Execution Without Data Access

Every time an agent CLI needs to run user-supplied code (e.g., `github-copilot-cli exec`, `codex exec`, `claude -p`), it now speaks to a dedicated `agent-task-runner` helper via a Unix domain socket:

1. CLI sends `{command, env, cwd}` JSON to the runner whenever it would have spawned a process—whether that's due to a `run/exec` subcommand invoked by a human or an automated tool invocation generated by the agent itself.
2. Runner validates the request, spawns a process as `agentuser` inside a fresh pid+mount namespace that **does not** include `/run/agent-data/<agent>` or `/run/agent-secrets/<agent>`.
3. Runner bind-mounts only `/workspace`, `/home/agentuser`, `/tmp`, and the network policy tmpfs required for the command. Because the sensitive mounts were marked unbindable/private in step 1, they cannot be re-shared into this namespace.
4. Runner applies `no_new_privs`, seccomp profile, and an AppArmor label (`coding-agents-task`) that explicitly denies access to `/run/agent-*` even if the process later attempts to mount or open those paths via `/proc/self/fd` tricks.
5. STDIN/STDOUT/STDERR of the spawned process are proxied back to the CLI over the socket, giving the CLI the illusion that it executed the command locally.

With this split, arbitrary subprocesses launched during a prompt run are **never** executed within the `agentcli` namespace, so they cannot observe or exfiltrate the agent data mount. Even if a prompt asks the agent to run `cat /run/agent-data/copilot/config.json`, the request goes through the runner and gets denied by both the mount topology (path not present) and AppArmor policy.

If an operator truly needs shell access with the same visibility as the CLI (for debugging the cache), we expose a gated `coding-agents with-agentcli <cmd>` helper that requires an override token plus MFA challenge before mapping the caller into the control-plane namespace. This keeps day-to-day workloads locked down while preserving a break-glass path.

##### How Existing CLIs Learn About the Runner

When we talk about an “agent” in this document we mean the upstream binaries provided by GitHub (Copilot CLI), OpenAI (Codex), and Anthropic (Claude). Those binaries remain untouched; we interpose using two layers:

1. **Binary shim (best effort path detection).** During image build we rename the real binary (e.g., `/usr/bin/github-copilot-cli` → `.real`) and install a wrapper that exports `AGENT_TASK_RUNNER_SOCKET` and reroutes any *explicit* subcommands (like `copilot exec`) through the socket. This covers the common cases we control.
2. **Seccomp exec interception (guaranteed enforcement).** Regardless of what the vendor binary tries to run, we apply a seccomp filter to the `agentcli` namespace that places `execve`, `execveat`, and `posix_spawn` behind a user-notification handler:
    - When the CLI (or any library it loads) issues an `execve`, the kernel pauses the call and notifies our host-side `agent-task-runnerd` via the seccomp user-notif FD.
    - The daemon inspects the request (argv/env/cwd pulled from the paused task’s memory), decides whether it is allowed, and if so launches the command itself inside the sandboxed `agentuser` namespace. The original `execve` never completes; instead we return `-EPERM` so the CLI understands it must consume the runner’s output (which we stream back through the socket).
    - Because the exec never succeeds inside the `agentcli` namespace, no new process with access to `/run/agent-data/<agent>` is created. The vendor binary simply reads STDOUT/STDERR from the socket the way it expects a child process to behave.

If the vendor adds new execution pathways that bypass our wrapper, the seccomp layer still intercepts them. This guarantees that every process launch—whether initiated manually or automatically by the agent’s own reasoning loop—flows through the hardened runner.

If the CLI needs to share artifacts with the general workspace (for example, download files for the repo), it should explicitly copy them into `/workspace` or `/home/agentuser`—the data tmpfs is not shared automatically.

#### Bi-Directional Sync Workflow

```mermaid
sequenceDiagram
    autonumber
    participant Host as Host Launcher
    participant Broker as Secret Broker
    participant Import as Data Import Helper
    participant CLI as Agent CLI (agentcli UID)
    participant Export as Data Export Helper

    Host->>Host: Collect whitelisted files (table above)
    Host->>Host: Create tar + manifest + HMAC
    Host->>Import: Drop tar inside /run/coding-agents/<agent>/data-import.tar
    Import->>CLI: Unpack tar into /run/agent-data/<agent>
    CLI->>CLI: Read/write within tmpfs
    CLI-->>Export: Exit triggers export helper
    Export->>Export: Filter files per whitelist, recompute manifest
    Export->>Host: Emit signed tar via /run/agent-data-export/<agent>
    Host->>Host: Validate signature + merge back into ~/.agent/
```

This approach lets us persist the useful artifacts (logs, history, saved sessions) while preventing arbitrary file writes back onto the host. It also guarantees that the same data the CLI expects is present every time without reopening the attack surface that came with raw bind mounts.
