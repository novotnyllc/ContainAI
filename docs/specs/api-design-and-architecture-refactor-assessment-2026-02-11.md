# API Design And Architecture Refactor Assessment (2026-02-11)

## Objective
Finish the runtime reorganization so the codebase is folder-first, namespace-coherent, SRP/OOP aligned, and compatible with .NET 10 API and AOT expectations.

## Baseline Status
- Current branch is build-green after rollback of the failed wide namespace sweep.
- Build command:
  - `dotnet build src/cai/cai.csproj -c Release -warnaserror /m:1 -nodeReuse:false -p:UseSharedCompilation=false`
- File-size problem is mostly solved.
  - Largest `src/cai` file is 120 LOC.
- Remaining architecture problem is fragmentation and partial sprawl.
  - `partial` declarations in `src/cai`: 380
  - Most fragmented roots:
    - `TomlCommandProcessor`: 45 files
    - `ContainAiDockerProxy`: 35 files
    - `SessionTargetResolver`: 32 files
    - `ContainerRuntimeCommandService`: 29 files

## Reviewed .NET Guidance (Primary Sources)
- Change rules for compatibility:
  - https://learn.microsoft.com/en-us/dotnet/core/compatibility/library-change-rules
- API compatibility tooling:
  - https://learn.microsoft.com/en-us/dotnet/fundamentals/apicompat/overview
- Library guidance and breaking changes:
  - https://learn.microsoft.com/en-us/dotnet/standard/library-guidance/
  - https://learn.microsoft.com/en-us/dotnet/standard/library-guidance/breaking-changes
- DI guidance:
  - https://learn.microsoft.com/en-us/dotnet/core/extensions/dependency-injection/guidelines
- Runtime coding guidelines and digest:
  - https://github.com/dotnet/runtime/blob/main/docs/coding-guidelines/coding-style.md
  - https://github.com/dotnet/runtime/blob/main/docs/coding-guidelines/framework-design-guidelines-digest.md
  - https://github.com/dotnet/runtime/blob/main/docs/coding-guidelines/breaking-change-rules.md

## Non-Negotiable Standards For Remaining Work
- .NET 10 coding style and analyzer-clean patterns only.
- Folder names must stay dot-free.
- Preserve public/externally consumed command/API signatures unless explicitly versioned.
- Avoid broad namespace sweeps; migrate by bounded domain with build verification after each slice.
- Reduce partial usage by extracting cohesive types (services, workflows, parsers, validators, models).
- Keep composition roots explicit; avoid service locator drift.
- DI and AOT:
  - `IServiceCollection` is allowed for this app shape.
  - Avoid reflection-driven activation patterns and dynamic runtime discovery in hot paths.
  - Prefer explicit registrations/factories and source-gen-friendly serialization paths where relevant.

## What Is Left

### 1. Toml Domain (Highest fragmentation)
Current issue:
- `TomlCommandProcessor` ecosystem is split into many partials with mixed concerns.

Remaining work:
- Consolidate each core type to single-file, non-partial implementations.
- Organize into focused folders:
  - `Toml/Contracts`, `Toml/Execution`, `Toml/IO`, `Toml/Parsing`, `Toml/Serialization`, `Toml/Validation`, `Toml/Update`, `Toml/Rules`
- Keep facade compatibility:
  - `ContainAI.Cli.Host.TomlCommandProcessor`
  - `ContainAI.Cli.Host.TomlCommandResult`

### 2. DockerProxy Domain
Current issue:
- One large orchestration concept split across many partial files.

Remaining work:
- Keep external facade stable (`ContainAiDockerProxy`).
- Extract cohesive internals by responsibility:
  - Workflow
  - Parsing
  - Feature settings
  - Ports
  - Execution
  - System side-effects
  - Models
- Preserve compatibility shims where existing internal call sites rely on legacy type names.

### 3. Sessions Resolution Domain
Current issue:
- `SessionTargetResolver` and docker lookup/validation flows have dependency hubs and constructor-level composition in domain services.

Remaining work:
- Split into domain-first folders:
  - `Sessions/Resolution/Orchestration`
  - `Sessions/Resolution/Workspace`
  - `Sessions/Resolution/Containers`
  - `Sessions/Resolution/Validation`
  - `Sessions/Resolution/Models`
- Move default constructor composition to clear composition root boundaries.
- Keep target resolution behavior stable.

### 4. ContainerRuntime Domain
Current issue:
- `ContainerRuntimeCommandService` mixes command mapping, workflow construction, and execution details across partials.

Remaining work:
- Reorganize into:
  - `ContainerRuntime/Commands`
  - `ContainerRuntime/Workflows`
  - `ContainerRuntime/Services`
  - `ContainerRuntime/Linking`
  - `ContainerRuntime/Configuration`
  - `ContainerRuntime/Infrastructure`
  - `ContainerRuntime/Models`
- Turn command service into a thin facade and delegate to explicit handlers/workflows.

## Execution Order (Risk-Controlled)
1. Toml domain consolidation and folderization.
2. ContainerRuntime extraction into commands/workflows/services/linking.
3. Sessions resolution decomposition.
4. DockerProxy decomposition.
5. Cross-domain namespace polish only after bounded migrations build cleanly.

## Gates Per Slice
- Build clean:
  - `dotnet build src/cai/cai.csproj -c Release -warnaserror`
- No unintended public API break in command surface.
- Dot-free folder naming.
- New code follows SRP boundaries with explicit constructor contracts.

## Definition Of Done
- Top fragmented roots (`TomlCommandProcessor`, `ContainAiDockerProxy`, `SessionTargetResolver`, `ContainerRuntimeCommandService`) are no longer multi-dozen partial clusters.
- Partial count is materially reduced and isolated to justified cases.
- Folder and namespace structure is coherent and domain-based.
- Build is green with analyzers and no regressions in command behavior.
