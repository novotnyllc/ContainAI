# Secret Credential HTTPS Backlog (Canonical – 2025-11-19)

## Epic 1 – Agent CLI Secret Import/Export
- **1.1 Detect Secrets – run-agent/launch-agent** — Status: **Done**
  - Bash launchers discover Copilot/Codex/Claude host creds, hash them, and register the new `agent_*` stubs before capability issuance (`scripts/launchers/run-agent`, lines 352-455; `scripts/launchers/launch-agent`, lines 242-330). PowerShell wrappers delegate through WSL, so both shells share the same logic.
- **1.2 Capability Packaging – host tmpfs** — Status: **Done**
  - `stage_agent_cli_capability_bundles` copies broker outputs into per-agent session tmpfs roots and emits manifests, while `issue_session_capabilities` drives `secret-broker.py` to mint sealed blobs (`scripts/launchers/run-agent`, lines 508-538; `scripts/utils/common-functions.sh`, lines 582-610).
- **1.3 Container Helpers – prepare-<agent>-secrets** — Status: **Done**
  - Container images ship dedicated helpers that redeem capabilities via `/usr/local/bin/capability-unseal`, write configs under `/run/agent-secrets/<agent>`, and symlink CLI caches back to tmpfs (`docker/agents/copilot/prepare-copilot-secrets.sh`, `docker/agents/codex/prepare-codex-secrets.sh`, `docker/agents/claude/prepare-claude-secrets.sh`). Launchers set `CODING_AGENTS_AGENT_CAP_ROOT`/`CODING_AGENTS_AGENT_SECRET_ROOT` when starting each container (`scripts/launchers/run-agent`, lines 1276-1290), and regression tests execute the helpers directly (`scripts/test/test-launchers.sh`, lines 780-970).
- **1.4 Data Import/Export – signed tarball flow** — Status: **Done**
  - `package-agent-data.py` records per-entry SHA256+HMAC during packaging and enforces the HMAC during merge (`scripts/utils/package-agent-data.py`). Host launchers call it for imports, and the container entrypoint validates and mounts `/run/agent-data/<agent>/<session>` tmpfs before launch (`scripts/runtime/entrypoint.sh`, lines 206-320). Shutdown exports reuse the same script and drop artifacts into `/run/agent-data-export` (`scripts/runtime/entrypoint.sh`, lines 324-370). Host-side `merge_agent_data_exports` also demands matching HMAC keys (`scripts/utils/common-functions.sh`, lines 1290-1375). Tests cover the packager + merge paths, including HMAC failure cases (`scripts/test/test-launchers.sh::test_agent_data_packager`).

## Epic 2 – Agent Namespace & Exec Interception
- **2.1 UID Split – agentuser/agentcli & tmpfs** — Status: **Done**
  - Base images create `agentuser` and `agentcli`, assign ownership, and install setuid helpers (`docker/base/Dockerfile`, lines 213-244). The entrypoint mounts `/run/agent-{secrets,data,data-export}` as `nosuid,nodev,noexec,MS_PRIVATE|MS_UNBINDABLE` tmpfs owned by `agentcli` (`scripts/runtime/entrypoint.sh`, lines 40-110 & 417-422).
- **2.2 Wrapper & Env – CLI wrappers** — Status: **Done**
  - `/usr/local/bin/install-agent-cli-wrappers.sh` renames vendor binaries, exports runner socket/env vars, and drops privileges via `agentcli-exec` before invoking the real CLI (`scripts/runtime/install-agent-cli-wrappers.sh`). Integration tests confirm the wrappers reference `agentcli-exec`, set `AGENT_TASK_RUNNER_SOCKET`, and keep `.real` backups (`scripts/test/integration-test-impl.sh::test_cli_wrappers`).
- **2.3 Seccomp Exec Trap – agent-task-runnerd** — Status: **Done**
  - `agentcli-exec` installs a seccomp user-notification filter on `execve/execveat` and registers with `agent-task-runnerd`, which audits each notification before replaying or denying (`scripts/runtime/agent-task-runner/src/agentcli_exec.rs`, lines 60-140; `scripts/runtime/agent-task-runner/src/agent_task_runnerd.rs`, seccomp handling around lines 50-420). Tests verify intercepted launches generate `events.log` entries (`scripts/test/integration-test-impl.sh::test_agent_task_runner_seccomp`).
- **2.4 Runner Sandbox – namespace/AppArmor** — Status: **Done**
  - `agent_task_sandbox.rs` remounts `/` private, masks `/run/agent-{secrets,data,data-export}` with 000 tmpfs, enforces `PR_SET_NO_NEW_PRIVS`, drops capabilities, and wraps commands in the `coding-agents-task` AppArmor profile when available. Unit tests assert the default hide paths and deduping logic (`scripts/runtime/agent-task-runner/src/agent_task_sandbox.rs`).
- **2.5 CLI Integration – explicit exec/run** — Status: **Done**
  - Wrappers route `exec|run|shell` subcommands through `agent-task-runnerctl` even if seccomp cannot fire (macOS dev mode), before falling back to `agentcli-exec` for normal invocations (`scripts/runtime/install-agent-cli-wrappers.sh`). The integration test suite greps for the runnerctl hook to guard regressions (`scripts/test/integration-test-impl.sh::test_cli_wrappers`).

## Epic 3 – MCP Stub & Helper Improvements
- **3.1 Command MCPs – dedicated stub binaries/AppArmor** — Status: **TODO**
  - Only the legacy shared Python stub exists (`scripts/runtime/mcp-stub.py`); there are no per-MCP binaries, UIDs, or profiles under `scripts/runtime/` or `docker/agents/`.
- **3.2 HTTPS/SSE Helper Proxies** — Status: **TODO**
  - There are no helper daemons or launcher hooks that expose localhost sockets or redeem HTTPS/SSE capabilities; the `scripts/runtime` tree lacks any `https`/`sse` helper implementations, and generated configs still point directly to remote endpoints.
- **3.3 Session Config Rewrites** — Status: **TODO**
  - `scripts/runtime/setup-mcp-configs.sh` simply calls `scripts/utils/convert-toml-to-mcp.py`, which copies the TOML definitions verbatim into each agent’s `config.json` without rewriting transports to helper sockets or stub binaries.
- **3.4 Helper Lifecycle Hooks** — Status: **TODO**
  - With no helper processes, there are no audit log events, tmpfs cleanup routines, or health probes for MCP helpers in `scripts/utils/common-functions.sh` or the launchers.

## Epic 4 – TLS Trust & Certificates
- **4.1 Trust Store Strategy** — Status: **TODO**
  - No code mounts CA bundles into helper tmpfs or lets helpers choose curated trust stores; repo-wide searches for `trust-overrides` or helper CA handling only appear in docs/memories, not scripts.
- **4.2 Certificate/Public Key Pinning** — Status: **TODO**
  - Session configs (`scripts/utils/convert-toml-to-mcp.py`) have no schema for pins, and no runtime code enforces TLS pins for MCP HTTPS calls.
- **4.3 Trust Overrides Command** — Status: **TODO**
  - There is no `coding-agents trust add` CLI or supporting scripts under `scripts/` managing `~/.config/coding-agents/trust-overrides/`; only documentation references exist.

## Epic 5 – Audit & Introspection Tooling
- **5.1 `audit-agent` Command (bash + PowerShell)** — Status: **TODO**
  - The `scripts/launchers/` directory contains only run/list/connect/remove commands; no `audit-agent` bash or PowerShell entrypoint exists despite docs describing it.
- **5.2 Launcher Events – structured logging** — Status: **InProgress**
  - Launchers already log `session-config`, `capabilities-issued`, and `override-used` via `log_security_event` (`scripts/utils/common-functions.sh`, lines 269-360; `scripts/launchers/run-agent`, lines 1080-1105), but there are no helper lifecycle or `audit-agent` events because those components are still absent.

## Epic 6 – Documentation & Troubleshooting
- **6.1 Documentation Updates (architecture + flows)** — Status: **InProgress**
  - Files such as `docs/secret-credential-architecture.md` describe HTTPS helper proxies and an `audit-agent` command (lines 140-260, 346-410), yet those features are not implemented, so the documentation is aspirational rather than an accurate operator guide.
- **6.2 Operator Runbooks (helpers, trust, audit)** — Status: **TODO**
  - There are no runbook sections covering helper log inspection, endpoint substitution validation, TLS pin workflows, or audit tarball handling (`grep -R "runbook" docs/` returns no matches), so operators lack the promised guidance.

## Epic 7 – Testing & Validation
- **7.1 Unit/Integration Coverage** — Status: **InProgress**
  - Existing suites cover packager HMAC enforcement, CLI helpers, and exec interception (`scripts/test/test-launchers.sh::test_agent_data_packager`, `test_codex_cli_helper`, `test_claude_cli_helper`; `scripts/test/integration-test-impl.sh::test_agent_task_runner_seccomp`), but there are no tests for HTTPS helper flows, TLS pin mismatches, or audit-agent output because those features do not exist yet.
- **7.2 CI Enforcement (parity + analyzers)** — Status: **TODO**
  - `.github/workflows/test-launchers.yml` runs bash/PowerShell launcher tests and integration jobs but never invokes shellcheck, PSScriptAnalyzer, or helper-specific checks, so parity/analyzer enforcement remains manual.
- **7.3 Telemetry Verification** — Status: **TODO**
  - Apart from the narrow `test_audit_logging_pipeline` function that directly calls `log_security_event` (`scripts/test/test-launchers.sh`, lines 360-420), there are no automated checks ensuring real launches emit the required audit events (capabilities, helper lifecycle, audit-agent).
