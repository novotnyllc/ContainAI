## Plan: Convert Runtime `cai` Bash CLI to `.NET 10` NativeAOT Single Binary with Integrated ACP

### Summary
Migrate all **non-installer client-side runtime shell code** (`src/containai.sh` + `src/lib/*.sh`) into a well-factored `.NET 10` CLI that publishes as one native, trimmed binary: `cai`.
Refactor existing `acp-proxy` command surface into `System.CommandLine` under `cai acp proxy ...` and preserve full functional capability (including undocumented runtime behavior currently embodied in shell/tests).
Migrate tests to xUnit v3 (unit + ACP + key integration).
Execution model uses orchestrator-led parallel subagents in separate worktrees, with mandatory review-agent passes and completion gates.
**This plan is completion-bound: work keeps going until all acceptance gates are met.**

### Scope, Boundaries, and Decisions
1. In scope:
   Runtime command behavior currently in `src/containai.sh` and `src/lib/*.sh`.
2. Out of scope (this phase):
   Installer/build shell systems (`install.sh`, `src/build.sh`, packaging scripts), except minimal consumption updates for new `cai` binary paths when needed.
3. Compatibility posture:
   **Clean break in command UX is allowed**, but **capability parity is required**.
4. Must follow CLI design guildlines from https://clig.dev
5. Native publish targets required now:
   Linux + macOS.
6. Test migration level:
   Port all unit + ACP + key integration flows to xUnit v3 now.

### Required Skill Usage (from AGENTS guidance)
Apply these skills explicitly during implementation and review:
1. `dotnet-project-structure`:
   Use modern solution/project structure and keep `.slnx`/central props/package hygiene.
2. `modern-csharp-coding-standards`:
   Enforce modern C# patterns, immutable option records, async correctness, cancellation discipline.
3. `dependency-injection-patterns`:
   Organize command/services via composable `IServiceCollection` extensions.
4. `api-design`:
   Keep internal/public command contracts stable and explicit.
5. `type-design-performance`:
   Use efficient type boundaries and avoid unnecessary allocations in hot CLI paths.
6. `csharp-concurrency-patterns`:
   ACP/session concurrency design for output serialization and request routing.
7. `testcontainers-integration-tests`:
   Docker-dependent integration test architecture in xUnit.
8. `dotnet-slopwatch` (quality gate after substantial changes):
   Detect shortcutting/regression-hiding patterns.
9. `crap-analysis` (quality gate after test migration):
   Detect high-risk complexity/coverage hotspots.

### Target Architecture
1. Projects:
   `src/ContainAI.Cli.Abstractions` (options/contracts/errors),
   `src/ContainAI.Cli` (application services/use-cases),
   `src/cai` (native host, `System.CommandLine` composition),
   retain `src/ContainAI.Acp` (protocol/session core),
   deprecate standalone `src/acp-proxy` executable role after merge.
2. Command model:
   Per command: `Options` + validation + handler + use-case service + adapter interfaces.
3. Infrastructure adapters:
   Docker, process execution, file system, terminal IO/prompts, config/env resolution, clock, path normalization.
4. AOT/trim safety:
   Source-generated JSON, no reflection-dependent command binding, trim warnings treated as blockers.
5. Binary outcome:
   One executable `cai` with integrated ACP subcommands.

### Command Surface to Implement in `System.CommandLine`
Root commands and subcommands:
1. `run`
2. `shell`
3. `exec`
4. `doctor` (+ `fix` targets)
5. `setup`
6. `validate`
7. `docker`
8. `import`
9. `export`
10. `sync`
11. `stop`
12. `status`
13. `gc`
14. `ssh` (`cleanup`)
15. `links` (`check`, `fix`)
16. `config` (`list/get/set/unset`)
17. `template` (`upgrade`)
18. `update`
19. `refresh`
20. `uninstall`
21. `completion`
22. `version`
23. `acp proxy <agent>`

### ACP Integration Plan
1. Move parser/entrypoint behavior from `src/acp-proxy/Program.cs` into `cai` command tree.
2. Keep `ContainAI.Acp` core session/protocol libraries; adapt `AgentSpawner` to invoke the new CLI path safely.
3. Preserve ACP requirements:
   NDJSON behavior, stdout purity, initialize/session lifecycle, multi-session routing, concurrency safety, graceful shutdown.
4. Remove runtime dependency on separate `acp-proxy` binary path in CLI behavior.

### Functional Migration Workstreams (for parallelization)
#### Stream A: CLI Kernel & Composition
1. Build root `System.CommandLine` graph, shared option primitives, DI bootstrap, command registration modules.
2. Owns command parsing/dispatch architecture and cross-command conventions.

#### Stream B: Runtime + Docker Core
1. Implement `run`, `shell`, `exec`, `docker`, `setup`, `validate`.
2. Own context resolution, container discovery/creation/start, execution pathways.

#### Stream C: Lifecycle/Data Commands
1. Implement `import`, `export`, `sync`, `stop`, `status`, `gc`, `ssh`, `links`, `config`, `template`, `update`, `refresh`, `uninstall`.
2. Own config precedence, workspace state behaviors, lifecycle safety prompts.

#### Stream D: ACP Merge
1. Integrate ACP command into root CLI.
2. Own ACP session wiring, process spawning adaptations, protocol-level parity.

#### Stream E: Test Migration (xUnit v3)
1. Port shell unit tests to C# unit tests.
2. Port ACP integration tests to xUnit.
3. Port key runtime integration scenarios with Docker-aware fixtures.

#### Stream F: Docs/CI/Release Wiring
1. Update contributor docs and command references.
2. Add/adjust CI pipelines for tests + NativeAOT publish matrix for Linux/macOS.
3. Minimal install/runtime docs updates for binary-based flow.

### Parallel Worktree/Agent Execution Design
1. Orchestrator agent responsibilities:
   Own integration branch, maintain parity checklist, assign streams, coordinate rebases, run final validation.
2. Worktree strategy:
   One independent git worktree per stream; no overlapping file ownership where possible.
3. Merge order:
   A first (foundation), B/C/D in parallel rebased on A, then E (test convergence), then F.
4. Review-agent requirement per stream PR:
   One correctness/regression reviewer + one architecture/factoring reviewer.
5. Merge target:
   All stream PRs merge into orchestrator integration branch first; only orchestrator merges to `main`.

### Behavior-Parity and Undocumented Feature Capture
1. Build a parity inventory from:
   `src/containai.sh`, all `src/lib/*.sh`, current help text, completion behavior, integration/unit tests, and CLI docs.
2. Mark each behavior as:
   `mandatory`, `intentional break`, or `deferred`.
3. Any undocumented behavior exercised by tests/codepaths is treated as mandatory unless explicitly reclassified.
4. Parity inventory is a hard gate for completion.

### Testing Plan (xUnit v3)
1. Add/expand test projects:
   `tests/ContainAI.Cli.UnitTests`,
   `tests/ContainAI.Cli.IntegrationTests`,
   existing `tests/ContainAI.Acp.Tests`.
2. Unit coverage:
   argument parsing, validation, option precedence, config/workspace resolution logic, docker command assembly.
3. ACP test coverage:
   framing, stdout purity, initialize/session lifecycle, routing and cleanup, multi-session concurrency.
4. Integration coverage:
   key end-to-end command flows for runtime-critical paths (`run/shell/exec/import/export/stop/status/gc/config/docker`).
5. Quality gates:
   slopwatch and CRAP/coverage analysis executed before integration-branch final merge.

### CI and Publish Gates
1. Build/test matrix:
   .NET build + xUnit v3 suites + ACP tests + key integration suites.
2. Native publish matrix:
   Linux + macOS NativeAOT trimmed binary artifacts for `cai`.
3. Failure policy:
   Any broken parity item, failing critical tests, or unresolved reviewer findings blocks merge.

### Important Changes to Interfaces/Types
1. `System.CommandLine`-based command definitions become canonical command interface source.
2. Shared options and resolution contracts move into strongly-typed abstractions (no shell global-state patterns).
3. ACP command becomes internal subcommand of `cai`; standalone proxy executable path is retired from runtime contract.
4. Error/result contracts become typed and testable (instead of implicit shell exit-path behavior).

### Assumptions and Defaults
1. Installer shell remains for now; runtime shell is replaced.
2. Command naming/flag cleanup is permitted if functionality remains.
3. Linux + macOS native artifacts are mandatory in this phase.
4. No backward-compat shell alias layer is required.

### Completion Criteria ("Keep Going Until")
Work continues until all are true:
1. One native `cai` binary fully handles runtime command set.
2. `cai acp proxy <agent>` fully replaces runtime ACP proxy path and passes ACP tests.
3. xUnit v3 migration is complete for unit + ACP + key integration suites.
4. Parity inventory is closed with no unapproved gaps.
5. Linux/macOS NativeAOT publish succeeds.
6. Required review-agent findings are resolved.
7. slopwatch and CRAP/coverage gates pass.
8. Orchestrator branch passes full validation and is merged to `main`.
