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
TBD

## Evidence
- Commits:
- Tests:
- PRs:
