# fn-33-lp4.8 Implement doctor fix template recovery

## Description
`cai doctor fix template [--all | <name>]` backs up and restores from repo. Works for repo-shipped templates; user templates get backup + error.

## Acceptance
- [ ] `cai doctor fix template` recovers default template
- [ ] `cai doctor fix template <name>` recovers specific template
- [ ] `cai doctor fix template --all` iterates all template directories
- [ ] Backup created: `Dockerfile.backup.YYYYMMDD-HHMMSS`
- [ ] Repo templates (default, example-ml): restore from `src/templates/{name}.Dockerfile`
- [ ] User-created templates: backup only, then error with guidance
- [ ] Logs backup and restore paths with `_cai_info()`

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
