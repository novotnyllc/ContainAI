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
TBD

## Evidence
- Commits:
- Tests:
- PRs:
