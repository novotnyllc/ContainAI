# fn-33-lp4.12 Add integration test

## Description
Create `tests/integration/test-templates.sh` to verify template build, doctor checks, and recovery.

## Acceptance
- [ ] Test script at `tests/integration/test-templates.sh`
- [ ] Tests template installation via setup
- [ ] Tests template build produces correct image tag
- [ ] Tests doctor detection of missing template
- [ ] Tests doctor fix template recovery
- [ ] Tests layer validation warning for non-ContainAI base
- [ ] Image inspection uses same Docker context as build (`docker --context "$ctx" image inspect`)
- [ ] CI guard: skip if Docker unavailable (`command -v docker` check)
- [ ] Test passes in CI (requires Docker)

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
