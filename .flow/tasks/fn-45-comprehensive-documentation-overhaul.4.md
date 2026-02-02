# fn-45-comprehensive-documentation-overhaul.4 Document ephemeral vs persistent usage patterns

## Description
Create a usage patterns guide that explicitly documents the two primary usage modes: ephemeral (disposable sandbox) and persistent (long-lived dev environment). Users currently have to piece this together from lifecycle.md and various hints.

**Size:** M
**Files:** `docs/usage-patterns.md` (new)

## Approach

1. **Ephemeral Pattern** section:
   - When to use: quick experiments, untrusted code, CI
   - Workflow: `cai` → work → `cai stop --remove`
   - Data handling: nothing persists, fresh each time
   - Flags: `--fresh`, `--reset`

2. **Persistent Pattern** section:
   - When to use: ongoing projects, customized environments
   - Workflow: `cai` → work → `cai stop` → resume later
   - Data handling: volumes persist, `cai import`/`cai export`
   - Flags: default behavior, `--data-volume`

3. **Comparison table**: Side-by-side of both patterns

4. **Mermaid decision flowchart** (REQUIRED):
   - Help users choose between ephemeral and persistent
   - Decision tree based on use case questions
   - Use standard dark theme from epic spec

5. **Migration scenarios**:
   - "I started ephemeral but want to keep this work"
   - "I want to reset a persistent container"

6. Reference existing content:
   - `docs/lifecycle.md:1-30` (container states)
   - `docs/sync-architecture.md` (what syncs)

## Key context

The term "VM-like" implies persistence. Users coming from Docker expect ephemeral. This doc bridges that gap.

Key insight from lifecycle.md: containers are "persistent workspaces" by default, but can be used ephemerally with flags.
## Approach

1. **Ephemeral Pattern** section:
   - When to use: quick experiments, untrusted code, CI
   - Workflow: `cai` → work → `cai stop --remove`
   - Data handling: nothing persists, fresh each time
   - Flags: `--fresh`, `--reset`

2. **Persistent Pattern** section:
   - When to use: ongoing projects, customized environments
   - Workflow: `cai` → work → `cai stop` → resume later
   - Data handling: volumes persist, `cai import`/`cai export`
   - Flags: default behavior, `--data-volume`

3. **Comparison table**: Side-by-side of both patterns

4. **Migration scenarios**:
   - "I started ephemeral but want to keep this work"
   - "I want to reset a persistent container"

5. Reference existing content:
   - `docs/lifecycle.md:1-30` (container states)
   - `docs/sync-architecture.md` (what syncs)

## Key context

The term "VM-like" implies persistence. Users coming from Docker expect ephemeral. This doc bridges that gap.

Key insight from lifecycle.md: containers are "persistent workspaces" by default, but can be used ephemerally with flags.
## Acceptance
- [ ] Ephemeral pattern documented with complete workflow
- [ ] Persistent pattern documented with complete workflow
- [ ] Comparison table showing key differences
- [ ] **Mermaid decision flowchart** for choosing pattern (REQUIRED, use standard dark theme)
- [ ] Migration scenarios covered (ephemeral→persistent, reset persistent)
- [ ] Cross-references to lifecycle.md and sync-architecture.md
- [ ] Examples using actual cai commands
- [ ] Diagram renders correctly on GitHub
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
