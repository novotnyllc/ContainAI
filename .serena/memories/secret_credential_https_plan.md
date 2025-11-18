# End-to-End Secret Credential Hardening Plan

This plan captures every implementation work stream required to deliver the documented design across agent CLI secrets, data synchronization, MCP helpers, auditing, and launcher/broker changes. Each item below should be treated as a trackable epic.

1. **Agent CLI Secret Import/Export**
   - [Detect Secrets] Extend both `run-agent` and `launch-agent` (bash + PowerShell) to locate Copilot (`~/.copilot/config.json`), Codex (`~/.codex/auth.json`), and Claude (`~/.claude/.credentials.json` or `CLAUDE_API_KEY`) credentials on the *host*, hash/input-validate them, and request per-agent capability bundles from `secret-broker.py` (new stub IDs: `agent_copilot_cli`, `agent_codex_cli`, `agent_claude_cli`).
   - [Capability Packaging] Write sealed capability blobs + manifest metadata to `/run/coding-agents/<agent>/<session>.cap` tmpfs directories, ensuring ownership matches the future helper UID and nothing is bind-mounted from the host secrets directory.
   - [Container Helpers] Replace the legacy `init-*` scripts with `prepare-<agent>-secrets` helpers that redeem capabilities, materialize configs under `/run/agent-secrets/<agent>` with `chmod 600`, and populate the CLI cache in `/home/agentuser/.<agent>/` entirely from tmpfs.
   - [Data Import/Export] Implement host-side tarball packaging for non-secret agent data (logs, sessions, histories) with per-entry SHA256 + HMAC. Mount `/run/agent-data/<agent>/<session>` tmpfs in containers (unique per agent + session) to avoid collisions, unpack on launch, then re-pack/export on shutdown to `/run/agent-data-export/<agent>/<session>.tar`. Paths with inherent unique IDs (e.g., files or directories containing `session-`, `run-`, or UUID-like segments) can replace their host counterparts wholesale, while singular rolling files (command history, log streams without IDs) must be replayed/merged sequentially so concurrent sessions append without clobbering shared state.

2. **Agent Namespace & Exec Interception**
   - [UID Split] Introduce distinct Unix identities: `agentuser` for shell/workspace operations and `agentcli` for the vendor CLI. Ensure `/run/agent-secrets/*` and `/run/agent-data/*` are owned by `agentcli` and mounted `nosuid,nodev,noexec,MS_PRIVATE|MS_UNBINDABLE`.
   - [Wrapper & Env] Install CLI wrapper scripts that set `AGENT_TASK_RUNNER_SOCKET`, export helper locations, and drop privileges to `agentcli` before launching the upstream binary.
   - [Seccomp Exec Trap] Apply a seccomp user-notification filter to the `agentcli` namespace that traps `execve/execveat/posix_spawn`. Build the `agent-task-runnerd` daemon that receives notifications, inspects argv/env/cwd, and either denies or replays the command inside a fresh sandbox as `agentuser`.
   - [Runner Sandbox] Implement the runner (Unix socket protocol) that spawns commands via `setpriv --reuid agentuser --regid agentuser --no-new-privs`, `unshare --pid --mount --fork`, attaches AppArmor profile `coding-agents-task`, and ensures the namespace contains only `/workspace`, `/home/agentuser`, `/tmp`, and policy tmpfs.
   - [CLI Integration] Update CLI wrappers to route explicit `exec/run` subcommands directly over the runner socket for best-effort behavior even without seccomp notification (e.g., macOS dev mode).

3. **MCP Stub & Helper Improvements**
   - [Command MCPs] Finalize per-MCP stub binaries with dedicated UIDs/AppArmor labels, tmpfs management, and broker capability redemption. Ensure STDIO bridging, network allow-lists, and audit logging match the doc.
   - [HTTPS/SSE Helpers] Implement helper proxies (either in-container or host-side) that expose localhost TCP/Unix sockets. They must redeem capabilities, rewrite headers (Auth, custom vendor metadata), manage SSE fan-out, enforce rate limits, and forward to the remote MCP endpoints.
   - [Config Rewrites] Extend the session config generator to transform MCP entries:
       * `command` transports -> stub executable path + required args (`--cap-path`, `--session-id`, etc.).
       * `https`/`sse` transports -> localhost helper endpoint + helper metadata (socket path, headers, SSE mode, expected content-types).
   - [Lifecycle Hooks] Ensure helpers register with the audit log, clean tmpfs on exit, and surface health metrics for troubleshooting.

4. **TLS Trust & Certificates**
   - [Trust Store] Decide whether helpers use the host CA bundle (bind-mounted read-only) or a curated bundle per MCP. Copy required certs into helper tmpfs before launch.
   - [Pinning] Provide config schema for optional certificate/public key pinning per MCP. Helpers should fail closed if pins mismatch and emit audit events.
   - [Overrides] Implement `coding-agents trust add <mcp> <cert>` workflow (host-side) that writes override certs + justification to `~/.config/coding-agents/trust-overrides/` and logs usage.

5. **Audit & Introspection Tooling**
   - [audit-agent Command] Build `scripts/launchers/audit-agent` (bash + PowerShell parity) to collect:
       * Host configs (`config.toml`, agent configs) + hashes.
       * Generated artifacts from container tmpfs (session configs, manifests).
       * Capability metadata + files (redacted by default, Base64 with `--include-secrets`).
       * User/passwd entries, mount tables, running processes, seccomp/AppArmor labels.
       * Network/proxy settings, helper socket endpoints.
     Package everything into `audit-agent-<session>/` directory, write `manifest.json` with hash/owner/redaction metadata, tar+gzip, and sign. Emit audit log entry noting whether secrets were included.
   - [Launcher Events] Ensure launchers log `session-config`, `capabilities-issued`, `override-used`, helper launch/exit, and audit requests with structured JSON.

6. **Documentation + Troubleshooting**
   - Update **all** relevant Markdown files (`docs/secret-credential-architecture.md`, `docs/architecture.md`, `docs/mcp-setup.md`, `docs/usage/*`, troubleshooting guides) to reflect:
       * Agent secret import/export flow + data sync isolation.
       * `agentcli` namespace, task runner, exec interception behavior.
       * Command vs HTTPS/SSE MCP handling (including helper proxies, header rewriting, SSE specifics, TLS trust).
       * `audit-agent` usage and interpretation.
   - Provide operator-facing runbooks for: inspecting helper logs, verifying substituted endpoints, validating certificates/pins, using `audit-agent` tarballs, and rotating secrets.

7. **Testing & Validation**
   - [Unit/Integration] Add tests that cover secret packaging, capability redemption (success/failure), helper launches, SSE stream forwarding, TLS pin mismatches, exec interception enforcement, and audit-agent output validation.
   - [CI Enforcement] Ensure bash + PowerShell launchers remain feature-aligned, PSScriptAnalyzer and shellcheck remain clean, and new tests run inside existing integration harnesses (including the Docker-in-Docker flow described in docs).
   - [Telemetry Verification] Add automated checks that audit logs contain the expected events when capabilities are issued, helpers launched, or audit-agent is run.

This plan should be referenced whenever implementing or reviewing the secret credential isolation work so new contributors have a complete roadmap without needing prior conversation context.
