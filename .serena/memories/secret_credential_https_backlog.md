s# Secret Credential HTTPS Backlog (Updated 2025-11-19)

## Epic 1 – Agent CLI Secret Import/Export
- **1.1 Detect Secrets – run-agent/launch-agent** – **Done**  \
  `scripts/launchers/run-agent` and `run-agent.ps1` call `detect_{copilot,codex,claude}_cli_secret` before container launch, hashing each credential via `register_agent_cli_secret` so the broker stashes per-agent secrets.
- **1.2 Capability Packaging – host tmpfs** – **Done**  \
  `stage_agent_cli_capability_bundles` (bash/PowerShell) copies sealed broker capabilities plus manifests into `$SESSION_CONFIG_OUTPUT/<agent>/cli/capabilities` and the container mounts that tmpfs at `/run/coding-agents/<agent>/cli`.
- **1.3 Container Helpers** – **Done**  \
  Helpers `docker/agents/{copilot,codex,claude}/prepare-*-secrets.sh` redeem capabilities through `/usr/local/bin/capability-unseal`, write configs under `/run/agent-secrets/<agent>`, and symlink CLI state to tmpfs. `scripts/runtime/entrypoint.sh` wires `CODING_AGENTS_AGENT_CAP_ROOT`/`CODING_AGENTS_AGENT_SECRET_ROOT` before helper execution.
- **1.4 Data Import/Export** – **InProgress**  \
  The host packager (`scripts/utils/package-agent-data.py`) emits per-entry SHA256/HMAC and entrypoint imports/exports tarballs via `/run/agent-data/<agent>/<session>`; however, neither `install_host_agent_data` nor `merge_agent_data_exports` validates the HMAC (no `--hmac-key-file` / `--require-hmac` usage), so tamper detection is still missing and the round-trip lacks regression tests.

## Epic 2 – Agent Namespace & Exec Interception
- **2.1 UID Split – agentuser/agentcli** – **Done**  \
  `docker/base/Dockerfile` provisions `agentcli` and adds `agentuser` to the group, while `scripts/runtime/entrypoint.sh` mounts `/run/agent-{secrets,data,data-export}` as `agentcli`-owned tmpfs (`nosuid,nodev,noexec,private,unbindable`) before privilege drop.
- **2.2 Wrapper & Env – CLI wrappers** – **Done**  \
  `/usr/local/bin/install-agent-cli-wrappers.sh` renames the vendor binaries, exports `AGENT_TASK_RUNNER_SOCKET`, and invokes `agentcli-exec`. `scripts/test/integration-test-impl.sh:test_cli_wrappers` confirms the wrappers call `agentcli-exec` and set the socket env.
- **2.3 Seccomp Exec Trap – agent-task-runnerd** – **Done**  \
  The Rust daemon (`scripts/runtime/agent-task-runner/src/agent_task_runnerd.rs`) registers for seccomp user-notification events, logs allow/deny decisions to `/run/agent-task-runner/events.log`, and ships via the cargo builder stage in `docker/base/Dockerfile`.
- **2.4 Runner Sandbox – namespace limits** – **Done**  \
  `agent-task-sandbox` remounts `/` private, masks `/run/agent-*`, enforces `PR_SET_NO_NEW_PRIVS`, and applies the `coding-agents-task` AppArmor profile before spawning shells (`scripts/runtime/agent-task-runner/src/agent_task_sandbox.rs`; entrypoint lines 360–420).
- **2.5 CLI Integration – explicit exec/run** – **Done**  \
  Wrappers dispatch `exec|run|shell` via `/usr/local/bin/agent-task-runnerctl` before falling back to `agentcli-exec` (see `scripts/runtime/install-agent-cli-wrappers.sh`). Integration tests grep for `agent-task-runnerctl` to guarantee the RPC path is wired.

## Epic 3 – MCP Stub & Helper Improvements
- **3.1 Command MCP Stubs** – **TODO**  \
  Only the shared Python `scripts/runtime/mcp-stub.py` ships—no per-MCP binaries, UIDs, or AppArmor labels exist yet.
- **3.2 HTTPS/SSE Helper Proxies** – **TODO**  \
  The repo lacks localhost helper daemons; HTTPS/SSE MCP traffic still goes straight from agent containers to vendor endpoints.
- **3.3 Session Config Rewrites** – **TODO**  \
  `scripts/runtime/setup-mcp-configs.sh` keeps emitting original MCP URLs/commands. There is no manifest rewrite that swaps transports for helper sockets.
- **3.4 Helper Lifecycle Hooks** – **TODO**  \
  With no helpers, there are no lifecycle events, tmpfs cleanup routines, or structured logs.

## Epic 4 – TLS Trust & Certificates
- **4.1 Trust Store Strategy** – **TODO**  \
  No code copies CA bundles into helper tmpfs or lets helpers choose between host vs curated trust stores.
- **4.2 Certificate/Public Key Pinning** – **TODO**  \
  Session configs have no pinning schema and nothing enforces pins for MCP HTTPS endpoints.
- **4.3 Trust Overrides Command** – **TODO**  \
  Still missing the `coding-agents trust add` workflow and `~/.config/coding-agents/trust-overrides/` management.

## Epic 5 – Audit & Introspection Tooling
- **5.1 audit-agent Command (bash + PowerShell)** – **TODO**  \
  Documentation references `scripts/launchers/audit-agent`, but no bash or PowerShell implementation exists in the repo.
- **5.2 Launcher Structured Events** – **InProgress**  \
  `scripts/utils/common-functions.{sh,ps1}` log `session-config`, `capabilities-issued`, and `override-used`, yet there are no helper lifecycle events and nothing reports audit dumps.
- **5.3 Telemetry & Audit Verification** – **TODO**  \
  No automated tests or CI steps validate `security-events.log` or runner audit files.

## Epic 6 – Documentation & Troubleshooting
- **Status: InProgress**  \
  Docs such as `docs/secret-credential-architecture.md` describe HTTPS helper proxies and an `audit-agent` CLI as if they shipped, but those binaries/scripts are absent, so runbooks remain aspirational and need updates reflecting the actual state.

## Epic 7 – Testing & Validation
- **7.1 Unit/Integration Tests** – **InProgress**  \
  Launchers/tests now cover secrets (`test_codex_cli_helper`), packager (`test_agent_data_packager`), helper network isolation, and CLI wrappers, but there is zero coverage for HTTPS helper flows, TLS pinning, or the missing audit-agent command.
- **7.2 CI Enforcement** – **TODO**  \
  No automated job enforces bash/PowerShell parity or analyzer checks; guidance still relies on manual CONTRIBUTING steps.
- **7.3 Telemetry & Audit Verification** – **TODO**  \
  CI never inspects audit logs or runner events after a launch.
- **7.4 Split prod vs. test helpers** – **TODO**  \
  `scripts/utils/common-functions.{sh,ps1}` are still shared by runtime helpers and tests, so sensitive functions (e.g., `remove_container_with_sidecars`) continue to ship into containers instead of being isolated.
