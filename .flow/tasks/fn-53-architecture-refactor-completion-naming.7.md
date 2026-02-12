# fn-53-architecture-refactor-completion-naming.7 Contract/implementation separation: P1 modules (Sessions, Importing, Operations, remaining)

## Description
Extract co-located interfaces from implementation files in P1 modules. Processed in 4 independent batches, each with its own build+test gate.

**Size:** L (split into 4 batches for safe review and execution)
**Files:** ~177 files to evaluate, ~130-140 splits expected, ~35-40 approved exceptions

### Batch execution plan

**Batch A — Sessions (~46 mixed files):**
- Process by subfolder: Resolution/ → Execution/ → Provisioning/ → Models/ → remaining
- Sessions has hierarchical namespaces from task 4, so interface extraction benefits from clear module boundaries
- Build+test gate after batch A completes

**Batch B — Importing (~42 mixed files):**
- Process by subfolder: Environment/ → Facade/ → Orchestration/ → Paths/ → Symlinks/ → Transfer/
- Importing already has well-structured subfolders
- Build+test gate after batch B completes

**Batch C — Operations (~29 mixed files):**
- Process by subfolder: Diagnostics/ → DiagnosticsAndSetup/ → Facade/ → Maintenance/ → TemplateSshGc/
- Build+test gate after batch C completes

**Batch D — Remaining modules (~60 mixed files):**
- ContainerLinks (~11), Install (~8), ShellProfile (~6), and other small modules (~35)
- `ContainerLinks/Repair/ContainerLinkRepairContracts.cs` already exists as a contracts file — extend pattern
- Build+test gate after batch D completes

### Approach
- Follow the same pattern and exception rubric established in task 6
- Apply the same exception criteria (private-nested, source-generator, tiny-adapter ≤15 lines)
- Add all approved exceptions to `docs/architecture/refactor-exceptions.md` (created in task 6)
- **Each batch must pass `dotnet build -warnaserror` and `dotnet test` independently before proceeding to next batch**
- Commit per batch (not per file) for manageable review

### Key context
- Task 6 establishes the pattern; this task follows it mechanically
- The 4-batch structure ensures no single review exceeds ~50 files
- Exception rubric: same as task 6 (see epic spec for full rubric definition)
## Acceptance
- [ ] **Batch A (Sessions):** All ~46 mixed files evaluated, splits completed, build+test passes
- [ ] **Batch B (Importing):** All ~42 mixed files evaluated, splits completed, build+test passes
- [ ] **Batch C (Operations):** All ~29 mixed files evaluated, splits completed, build+test passes
- [ ] **Batch D (Remaining):** All ~60 mixed files evaluated, splits completed, build+test passes
- [ ] `docs/architecture/refactor-exceptions.md` updated with all approved exceptions (per rubric)
- [ ] Mixed file count reduced from 213 baseline to approved exceptions only
- [ ] `dotnet build ContainAI.slnx -c Release -warnaserror` passes (full solution)
- [ ] All existing tests pass unchanged
- [ ] slopwatch clean
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
