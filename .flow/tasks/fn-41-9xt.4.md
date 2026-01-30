# fn-41-9xt.4 Update documentation and help text

## Description
Update documentation to reflect the new silent-by-default behavior and `--verbose` flag.

**Size:** S
**Files:** `README.md`, `AGENTS.md`, `docs/setup-guide.md`, `.flow/memory/conventions.md`

## Approach

1. Update README.md common commands section to mention `--verbose`
2. Update AGENTS.md Code Conventions to document verbose pattern
3. Update docs/setup-guide.md to explain `--verbose` behavior
4. Add convention to .flow/memory/conventions.md
5. Prepare CHANGELOG.md entry (under Unreleased)

## Key context

The setup-guide.md already has examples with `--verbose` (lines 222, 323, 380). These should have explanation text added.
## Acceptance
- [ ] README.md mentions `--verbose` flag
- [ ] AGENTS.md Code Conventions documents verbose pattern
- [ ] docs/setup-guide.md explains `--verbose` behavior
- [ ] .flow/memory/conventions.md has verbose pattern entry
- [ ] CHANGELOG.md has entry under Unreleased
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
