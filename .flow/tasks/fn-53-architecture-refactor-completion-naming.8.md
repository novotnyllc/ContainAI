# fn-53-architecture-refactor-completion-naming.8 AOT composition decision record

## Description
Research and document the AOT composition strategy as an architecture decision record (ADR). Evaluates whether the current manual composition pattern is sufficient or if source-generated DI should be adopted.

**Size:** S (research + writing, no code changes)
**Files:** 1 new file (`specs/cai-aot-composition-decision-record.md`)

### Approach
- Review current composition roots:
  - `src/cai/Program.cs` (top-level entry)
  - `src/cai/CommandRuntime/Factory/CaiCommandRuntimeHandlersFactory.cs:5-31` (central factory)
  - `src/cai/DockerProxy/ContainAiDockerProxy.cs:29-61` (DockerProxy factory)
  - `src/cai/ContainerRuntime/ContainerRuntimeCommandService.cs:16-49` (ContainerRuntime constructor)
- Evaluate 3 options: (1) keep manual composition, (2) adopt Jab (compile-time DI), (3) adopt Pure.DI
- Assess against criteria: AOT safety, trim safety, startup overhead, maintenance burden, testing ergonomics
- Document the dual-constructor pattern (`public` with `new`, `internal` with interfaces) and whether it should continue
- Coordinate with fn-52 (AOT DI strategy) findings — this task produces the decision record that fn-52 scoped

### Key context
- Current composition is already fully AOT-safe (pure `new` wiring, no reflection)
- MEDI source generator does not exist; MEDI is AOT-safe with explicit registrations
- `ManifestTomlParser` instantiated in 8 places — evaluate if this warrants centralized wiring
- CLI startup is already fast with NativeAOT — DI container overhead is marginal concern
- Practice-scout finding: Jab (200x faster startup than MEDI) vs Pure.DI (zero runtime deps)
## Acceptance
- [ ] `specs/cai-aot-composition-decision-record.md` created with: options considered, tradeoffs, final decision, migration plan
- [ ] Decision addresses the dual-constructor pattern explicitly
- [ ] Decision addresses cross-module concrete instantiation hotspots (ManifestTomlParser in 8 places)
- [ ] Trim/AOT compatibility verified for chosen approach
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
