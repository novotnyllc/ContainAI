# PRD: .NET 10 AOT-First DI Strategy and Architecture Decision

## Epic
- ID: `fn-52-net-10-aot-first-di-strategy-and`
- Title: `.NET 10 AOT-first DI Strategy and Architecture Decision`

## Problem Statement
ContainAI has made substantial structural refactors, but a final architecture decision is still missing for dependency wiring under NativeAOT constraints. We need an explicit, evidence-backed decision on whether the current `IServiceCollection` approach is acceptable as-is for .NET 10 NativeAOT, or whether a source-generated/container alternative should be adopted.

This decision must be made before further architectural consolidation to avoid churn, regressions, or AOT/trimming issues.

## Product Requirement
Define and execute an AOT-first DI decision workflow that:
1. Enforces **.NET 10+ coding standards only** for all related work.
2. Evaluates DI approaches with measurable AOT/trimming/runtime impact.
3. Produces a signed-off decision record and an implementation plan.

## Goals
1. Establish a single approved DI/composition approach for `src/cai` and related host/runtime paths.
2. Keep or improve NativeAOT publish reliability.
3. Keep or improve startup time and memory profile for CLI workloads.
4. Avoid reflection-heavy patterns that compromise trimming/AOT safety.

## Non-Goals
1. Rewriting the full codebase DI in this PRD phase.
2. Changing public CLI behavior.
3. Replacing `System.CommandLine` command surface modeling.

## Hard Constraints
1. **.NET 10 and later coding standards only.**
2. Preserve AOT/trimming safety and source-gen friendly patterns.
3. No ad-hoc runtime command discovery.
4. No parser executable regressions for config paths.
5. Guardrails remain enforced:
   - `dotnet build ContainAI.slnx -c Release -warnaserror`
   - `dotnet format analyzers --diagnostics IDE1006 --verify-no-changes`
   - `dotnet run --project src/cai -- manifest check src/manifests`

## Research Questions
1. Is the current `IServiceCollection` pattern sufficient for .NET 10 NativeAOT in this repo?
2. If yes, what restrictions/patterns are mandatory to keep it safe and performant?
3. If no, which alternative is best:
   - Source-generated DI approach
   - Compile-time composition root pattern
   - Hybrid approach (manual composition in hot paths + ServiceCollection elsewhere)
4. What are measurable tradeoffs in:
   - Publish success/trimming warnings
   - Binary size
   - Startup latency
   - Runtime allocations

## Candidate Approaches
1. **Baseline:** Keep `IServiceCollection` + strict usage rules.
2. **Source-generated DI:** Adopt a source-gen container/registration model.
3. **Manual composition root:** Replace dynamic registration with explicit wiring.
4. **Hybrid:** Manual composition for AOT-critical paths, ServiceCollection for non-critical paths.

## Evaluation Method
For each candidate, run:
1. `dotnet publish src/cai/cai.csproj -c Release -r linux-x64 -p:PublishAot=true -p:PublishTrimmed=true`
2. Capture warnings/errors and trimming diagnostics.
3. Measure binary size and cold-start timing.
4. Compare allocations for representative command paths.

## Acceptance Criteria
1. A written decision document exists under `docs/` or `.flow/specs/` and is linked from epic evidence.
2. Decision includes rationale, rejected alternatives, migration impact, and rollback strategy.
3. At least one reproducible benchmark/evidence artifact per candidate option.
4. Chosen approach passes all required quality gates.
5. Follow-up implementation tasks are created with explicit dependencies.

## Risks
1. Choosing a DI model that later introduces hidden trimming/AOT failures.
2. Over-optimizing startup at cost of maintainability.
3. Introducing parallel composition styles without clear boundaries.

## Mitigations
1. AOT publish must be a hard gate in decision phase.
2. Keep decision reversible via bounded migration tasks.
3. Define allowed/forbidden DI patterns in contributor docs.

## Deliverables
1. DI Decision Record (final recommendation + evidence).
2. Updated architecture guidance (coding standards + DI policy).
3. Task backlog for implementation phase.

## Proposed Task Breakdown
1. Research + baseline measurement.
2. Option spike(s) and comparative measurement.
3. Decision record + architecture policy updates.
4. Controlled implementation rollout plan.

## Rollout Plan
1. Phase 1: research and decision only.
2. Phase 2: low-risk adoption in one domain as pilot.
3. Phase 3: incremental migration with per-domain gates.

## Exit Criteria
Epic is complete when the DI strategy is selected, documented, evidence-backed, and decomposed into actionable implementation tasks with dependencies.
