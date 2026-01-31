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
Added import integration tests to CI workflow with tiered strategy: lint job runs shellcheck and manifest consistency on ubuntu-latest, test job builds image and runs full integration test suite on PRs after build job completes. E2E tests requiring sysbox are documented in docs/testing.md for manual execution.
## Evidence
- Commits: 83a4df79aca60a40defc6c8f87d85bc2d0b2e1c5, 9dc2b8974eda69d6b8175a550c9cec9a47f3160d
- Tests: shellcheck -x src/*.sh src/lib/*.sh, ./scripts/check-manifest-consistency.sh, python3 -c 'import yaml; yaml.safe_load(...)'
- PRs:
