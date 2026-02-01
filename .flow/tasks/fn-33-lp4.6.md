# fn-33-lp4.6 Add warning suppression config

## Description
Add `[template].suppress_base_warning = true` config option. Update config parser in `src/lib/config.sh` to read `[template]` section.

## Acceptance
- [ ] Config parser extracts `template.suppress_base_warning` boolean
- [ ] Global `_CAI_TEMPLATE_SUPPRESS_BASE_WARNING` set from config
- [ ] Validation warning respects suppression flag
- [ ] Example in `docs/configuration.md` showing `[template]` section
- [ ] Works with both true/false and 1/0 values

## Done summary
Added [template].suppress_base_warning config option to control whether the base image validation warning is shown when building templates. Updated config parser to read the new option and pass it through to the template build flow.
## Evidence
- Commits: 5e34360e78d1697249fa953d98ed1c26c9d0f895
- Tests: ./tests/unit/test-template-paths.sh
- PRs:
