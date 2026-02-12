# ADR: AOT Composition Strategy for ContainAI CLI

## Status

**Accepted** -- 2026-02-12

## Context

The ContainAI CLI (`src/cai`) is a NativeAOT-published .NET 10 application that uses manual object composition (pure `new` wiring) with no dependency injection container. The project enables `PublishAot=true`, `PublishTrimmed=true`, `TrimMode=link`, `EnableTrimAnalyzer=true`, and aggressively strips runtime features (`DebuggerSupport=false`, `StackTraceSupport=false`, `InvariantGlobalization=true`).

As the codebase grows through architecture refactoring (fn-53), we need a documented decision on whether to keep manual composition or adopt a source-generated DI framework.

### Current composition pattern

The codebase uses a **dual-constructor pattern** across service classes:

1. A `public` constructor that calls `new` on concrete dependencies (used at runtime and for simple test scenarios).
2. An `internal` constructor that accepts interfaces (used for testing with fakes/mocks).

Examples of this pattern:

- `ContainerRuntimeCommandService`: public ctor creates `ManifestTomlParser` + `ContainerRuntimeOptionParser` via `new`, internal ctor accepts `IManifestTomlParser` + `IContainerRuntimeOptionParser`.
- `CaiCommandRuntime`: public ctor chains through overloads ending at an `internal` ctor accepting `AcpProxyRunner` + `IManifestTomlParser`.
- `CaiOperationsService`, `CaiConfigManifestService`, `CaiImportService`: each follows the same public/internal constructor split.

There are four composition roots:

| Root | Location | Responsibility |
|------|----------|---------------|
| Program.cs (top-level) | `src/cai/Program.cs` | Entry point; creates `ManifestTomlParser`, `AgentShimDispatcher`, `CaiCommandRuntime` |
| CaiCommandRuntimeHandlersFactory | `src/cai/CommandRuntime/Factory/CaiCommandRuntimeHandlersFactory.cs` | Central factory creating all command handlers from injected `AcpProxyRunner` + `IManifestTomlParser` |
| ContainerRuntimeCommandService | `src/cai/ContainerRuntime/ContainerRuntimeCommandService.cs` | Builds `ContainerRuntimeExecutionContext`, workflows, and handlers for container runtime commands |
| ContainAiDockerProxy | `src/cai/DockerProxy/ContainAiDockerProxy.cs` | Static factory methods wiring the DockerProxy subsystem |

### Cross-module concrete instantiation

`ManifestTomlParser` is instantiated via `new ManifestTomlParser()` in 9 locations across 8 files:

| File | Context |
|------|---------|
| `Program.cs` | Top-level entry, passed to `CaiCommandRuntime` and `AgentShimDispatcher` |
| `CaiCommandRuntime.cs` | Two public constructor overloads (lines 12, 20) |
| `ContainerRuntimeCommandService.cs` | Public constructor (line 18) |
| `CaiOperationsService.cs` | Public constructor (line 8) |
| `CaiConfigManifestService.cs` | Public constructor (line 13) |
| `CaiImportService.cs` | Public constructor (line 13) |
| `CaiImportOrchestrationOperations.cs` | Public constructor (line 15) |
| `ManifestGenerators.cs` | Static convenience overload (line 9) |

Of the 9 sites, 8 follow the dual-constructor pattern: the `new ManifestTomlParser()` call lives in a public convenience constructor that chains to an internal constructor accepting `IManifestTomlParser`. The ninth (`ManifestGenerators`) is a static convenience overload that chains to a method accepting `IManifestTomlParser`. The runtime entry path through `Program.cs` creates a single `ManifestTomlParser` instance and passes it to `CaiCommandRuntime`, which passes it to `CaiCommandRuntimeHandlersFactory.Create()`, which distributes it to all handlers. The other 8 instantiation sites are convenience constructors or static overloads primarily used for testing ergonomics and standalone invocations; some (e.g., `ContainerRuntimeCommandService`) may also serve as entry points for subsystem-scoped runtime paths.

## Options Considered

### Option 1: Keep manual composition (status quo)

Continue using explicit `new` wiring in composition roots and the dual-constructor pattern for testability.

**Advantages:**
- Zero runtime dependencies beyond the application itself.
- Zero reflection -- already fully AOT-safe and trim-safe. No trim analyzer warnings.
- Zero startup overhead from container initialization. CLI startup is already sub-millisecond for the composition phase.
- Complete transparency: every dependency is visible at the call site. No magic, no service locator, no hidden lifetime management.
- No additional NuGet packages to track, audit, or keep compatible with .NET version upgrades.
- No source generator build-time overhead or generated code to understand/debug.
- The dual-constructor pattern is well-established across the codebase (8+ service classes follow it consistently).
- Builds clean with `-warnaserror` and all trim/AOT analyzers enabled.

**Disadvantages:**
- `ManifestTomlParser` instantiated in 9 places (though 8 are in convenience constructors, not on the runtime hot path).
- Adding a new cross-cutting dependency requires touching multiple convenience constructors.
- No automatic lifetime management (singleton, scoped, transient). All lifetimes are implicit in where `new` is called.
- The dual-constructor pattern is a mild code smell: the public constructor "knows" the concrete types, even though the internal constructor uses interfaces.

### Option 2: Adopt Jab (compile-time DI source generator)

Replace manual composition with Jab, a C# source generator that produces DI container code at compile time.

**Advantages:**
- Source-generated: no reflection, AOT-safe, trim-safe.
- Benchmarked at ~200x faster startup than Microsoft.Extensions.DependencyInjection (MEDI).
- Supports constructor injection, factory methods, scoped/singleton/transient lifetimes.
- Centralizes wiring into a single `[ServiceProvider]`-annotated partial class.
- Would eliminate the dual-constructor pattern: all classes would have a single constructor accepting interfaces.

**Disadvantages:**
- Adds a NuGet dependency (`Jab`, currently v0.10.x -- still pre-1.0).
- Pre-1.0 maturity: limited community adoption compared to MEDI. Risk of breaking changes or abandonment.
- Source generator must be compatible with `TrimMode=link`, `PublishAot=true`, and the aggressive trimming flags in `cai.csproj`. Compatibility is likely but not guaranteed for all future .NET versions.
- Requires rewriting all composition roots and removing the dual-constructor pattern across 8+ service classes.
- Generated code may conflict with CsToml source generator (both run during compilation). Risk of ordering/interaction issues.
- For a CLI app with sub-millisecond composition, the 200x speedup over MEDI is irrelevant (MEDI is not in use).
- Limited documentation and tooling compared to MEDI ecosystem.
- The codebase has no `IServiceCollection` usage anywhere; adopting Jab introduces a new paradigm the team must learn.

### Option 3: Adopt Pure.DI (zero-runtime-dependency source generator)

Replace manual composition with Pure.DI, which generates code indistinguishable from hand-written `new` chains.

**Advantages:**
- Source-generated: no reflection, AOT-safe, trim-safe.
- Zero runtime dependencies: the generated code is plain constructor calls, equivalent to what we write manually today.
- Supports .NET Framework 2.0 through .NET 10+; broad platform compatibility.
- Would centralize wiring into a fluent `DI.Setup()` configuration.
- Active development (v2.3.x, regular releases).

**Disadvantages:**
- Adds a NuGet dependency (`Pure.DI`).
- Generated code is functionally equivalent to manual composition -- the primary benefit (centralized wiring) can be achieved with a manual factory pattern at lower risk.
- Requires rewriting all composition roots and removing the dual-constructor pattern.
- Fluent API has a learning curve and non-obvious error messages when wiring is misconfigured.
- Source generator interaction risk with CsToml generator (same concern as Jab).
- For a codebase with 4 composition roots and ~20 services, the framework overhead exceeds the wiring complexity it solves.

## Decision

**Keep manual composition (Option 1).**

### Rationale

1. **The composition is already AOT-safe.** The primary motivation for evaluating DI frameworks -- AOT/trim compatibility -- is a non-issue. The current manual wiring produces zero trim analyzer warnings and zero AOT compatibility warnings. There is nothing to fix.

2. **The codebase scale does not warrant a DI container.** The CLI has 4 composition roots creating approximately 20 service instances total. This is well within the range where manual wiring is clearer and more maintainable than a DI framework. DI containers provide value when there are hundreds of registrations, complex lifetime management, or runtime service resolution -- none of which apply here.

3. **Startup time is already optimal.** NativeAOT eliminates JIT, and manual composition has zero overhead beyond the constructor calls themselves. Neither Jab's 200x improvement over MEDI nor Pure.DI's zero-runtime claim provides a meaningful benefit when the baseline is already sub-millisecond.

4. **Risk vs. reward is unfavorable.** Adopting a source-generated DI framework introduces: a new NuGet dependency to maintain, potential source generator conflicts with CsToml, a new paradigm for the team to learn, and a multi-file rewrite of established composition patterns. The reward is marginal centralization of wiring that is already well-structured.

5. **The dual-constructor pattern is working.** While it is a mild code smell, it provides clear benefits: public constructors give a zero-configuration default for production and simple tests; internal constructors enable precise dependency substitution for unit tests. This pattern is consistent, well-understood, and self-documenting.

## Addressing the Dual-Constructor Pattern

The dual-constructor pattern should **continue** for the following reasons:

- **Testing flexibility:** Internal constructors accepting interfaces enable unit tests to substitute any dependency without reflection or mocking frameworks that are incompatible with AOT.
- **Production simplicity:** Public constructors provide sensible defaults for the runtime path, reducing ceremony in composition roots.
- **Explicit dependency visibility:** Each class declares its concrete defaults in the public constructor and its contract surface in the internal constructor. This makes dependency graphs easy to trace.

**Recommended evolution (not required now):**

If the number of convenience constructor instantiation sites for a single type (like `ManifestTomlParser`) grows beyond the current 9, consider consolidating by:

1. Removing convenience constructors from leaf services that are always created through `CaiCommandRuntimeHandlersFactory`.
2. Keeping convenience constructors only on true entry-point services (`ContainerRuntimeCommandService`, `CaiCommandRuntime`) that may be instantiated standalone.
3. Using a static factory method (e.g., `ManifestTomlParser.Default`) instead of scattering `new ManifestTomlParser()` across files, making it a single point of change.

This is a lightweight refactoring that does not require adopting a DI framework.

## Addressing Cross-Module Concrete Instantiation

The `ManifestTomlParser` instantiation pattern is the primary cross-module hotspot. Analysis:

| Instantiation site | On runtime hot path? | Justification |
|---|---|---|
| `Program.cs` | Yes | Top-level entry; single instance shared with runtime |
| `CaiCommandRuntime` (2 ctors) | No | Convenience constructors for tests; runtime uses `Program.cs` instance |
| `ContainerRuntimeCommandService` | No | Convenience constructor; runtime creates via factory |
| `CaiOperationsService` | No | Convenience constructor; runtime creates via factory |
| `CaiConfigManifestService` | No | Convenience constructor; runtime creates via factory |
| `CaiImportService` | No | Convenience constructor; runtime creates via factory |
| `CaiImportOrchestrationOperations` | No | Convenience constructor; runtime creates via factory |
| `ManifestGenerators` | Sometimes | Static convenience overload; main path uses injected parser |

**Assessment:** On the primary CLI command runtime path (non-docker-proxy invocations), a single `ManifestTomlParser` instance is created in `Program.cs` and threaded through the composition graph via `CaiCommandRuntime` and `CaiCommandRuntimeHandlersFactory`. The DockerProxy path creates its own instances via `ContainAiDockerProxy`'s static factory methods. The other 8 instantiation sites are convenience constructors or static overloads that exist solely for testing ergonomics and standalone usage. This is acceptable: `ManifestTomlParser` is a lightweight, stateless parser with no side effects, so multiple instances carry no cost.

**No remediation required.** The current pattern does not violate the inward-pointing dependency rule because all runtime dependencies point from concrete services to the `IManifestTomlParser` interface. The convenience constructors are syntactic sugar, not architectural coupling.

## Trim/AOT Compatibility Verification

The chosen approach (manual composition) is verified AOT-compatible and trim-safe:

- **PublishAot=true**: Enabled in `cai.csproj`. Builds successfully with zero AOT warnings.
- **PublishTrimmed=true**: Enabled with `TrimMode=link` (most aggressive). Zero trim warnings.
- **EnableTrimAnalyzer=true**: Enabled. Analyzer reports no issues with manual `new` wiring.
- **No reflection usage**: Composition uses only direct constructor calls. No `Activator.CreateInstance`, no `Type.GetType`, no `MethodInfo.Invoke`.
- **No `IServiceCollection`**: No MEDI registration patterns that could introduce reflection-based activation.
- **Source generators in use**: CsToml.Generator (TOML serialization) and ContainAI.EmbeddedAssets.Generator (resource embedding) -- both are compile-time only and produce trim-safe code.

## Migration Plan

**No migration is required.** The decision is to maintain the current approach.

### Future re-evaluation triggers

Re-evaluate this decision if any of the following occur:

1. **Service count exceeds 50 registrations** across all composition roots (currently ~20).
2. **Complex lifetime management is needed** (e.g., scoped services per request, disposable service chains).
3. **Microsoft ships an official MEDI source generator** that eliminates reflection from `IServiceCollection` registration. As of .NET 10, MEDI uses annotation attributes (`[DynamicallyAccessedMembers]`) for trim safety but does not have a source generator.
4. **A new module requires runtime service resolution** (service locator pattern) that cannot be satisfied with compile-time wiring.
5. **The dual-constructor pattern becomes a maintenance burden** (more than 15 services with convenience constructors for the same dependency).

Until a trigger is met, manual composition remains the correct choice for this codebase.

## References

- [Jab - C# Source Generator DI container](https://github.com/pakrym/jab)
- [Pure.DI - Pure DI for .NET](https://github.com/DevTeam/Pure.DI)
- [MEDI NativeAOT discussion (dotnet/runtime #110386)](https://github.com/dotnet/runtime/discussions/110386)
- [Native AOT deployment overview](https://learn.microsoft.com/en-us/dotnet/core/deploying/native-aot/)
- [.NET trimming compatibility](https://learn.microsoft.com/en-us/dotnet/core/deploying/trimming/prepare-libraries-for-trimming)
- Architecture assessment: `docs/specs/api-design-and-architecture-refactor-assessment-2026-02-11.md`
- PRD: `specs/cai-architecture-refactor-completion-prd.md`
- Composition roots: `src/cai/Program.cs`, `src/cai/CommandRuntime/Factory/CaiCommandRuntimeHandlersFactory.cs`, `src/cai/ContainerRuntime/ContainerRuntimeCommandService.cs`, `src/cai/DockerProxy/ContainAiDockerProxy.cs`
