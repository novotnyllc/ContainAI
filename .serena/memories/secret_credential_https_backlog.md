# Secret Credential HTTPS Backlog (Updated 2025-11-18)

## Epic 1 – Agent CLI Secret Import/Export
- **1.1 Detect Secrets – run-agent/launch-agent** – **Done**  
  `scripts/launchers/run-agent`, `scripts/launchers/launch-agent`, and their PowerShell counterparts hash Copilot/Codex/Claude credentials, call the broker via `store_stub_secrets`, and label capability bundles (`Stage-AgentCliCapabilityBundles`).
- **1.2 Capability Packaging – host tmpfs** – **Done**  \
  `scripts/launchers/{run,launch}-agent` and the PowerShell variants invoke `issue_session_capabilities` to drop sealed broker tokens under `$SESSION_CONFIG_OUTPUT/capabilities`, mirror them into `SESSION_CONFIG_OUTPUT/<agent>/cli/capabilities`, and then `docker cp` the tree into `/run/coding-agents` inside the container (tmpfs with `nosuid,nodev,noexec`). Per-agent manifests come from `write_agent_cli_manifest`, so helpers now redeem capabilities without touching host secret directories.

## Epic 2 – Agent Namespace & Exec Interception
- **2.1 UID Split – agentuser/agentcli** – **Done (2025-11-18)**  
  `docker/base/Dockerfile` now provisions an `agentcli` user and places `agentuser` in the `agentcli` group. `scripts/runtime/entrypoint.sh` mounts `/run/agent-secrets`, `/run/agent-data`, and `/run/agent-data-export` as tmpfs owned by `agentcli` with `nosuid,nodev,noexec,private,unbindable` semantics, stages agent data before the privilege drop, and ensures fallback directories stay `agentcli`-owned. Docs (`docs/architecture.md`, `docs/vscode-integration.md`) describe the split, and `scripts/test/integration-test-impl.sh` adds `test_agentcli_uid_split` to verify ownership and mount options.
- **2.2 Wrapper & Env – CLI wrappers** – **Done (2025-11-18)**  
  `docker/base/Dockerfile` now builds `/usr/local/bin/agentcli-exec` (setuid helper) and runs `scripts/runtime/install-agent-cli-wrappers.sh` to rewrite `github-copilot-cli`, `codex`, and `claude` into shims that export `AGENT_TASK_RUNNER_SOCKET`/helper metadata before invoking the preserved `.real` binary as `agentcli`. Documentation (`docs/architecture.md`, `docs/secret-credential-architecture.md`) explains the wrapper model, and `scripts/test/integration-test-impl.sh` adds `test_cli_wrappers` to assert the wrapper + helper are in place. This satisfies the env + privilege drop requirements pending future runner/seccomp integration.
- **2.3 Seccomp Exec Trap – agent-task-runnerd** – **Done (2025-11-18)**  
  The legacy C helpers are gone and `/usr/local/bin/agentcli-exec` + `/usr/local/bin/agent-task-runnerd` now come from the Rust crate in `scripts/runtime/agent-task-runner` (tests added in `src/lib.rs`). `docker/base/Dockerfile` compiles them via a dedicated cargo builder stage and installs the resulting binaries with the same ownership/permissions. Documentation in `docs/architecture.md` and `docs/secret-credential-architecture.md` calls out the safe-language implementation so the plan’s policy is enforced.
- **2.4 Runner Sandbox – namespace limits** – **Done (2025-11-18)**  
  `scripts/runtime/entrypoint.sh` now launches `agent-task-runnerd` before privileges drop so it can `unshare` and mount inside child namespaces. The sandbox binary (`scripts/runtime/agent-task-runner/src/agent_task_sandbox.rs`) remounts `/` private, replaces `/run/agent-secrets`, `/run/agent-data`, and `/run/agent-data-export` with sealed tmpfs (`mode 000`), enforces `PR_SET_NO_NEW_PRIVS`, and defaults to the `coding-agents-task` AppArmor profile. Behavior is documented in `docs/secret-credential-architecture.md`, and the helper has unit tests (`cargo test --bin agent-task-sandbox`).
- **2.5 CLI Integration – explicit exec/run** – **TODO**  
  Runner daemon already exposes `MSG_RUN_REQUEST` JSON handling and stdout/stderr streaming, but nothing in the wrappers or helpers speaks that protocol today. `agentcli-exec` only registers the seccomp listener and immediately `execvp`s the vendor binary, so exec mediation still relies solely on kernel traps. Work needed: client-side RPC shim that sends run requests over `AGENT_TASK_RUNNER_SOCKET`, updates to `install-agent-cli-wrappers.sh` to route explicit subcommands (e.g., `copilot exec`, `codex run`) through the shim, plus Rust/unit/integration tests covering the socket path.

## Epic 3 – MCP Stub & Helper Improvements – MCP Stub & Helper Improvements
- **3.1 Command MCP Stubs** – **TODO**  
  No per-MCP stub binaries or UID/AppArmor wiring exist beyond the legacy `scripts/runtime/mcp-stub.py`.
- **3.2 HTTPS/SSE Helper Proxies** – **TODO**  
  No localhost helper daemons or proxy scripts are present; HTTPS flows still rely on vendor CLIs directly.
- **3.3 Session Config Rewrites** – **TODO**  
  Session config generator (`scripts/runtime/setup-mcp-configs.sh`) does not rewrite transports to helper binaries.
- **3.4 Helper Lifecycle Hooks** – **TODO**  
  No helper processes emit audit events or health metrics; nothing cleans tmpfs artifacts.

## Epic 4 – TLS Trust & Certificates
- **4.1 Trust Store Strategy** – **TODO**  
  No code prepares curated bundles or copies certs into helper tmpfs directories.
- **4.2 Certificate/Public Key Pinning** – **TODO**  
  Configuration schema lacks pinning entries and helpers do not enforce TLS pins.
- **4.3 Trust Overrides Command** – **TODO**  
  There is no `coding-agents trust` command or supporting storage under `~/.config/coding-agents/trust-overrides/`.

## Epic 5 – Audit & Introspection Tooling
- **5.1 audit-agent Command (bash + PowerShell)** – **TODO**  
  No `audit-agent` script exists under `scripts/` (bash or PowerShell).
- **5.2 Launcher Structured Events** – **InProgress**  
  `scripts/utils/common-functions.{sh,ps1}` provide `log_security_event` plus session-config/capability override emitters, but helper lifecycle/audit events are not yet implemented.
- **5.3 Telemetry & Audit Verification** – **TODO**  
  There are no automated checks ensuring audit logs contain expected events.

## Epic 6 – Documentation & Troubleshooting
- **Status: TODO**  
  Docs (`docs/secret-credential-architecture.md`, `docs/security-workflows.md`, etc.) still describe the hardened design in future tense and do not match the partial implementation.

## Epic 7 – Testing & Validation
- **7.1 Unit/Integration Tests** – **TODO**  
  Existing suites (`scripts/test/test-launchers.{sh,ps1}`) lack coverage for secret packaging, capability redemption, tmpfs ownership, or exec interception.
- **7.2 CI Enforcement** – **TODO**  
  No automation enforces bash/PowerShell parity or analyzer runs for the new workflows beyond manual guidance in CONTRIBUTING.
- **7.3 Telemetry & Audit Verification** – **TODO**  
  There are no tests or CI steps verifying audit log contents for capability issuance, helper lifecycle, or TLS failures.
- **7.4 Split Prod from Test common helpers** – **TODO**  
  The common-functions contains test code that is copied into the runtime containers. Reduce attack surface area and factor better to split out functions that are only for testing into a separate file