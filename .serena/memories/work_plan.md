# Work Plan

## Open Work

### Epic 0 – Host/Container Split & Dogfooding Readiness
- **0.1 Host vs container script boundary** – Restructure the repo so host launchers/utilities live under a dedicated tree (e.g., `host/` or `scripts/host/`) while container-only helpers/stubs live under `docker/` or image contexts. Update build/test tooling to consume the new layout so the split is obvious to contributors. Dependencies: feeds Epics 3, 5, 8.
- **0.2 Dev/Prod entrypoints** – Provide parallel host entrypoints (`dev` vs `prod`) that run tests/debug flows directly from the repo while preparing the prod bundle for release. Ensure Dev paths keep today’s editable workflow, Prod paths source files from the new host tree, and both share test coverage. Dependencies: 0.1, informs 8.3–8.5.
- **0.3 Dogfooding readiness** – Once the split is in place, add scripts/docs for maintainers to install the “Prod” layout locally (integrity enforced) while still iterating via the dev tree. Include smoke tests that validate both modes. Dependencies: 0.2, feeds 6.x and 7.x.
- **0.4 Build automation** – Add build scripts (bash + PowerShell) and GitHub Actions pipelines that package the host tree, build agent images, and push artifacts to GHCR using the new layout. Include dry-run steps for dev mode so we can iterate before publishing. Dependencies: 0.1–0.2, informs Epic 8.
- **0.5 GHCR/secrets documentation** – Author a doc under `docs/` detailing how to configure GHCR repositories, GitHub Actions secrets, and required PAT/oidc permissions so contributors can reproduce releases. Dependencies: 0.4, feeds 6.1 and 6.2.

### Epic 3 – MCP Stub & Helper Improvements
- **3.1 Command MCP stubs** – Build dedicated stub binaries per MCP with unique UIDs, sandbox policies, and tmpfs cleanup so vendor agents never call the legacy shared `mcp-stub.py`. Dependencies: none.
- **3.2 HTTPS/SSE helper proxies** – Implement helper daemons plus launcher hooks that redeem HTTPS/SSE capabilities, expose localhost sockets, and enforce outbound network rules. Dependencies: none (feeds 4.x and 5.x).
- **3.3 Session config rewrites** – Extend `setup-mcp-configs.sh` and `convert-toml-to-mcp.py` to rewrite transports so configs point to the new stubs/helpers instead of remote endpoints. Dependencies: 3.1 and 3.2.
- **3.4 Helper lifecycle hooks** – Add audit events, tmpfs cleanup, health probes, and shutdown routines for every helper process in the launchers and `common-functions.sh`. Dependencies: 3.1–3.3 (feeds 5.2 and 7.3).

### Epic 4 – TLS Trust & Certificates
- **4.1 Trust store strategy** – Mount curated CA bundles inside helper tmpfs roots and let each helper pick the correct trust domain. Dependencies: 3.2.
- **4.2 Certificate/Public key pinning** – Add schema + enforcement so MCP HTTPS calls honor pins defined in configs; fail closed on mismatch. Dependencies: 3.3 and 4.1.
- **4.3 Trust overrides command** – Ship `coding-agents trust add/remove/list` tooling that manages `~/.config/coding-agents/trust-overrides/` and integrates with helpers. Dependencies: 4.1–4.2.

### Epic 5 – Audit & Introspection Tooling
- **5.1 `audit-agent` command** – Provide bash + PowerShell entrypoints that gather manifests, capabilities, mounts, helper state, and optional secrets into a signed report. Dependencies: 3.4, 4.x, and 8.x data paths.
- **5.2 Launcher events** – Expand `log_security_event` usage so launches emit helper lifecycle, integrity-check, env-detect, Podman-block, and audit-agent events. Dependencies: 3.4, 8.4–8.5, and 5.1.

### Epic 6 – Documentation & Troubleshooting
- **6.1 Documentation refresh** – Update `docs/secret-credential-architecture.md` and related guides to describe the implemented helper, trust, audit, integrity, and shim flows with current commands. Dependencies: 3–5 and 8 as features land.
- **6.2 Operator runbooks** – Publish runbooks that cover helper log inspection, endpoint substitution validation, TLS pin workflows, audit tarball handling, and health-check remediation steps. Dependencies: 3–5, 8, and 5.1.

### Epic 7 – Testing & Validation
- **7.1 Unit/integration coverage** – Add tests for HTTPS helpers, TLS pin mismatches, env-detect and integrity-check scripts, enhanced check-health behavior, and Windows shim delegation paths. Dependencies: 3–5 and 8 deliverables.
- **7.2 CI enforcement** – Update `.github/workflows/test-launchers.yml` to run shellcheck, PSScriptAnalyzer, and helper-specific linters so regressions fail the build. Dependencies: none.
- **7.3 Telemetry verification** – Create tests that launch agents end-to-end and assert all required audit events (capabilities, helper lifecycle, Podman blocks, integrity failures, audit-agent runs) are emitted. Dependencies: 3.4, 5.2, 8.4–8.5.

### Epic 8 – Distribution, Installation & Verification
- **8.1 Dual-artifact integrity model** – Add CI steps that run `syft`, emit CycloneDX `sbom.json`, compute canonical `SHA256SUMS`, and bundle both into `coding-agents.tar.gz` for installers. Dependencies: none (feeds 8.2 & 8.5).
- **8.2 Signed tarball & hardcoded SHA** – Sign the release tarball with Sigstore/OIDC, publish `SHA256SUMS`, and bake the tarball hash into installers for offline verification. Dependencies: 8.1.
- **8.3 Immutable system install + blue/green** – Enforce installs under system-owned roots with versioned directories and blue/green swaps, rejecting user-writable paths. Dependencies: 8.1–8.2.
- **8.4 Env-detect script** – Deliver `host/utils/env-detect.sh` that selects Prod vs Dev profiles based on install state and exposes the right config roots. Dependencies: 8.3 and 8.1.
- **8.5 Integrity-check script** – Run `sha256sum -c SHA256SUMS` before launches in Prod mode, aborting and logging on mismatch while allowing warnings in Dev. Dependencies: 8.1 and 8.4.
- **8.6 Health-check/Doctor** – Finish `scripts/utils/check-health.sh` so it blocks Podman, validates AppArmor/WSL posture, verifies Sigstore signatures, and integrates with launcher UX/docs. Dependencies: 8.3, 8.5, and 6.x documentation work.
- **8.8 Enforcement policies** – Ensure launchers/installers require system scope, block unsupported runtimes, rely only on `sha256sum`, and emit audit events when policies trigger. Dependencies: 8.3, 8.5, 7.3.

### Epic 9 – Network Security Hardening
- **9.1 Harden docker proxy rules** (Status: Done) – Update `docker/proxy/squid.conf` (and related Docker proxy settings) to block access to cloud metadata endpoints (169.254.169.254, 169.254.0.0/16) and private RFC1918 ranges (10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16) while keeping required MCP/package-manager traffic functional. Files: docker/proxy/squid.conf; scripts/test/integration-test-impl.sh; scripts/test/README.md. Tests: integration-test.sh::test_squid_proxy_hardening (added); lint: shellcheck docker/proxy/entrypoint.sh scripts/test/integration-test-impl.sh.
- **9.2 Enforce proxy rate limits** – Add squid/dnsmasq rules that cap request payloads at 10 MB and responses at 100 MB, returning clear errors when limits trigger. Tie the limits into telemetry so launches log violations. Dependencies: 9.1, feeds 5.2/7.3.

## Completed Work (For Reference)
- **Epic 1 – Agent CLI Secret Import/Export**: Secret discovery, capability packaging, container helpers, and data import/export flow are implemented with regression tests.
- **Epic 2 – Agent Namespace & Exec Interception**: UID split, CLI wrappers, seccomp interception, sandboxing, and explicit exec/run integration all ship with tests.
- **Epic 8.7 – Windows WSL shim launcher**: PowerShell launchers now delegate through `scripts/utils/wsl-shim.ps1`, keeping Windows shells thin and forwarding exit codes to the Bash launchers.
