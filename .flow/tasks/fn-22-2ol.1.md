# fn-22-2ol.1 Fix sysbox CI test jobs (image + headers)

## Description
Fix the sysbox CI test jobs that fail due to:
1. Non-existent Docker image tag `nestybox/ubuntu-focal-systemd-docker:20240618`
2. Unnecessary kernel header installation in test phase

**Size:** S
**Files:** `.github/workflows/build-sysbox.yml`

## Approach

- Change image tag from `nestybox/ubuntu-focal-systemd-docker:20240618` to `nestybox/ubuntu-focal-systemd-docker:latest` (minimal risk fix - keep purpose-built Sysbox image)
- Remove kernel header installation steps from test-amd64 and test-arm64 jobs
- **Important**: Move `sudo apt-get update` from the removed header step into the "Install sysbox deb" step (required for `apt-get install -f -y` to work)
- Keep existing systemd-based test logic since nestybox image supports systemd

## Key context

- Nestybox images are purpose-built for Sysbox; `docker:dind` would require extra validation for Sysbox compatibility
- The kernel headers step currently contains the only `apt-get update` in test jobs - must preserve it
- Test needs `apt-get update` before `apt-get install -f -y` or package installation may fail
- Lines to modify: 205-210, 264-302, 317-322, 376-414

## Acceptance
- [ ] Image tag changed from `:20240618` to `:latest` for nestybox image
- [ ] Kernel header install steps removed from both test jobs
- [ ] `apt-get update` preserved/moved to sysbox installation step
- [ ] Workflow syntax valid (yq/yamllint passes)
## Done summary
Fixed sysbox CI test jobs by changing nestybox image tag from non-existent :20240618 to :latest, removing unnecessary kernel header installation steps, and preserving apt-get update in the sysbox installation step.
## Evidence
- Commits: 371266138ca4449c15d0918cedd9846e3786a70e
- Tests: yq e '.' .github/workflows/build-sysbox.yml (YAML syntax validation)
- PRs:
