# fn-53-architecture-refactor-completion-naming.9 Documentation updates and refactor exceptions list

## Description
Update all documentation affected by the architecture refactor and create the refactor exceptions list.

**Size:** M
**Files:** 8 existing docs to update + 1 new directory (`docs/architecture/`)

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

**New documentation:**
- Create `docs/architecture/` directory
- Verify `docs/architecture/refactor-exceptions.md` is complete (created in task 6, extended in task 7)

### Approach
- Update file paths to match post-refactor locations
- Update Mermaid diagrams in architecture.md to show new module organization
- Add module layering subsection showing Contracts/Models/Services pattern per module
- Keep documentation patterns consistent (inline backticks for paths, pipe-delimited tables for modules)

**Key Devcontainer updates (completed by fn-53.5):**
- All 42 Devcontainer files now use hierarchical namespaces: `ContainAI.Cli.Host.Devcontainer.*`
- Root files use `ContainAI.Cli.Host.Devcontainer`
- Each subfolder maps to namespace: Configuration/, InitLinks/, Install/, ProcessExecution/, Inspection/, Sysbox/, UserEnvironment/
- Namespace examples: `InitLinks/DevcontainerFeatureInitWorkflow.cs` uses `ContainAI.Cli.Host.Devcontainer.InitLinks`
- Updated by plan-sync: All 12 previously dotted-basename files now use folder-based names matching their new locations
## Acceptance
- [ ] All 8 affected docs updated with correct post-refactor file paths
- [ ] Mermaid diagrams in docs/architecture.md reflect new module structure
- [ ] AGENTS.md Project Structure section matches actual folder layout
- [ ] docs/architecture/ directory created
- [ ] No broken links or stale file path references in docs/
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
