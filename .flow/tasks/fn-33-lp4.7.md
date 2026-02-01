# fn-33-lp4.7 Implement doctor template checks

## Description
Doctor diagnoses template issues (missing, parse error). Fast filesystem checks by default. Add `--build-templates` flag for heavy validation (actual docker build).

## Acceptance
- [ ] `cai doctor` checks if default template exists
- [ ] Reports `[FAIL] Template 'default' missing` if not found
- [ ] Basic syntax check (FROM line exists) without docker daemon
- [ ] `cai doctor --build-templates` attempts actual docker build
- [ ] Heavy checks are opt-in only
- [ ] Reports actionable fix: "Run 'cai doctor fix template' to recover"

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
