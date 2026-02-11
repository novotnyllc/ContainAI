# ContainAI CLI Architecture Refactor Completion PRD

## Status
- Date: 2026-02-11
- Scope: `src/cai`
- Purpose: define remaining refactor work to reach a consistent .NET 10 codebase architecture (SRP/OOP, folder-based organization, clean contracts, AOT-aware composition).

## Why This PRD Exists
Current refactoring removed the largest monoliths, but important architectural debt remains:
- dotted file naming patterns (example: `DevcontainerFeatureRuntime.Init.LinkSpecLoader.cs`)
- pseudo-partial organization via file names instead of folders/types
- interface + implementation co-located in many files
- runtime support and feature modules still unevenly layered

This doc is the execution contract for finishing the cleanup.

## Current Baseline (Measured)
- Total C# files in `src/cai`: **583**
- Files with dotted basenames (excluding `.cs`): **97**
- Files containing both interface and class declarations (heuristic): **213**
- Files >=100 lines in `src/cai`: **0** (size issue mostly solved, architecture issue remains)

## Design Principles (Mandatory)
- .NET 10+ coding standards only.
- Follow .NET API design guidelines: clear contracts, stable naming, low surprise, extend-only compatibility.
- Prefer folder/type decomposition over pseudo-partial naming.
- Single responsibility per class.
- Separate contracts from concrete implementations unless trivial/private local helper.
- No dotted file basenames for hand-written source in `src/cai`.
- Keep behavior unchanged unless explicitly planned.

## Out of Scope
- Behavioral feature changes.
- CLI command surface changes.
- Public API breaking changes in `ContainAI.Cli.Abstractions`.

## Target End State
1. No dotted basenames in hand-written `src/cai` source files.
2. Feature modules organized by folder hierarchy, not filename suffix hacks.
3. Contracts and implementations split consistently.
4. Devcontainer, DockerProxy, ContainerRuntime, Sessions, RuntimeSupport each have explicit internal layering.
5. Builds clean with analyzers as errors; slopwatch clean.

## Workstreams

### WS1: Naming and File Layout Normalization (P0)
Goal: remove dotted basenames and pseudo-partial file conventions.

Primary targets:
- `src/cai/Devcontainer/*Runtime.*.cs`
- `src/cai/ContainerRuntime/ContainerRuntimeCommandService.*.cs`
- `src/cai/DockerProxy/ContainAiDockerProxy.*.cs`
- `src/cai/ShellProfile/ShellProfileIntegration.*.cs`
- `src/cai/Sessions/Resolution/*.*.cs`
- `src/cai/Toml/*.*.cs`
- `src/cai/Manifests/Toml/ManifestTomlParser.Models.*.cs`

Execution rule:
- Convert `Feature.Area.Operation.cs` into folder path + single class file.
- Example:
  - from `DevcontainerFeatureRuntime.Init.LinkSpecLoader.cs`
  - to `Devcontainer/Init/LinkSpecLoader/DevcontainerFeatureLinkSpecLoader.cs` (or equivalent clean path)

Acceptance criteria:
- `find src/cai -type f -name '*.cs' -printf '%f\n' | sed 's/\.cs$//' | awk 'index($0,".")>0'` returns 0 for hand-written files.

### WS2: Contract/Implementation Separation (P0)
Goal: stop mixing interfaces and implementation classes in one file by default.

Current baseline:
- 213 mixed files (heuristic).

Execution rule:
- Move interfaces to `I*.cs` in same feature folder.
- Keep mixed only when:
  - private nested helper type, or
  - source-generator context pattern, or
  - tiny adapter where separation adds no clarity.

Acceptance criteria:
- Mixed files reduced to approved exceptions list only.
- Exceptions documented in `docs/architecture/refactor-exceptions.md`.

### WS3: Feature Module Layering Cleanup (P0/P1)
Goal: enforce consistent layering per domain.

Required module shape:
- `Contracts/`
- `Models/`
- `Services/`
- `Orchestration/` (if needed)
- `Infrastructure/` (IO/process/docker adapters)

Priority modules:
1. Devcontainer (P0)
2. ContainerRuntime (P0)
3. DockerProxy (P0)
4. Sessions (P1)
5. RuntimeSupport utilities consumed across modules (P1)

Acceptance criteria:
- Cross-module dependencies point inward to contracts, not across random concrete classes.
- No command/service class directly newing deep infrastructure chains without a dedicated factory/composition root.

### WS4: AOT-Friendly Composition and DI Strategy (P0 research, P1 implementation)
Goal: verify current composition model is correct for NativeAOT and trim safety.

Research tasks:
1. Evaluate if current manual composition roots are sufficient for AOT (likely yes).
2. Evaluate optional source-generated DI approach for selected modules.
3. Decide policy: manual composition vs generated DI, with rationale and constraints.

Deliverable:
- `specs/cai-aot-composition-decision-record.md` containing:
  - options considered
  - tradeoffs
  - final decision
  - migration plan (if any)

Implementation constraints:
- no reflection-heavy service discovery.
- preserve trim/AOT compatibility.

### WS5: Verification and Quality Gates (P0)
Required for every refactor batch:
- `dotnet build src/cai/cai.csproj -c Release -warnaserror`
- `dotnet tool run slopwatch analyze -d . --fail-on warning`
- targeted tests for touched behavior areas

Final completion gates:
- no dotted basenames (hand-written files)
- no unresolved architecture exception items
- build + slopwatch pass
- PR notes include module-by-module migration summary

## Execution Plan (Order)
1. Devcontainer rename/restructure (largest visible debt; user pain point).
2. ContainerRuntime and DockerProxy naming cleanup.
3. ShellProfile + Sessions + Toml naming normalization.
4. Contract/implementation split sweep.
5. AOT composition decision record and any agreed implementation changes.
6. Final validation sweep and docs update.

## Risks
- Large rename sets can break internal references and tests.
- Analyzer rule churn during broad moves.
- Accidental behavior drift in startup/composition paths.

Mitigations:
- small commits per module
- compile and slopwatch on each batch
- keep behavior-preserving refactors only

## Definition of Done
All of the following are true:
1. No dotted basenames remain in hand-written `src/cai` files.
2. Mixed interface/class files are either split or explicitly documented as exceptions.
3. Module folders reflect stable architecture boundaries.
4. AOT composition decision record is complete and approved.
5. Build/analyzer/slopwatch gates pass on final branch.
