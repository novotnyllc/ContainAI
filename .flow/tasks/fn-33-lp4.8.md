# fn-33-lp4.8 Implement doctor fix template recovery

<!-- Updated by plan-sync: fn-33-lp4.7 already implemented this functionality -->

## Description
`cai doctor fix template [--all | <name>]` backs up and restores from repo. Works for repo-shipped templates; user templates get backup + error.

**NOTE:** This functionality was already implemented as part of fn-33-lp4.7. The implementation exists in:
- `_cai_doctor_fix_template()` in `/home/agent/workspace/src/lib/doctor.sh` (line 2103)
- `_cai_doctor_fix_single_template()` in `/home/agent/workspace/src/lib/doctor.sh` (line 2177)

## Acceptance
- [x] `cai doctor fix template` recovers default template
- [x] `cai doctor fix template <name>` recovers specific template
- [x] `cai doctor fix template --all` iterates all template directories (via `_CAI_REPO_TEMPLATES` array)
- [x] Backup created: `Dockerfile.backup.YYYYMMDD-HHMMSS`
- [x] Repo templates (default, example-ml): restore from `src/templates/{name}.Dockerfile` via `_cai_get_repo_templates_dir()`
- [x] User-created templates: backup only, then error with guidance ("User template, cannot restore from repo")
- [x] Logs backup and restore paths with formatted output

## Done summary
Already implemented in fn-33-lp4.7. See `_cai_doctor_fix_template()` and `_cai_doctor_fix_single_template()` in src/lib/doctor.sh.

## Evidence
- Commits:
- Tests:
- PRs:
