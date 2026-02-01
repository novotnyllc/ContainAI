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
Implemented doctor template checks with fast filesystem checks by default and optional heavy validation via --build-templates flag. Added 'cai doctor fix template' command to restore templates from repo with backup support.
## Evidence
- Commits: c3e5a10, 6df362f, 406ab33, 16abe8c
- Tests: shellcheck -x src/lib/doctor.sh src/containai.sh, cai doctor, cai doctor --json, cai doctor --build-templates, cai doctor fix template
- PRs:
