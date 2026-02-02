# fn-38-8lv.2 Document agent config patterns

## Description

Add detailed conventions section to `docs/adding-agents.md` covering the patterns and practices for agent configuration. This task enhances the base documentation with practical guidance.

Key areas to document:
- Flag usage conventions (when to use each flag)
- Path pattern conventions (source vs target vs container_link)
- Optional sync with `o` flag for non-primary agents
- Credential handling patterns (using `s` flag appropriately)
- The _IMPORT_SYNC_MAP requirement and consistency enforcement

## Acceptance

- [ ] Conventions section added to docs/adding-agents.md
- [ ] Flag usage guidelines explain when to use each flag
- [ ] Path pattern conventions documented (relative paths, volume structure)
- [ ] `o` flag guidance: required agents omit, optional agents include
- [ ] Credential handling with `s` flag documented
- [ ] _IMPORT_SYNC_MAP + check-manifest-consistency.sh workflow clear
- [ ] No BRE grep patterns used (use rg or grep -E per AGENTS.md)

## Done summary
Added comprehensive Conventions section to docs/adding-agents.md covering:

1. **Flag Usage Guidelines** - Table mapping scenarios to recommended flags with rationale
2. **Path Pattern Conventions** - Explains source/target/container_link field purposes
3. **Optional Sync (o flag)** - When to use for primary vs optional agents
4. **Credential Handling (s flag)** - When and how to mark files as secrets
5. **_IMPORT_SYNC_MAP Alignment** - Workflow for keeping manifest and import map in sync
6. **Directory Flags** - Special flags for directory entries (d, dR, dxR, dm, dp)

Section placed after Overview for visibility before step-by-step instructions.
## Evidence
- Commits:
- Tests:
- PRs:
