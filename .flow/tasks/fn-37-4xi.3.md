# fn-37-4xi.3 Verify suppression config docs are complete

## Description
Ensure the warning suppression config option is fully documented and linked. The implementation already exists in `src/lib/config.sh:535` and is documented in `docs/configuration.md:302`. This task verifies completeness and adds cross-references.

**Note**: The config option already exists. This task is verification/linking, not implementation.

## Acceptance
- [x] `docs/configuration.md` has complete `[template].suppress_base_warning` documentation
- [x] `docs/base-image-contract.md` links to configuration.md for suppression details
- [x] Both docs describe same behavior (suppress in builds and doctor checks)
- [x] Example TOML syntax is correct: `suppress_base_warning = true` under `[template]`

## Done summary
Verified that warning suppression config documentation is complete and correctly linked:

1. **docs/configuration.md** (lines 296-317): Complete `[template]` section with:
   - Table entry at line 302: `suppress_base_warning | boolean | false | Suppress warning...`
   - Example TOML at lines 305-307 showing correct syntax
   - Description of behavior at lines 309-313

2. **docs/base-image-contract.md** (lines 112-127):
   - Warning Suppression subsection with example TOML
   - Link to configuration.md#template-section at line 122
   - Explicitly lists where suppression applies: template builds and doctor checks

3. **Behavior consistency verified**: Both docs describe same behavior:
   - Suppresses warnings in template builds (`cai run`, `cai build`)
   - Suppresses warnings in doctor checks (`cai doctor`)
   - Config format: `[template]` section with `suppress_base_warning = true`

4. **Implementation verified**: Source code at `src/lib/config.sh:535-540` parses the config and stores in `_CAI_TEMPLATE_SUPPRESS_BASE_WARNING`, used by both template.sh (builds) and doctor.sh (health checks).

No code changes required - documentation was already complete and cross-referenced.

## Evidence
- Commits: (none - verification task)
- Tests: (none - verification task)
- PRs:
