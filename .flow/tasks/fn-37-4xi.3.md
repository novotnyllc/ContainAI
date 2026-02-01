# fn-37-4xi.3 Verify suppression config docs are complete

## Description
Ensure the warning suppression config option is fully documented and linked. The implementation already exists in `src/lib/config.sh:535` and is documented in `docs/configuration.md:302`. This task verifies completeness and adds cross-references.

**Note**: The config option already exists. This task is verification/linking, not implementation.

## Acceptance
- [ ] `docs/configuration.md` has complete `[template].suppress_base_warning` documentation
- [ ] `docs/base-image-contract.md` links to configuration.md for suppression details
- [ ] Both docs describe same behavior (suppress in builds and doctor checks)
- [ ] Example TOML syntax is correct: `suppress_base_warning = true` under `[template]`

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
