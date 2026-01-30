# fn-31-gib.9 Implement data-migration test scenario

## Description
Test volume with user modifications survives container recreation. Ensures user customizations persist.

## Acceptance
- [ ] Test function `test_data_migration()` in test suite
- [ ] Test container named `test-data-migration-XXXX` with `containai.test=1` label
- [ ] Test volume named `test-data-migration-data-XXXX` with `containai.test=1` label
- [ ] Creates volume with initial config
- [ ] Makes user modification inside container (adds custom file)
- [ ] Stops and removes container
- [ ] Creates new container with same volume
- [ ] Asserts: user modification still present
- [ ] Asserts: symlinks still valid
- [ ] Asserts: no data loss (original + custom files present)
- [ ] Cleans up on success/failure (trap)

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
