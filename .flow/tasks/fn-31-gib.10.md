# fn-31-gib.10 Integrate tests into CI

## Description
Add import tests to GitHub Actions with tiered strategy: host-side tests on standard runners, E2E on self-hosted.

## Acceptance
- [ ] `.github/workflows/test.yml` (or similar) includes import test job
- [ ] Host-side tests (manifest parsing, consistency check) run on `ubuntu-latest`
- [ ] E2E tests run on self-hosted runner OR documented as manual-only with skip
- [ ] Tests run on PR (not just push to main)
- [ ] CI failure messages clearly identify which test failed
- [ ] Test job depends on build job (image available)

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
