# fn-53-architecture-refactor-completion-naming.9 Documentation updates and refactor exceptions list

## Description
Update all documentation affected by the architecture refactor and create the refactor exceptions list.

**Size:** M
**Files:** 8 existing docs to update (`docs/architecture/` directory already exists from task 6)

### Documentation updates (by priority)

**High priority (blocking clarity):**
- `AGENTS.md` lines 36-63: Update Project Structure section with new folder organization
- `src/README.md` lines 11, 58-93: Update module descriptions and file path references
- `docs/architecture.md` lines 372-436: Update Component Architecture section, module dependencies table, Mermaid diagrams

**Medium priority (reference accuracy):**
- `docs/sync-architecture.md` lines 32-34, 409-413: Update file path references
- `docs/for-security-auditors.md` lines 53-55, 92-93, 117: Update file path references
- `docs/for-contributors.md` lines 118-134: Update Code Structure section
- `CONTRIBUTING.md` lines 76-90: Update Project Structure code block

**Existing documentation (verify only):**
- `docs/architecture/` directory already exists (created in task 6)
- Verify `docs/architecture/refactor-exceptions.md` is complete (created in task 6, extended in task 7 with 4 approved exceptions: 3 tiny-adapter, 1 source-generator)

### Approach
- Update file paths to match post-refactor locations
- Update Mermaid diagrams in architecture.md to show new module organization
- Add module layering subsection showing the co-located `I*.cs` interface extraction pattern (interfaces extracted into separate `I<ClassName>.cs` files adjacent to their implementations, not into `Contracts/` subfolders)
<!-- Updated by plan-sync: fn-53.7 established I*.cs co-location pattern, not Contracts/Models/Services subfolder pattern -->
- Keep documentation patterns consistent (inline backticks for paths, pipe-delimited tables for modules)

**Key Devcontainer updates (completed by fn-53.5):**
- All 42 Devcontainer files now use hierarchical namespaces: `ContainAI.Cli.Host.Devcontainer.*`
- Root files use `ContainAI.Cli.Host.Devcontainer`
- Each subfolder maps to namespace: Configuration/, InitLinks/, Install/, ProcessExecution/, Inspection/, Sysbox/, UserEnvironment/
- Namespace examples: `InitLinks/DevcontainerFeatureInitWorkflow.cs` uses `ContainAI.Cli.Host.Devcontainer.InitLinks`
- Updated by plan-sync: All 12 previously dotted-basename files now use folder-based names matching their new locations

**Key interface extraction updates (completed by fn-53.7):**
- 156 interfaces extracted from implementation files into co-located `I*.cs` files across all P1 modules
- Pattern: `FooService.cs` + `IFooService.cs` side-by-side (not in `Contracts/` subfolders)
- Modules processed: Sessions (46), Importing (42), Operations (27), remaining (41: ContainerLinks, Install, ShellProfile, ConfigManifest, Toml, AcpProxy, AgentShims, Examples, Manifests)
- 4 approved exceptions documented in `docs/architecture/refactor-exceptions.md`: 3 tiny-adapter (ContainerRuntimeLinkSpecFileReader, CaiDockerImagePuller, CaiGcAgeParser) + 1 source-generator (DevcontainerFeatureModels)
- Legacy `Contracts/` directories remain in 3 locations (Toml, DockerProxy, Importing/Facade) -- these predate the refactor and follow a different grouping pattern
<!-- Updated by plan-sync: fn-53.7 completed interface extraction for all P1 modules -->
## Acceptance
- [ ] All 8 affected docs updated with correct post-refactor file paths
- [ ] Mermaid diagrams in docs/architecture.md reflect new module structure
- [ ] AGENTS.md Project Structure section matches actual folder layout
- [ ] docs/architecture/ directory exists (already created in task 6, verify contents)
- [ ] No broken links or stale file path references in docs/
## Done summary
Updated file path references across 11 documentation files (AGENTS.md, CONTRIBUTING.md, SECURITY.md, docs/architecture.md, docs/sync-architecture.md, docs/for-security-auditors.md, docs/for-contributors.md, docs/cli-reference.md, docs/configuration.md, docs/adding-agents.md, src/README.md) to match the post-refactor modular folder structure in src/cai/. Updated Mermaid diagrams, module dependency tables, and project structure trees. Verified docs/architecture/refactor-exceptions.md exists with 4 approved exceptions.
## Evidence
- Commits: 55872171365b136031ed1ddf76f1968d41d06047
- Tests: grep-sweep for stale file path references across all markdown files
- PRs: