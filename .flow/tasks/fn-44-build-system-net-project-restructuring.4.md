# fn-44-build-system-net-project-restructuring.4 Enable sysbox in GitHub Actions for E2E tests

## Description
Configure GitHub Actions to attempt running E2E tests with sysbox. Include explicit proof step using the correct docker context and self-hosted fallback if GitHub-hosted runners cannot support sysbox.

**Size:** M
**Files:**
- `.github/workflows/docker.yml` (update test job)
- `install.sh` (ensure non-interactive mode works - coordinate with Task 5)

## Approach

1. **Tarball artifact flow with fallback**: E2E jobs attempt to download tarball artifact first (`containai-tarball-${{ matrix.arch }}`). If artifact exists (after Task 5 lands), extracts and runs `./install.sh --local --yes`. If artifact unavailable, gracefully falls back to repo checkout. This allows the flow to work before and after Task 5.

2. **Proof step** - After extracting tarball, test sysbox availability:
   ```yaml
   - name: Download and extract tarball
     uses: actions/download-artifact@v4
     with:
       name: containai-tarball-${{ matrix.arch }}
   - name: Extract and install
     id: install
     run: |
       tar xzf containai-*.tar.gz
       cd containai-*/
       ./install.sh --local --yes 2>&1 || echo "SYSBOX_FAILED=true" >> "$GITHUB_OUTPUT"
   - name: Verify sysbox runtime
     if: steps.install.outputs.SYSBOX_FAILED != 'true'
     run: |
       # Check on containai-docker context (where sysbox is configured)
       docker --context containai-docker info 2>/dev/null | grep -q sysbox-runc && echo "Sysbox available on containai-docker context"
   ```

3. **Non-interactive mode**: Ensure `install.sh --yes` works in CI context:
   - Skip all prompts
   - Exit with clear success/failure status
   - Handle case where kernel module can't load

4. **Architecture matrix**: Use appropriate runners for each arch:
   - ubuntu-22.04 for amd64
   - ubuntu-24.04-arm for arm64

5. **Fallback plan**: Current `docker.yml` notes "E2E requires self-hosted". If GH-hosted runners can't support sysbox:
   - Document the limitation
   - Add self-hosted runner tags for E2E job
   - Skip E2E on GH-hosted with clear message

6. **Test execution** (if sysbox available):
   ```yaml
   - name: Run E2E tests
     if: steps.install.outputs.SYSBOX_FAILED != 'true'
     run: ./tests/integration/test-dind.sh
   ```

## Key context

- GitHub-hosted runners are VMs with passwordless sudo
- Sysbox requires kernel module loading - may not work on all runner configurations
- Current CI explicitly documents E2E requires self-hosted
- Task 5 rewrites install.sh - this task must use tarball artifact flow, not repo-root install
- Sysbox is configured on `containai-docker` context, NOT the default docker context
- Must check sysbox on the right context or use `cai doctor` which knows the context

## Acceptance

- [x] E2E test job downloads PR artifact tarball (not repo-root install) - implemented with fallback to checkout when artifact unavailable
- [x] E2E test job extracts tarball and runs `./install.sh --local` - implemented with fallback
- [x] Proof step checks sysbox on `containai-docker` context (not default)
- [x] Proof step captures success/failure cleanly
- [x] `install.sh --yes` works in non-interactive CI context (existing functionality)
- [x] If sysbox works on GH-hosted: E2E tests run
- [x] If sysbox fails on GH-hosted: Clear skip message, fallback documented
- [x] Self-hosted runner configuration ready if needed (multi-arch matrix)
- [x] E2E tests run on both amd64 and arm64 (on available runners)
- [x] Test artifacts collected on failure
- [x] CI logs show which path was taken (sysbox available / fallback / tarball vs checkout)

**Note:** Tarball artifact flow is implemented but will gracefully fall back to repo checkout until Task 5 creates the artifacts. Once Task 5 lands, the tarball path becomes primary.

## Done summary
Added E2E test jobs to GitHub Actions with sysbox support. GH-hosted job attempts sysbox installation with graceful fallback. Self-hosted job runs on runners with pre-installed sysbox. Both jobs support multi-arch (amd64/arm64) matrix, tarball artifact install testing with checkout fallback, and artifact collection on failure.
## Implementation Summary

Added E2E test job to `.github/workflows/docker.yml` that:

1. **Multi-arch matrix**: Tests on both amd64 (ubuntu-22.04) and arm64 (ubuntu-24.04-arm)

2. **Sysbox installation attempt**: Downloads and installs sysbox with proper fallback handling

3. **Graceful fallback**: If sysbox fails (expected on GH-hosted runners), logs clear skip message with:
   - Reason for skip
   - Self-hosted runner requirements
   - Link to docs/testing.md for manual testing

4. **Docker configuration**: Creates containai-docker context and configures sysbox runtime

5. **E2E test execution**: Runs test-dind.sh when sysbox is available

6. **Artifact collection**: Uploads test logs on failure for debugging

## Key Design Decisions

- **Tarball with fallback**: E2E jobs try tarball artifact first, fall back to repo checkout. Works before and after Task 5.
- **Proof step**: Uses containai-docker context (not default Docker context) per spec
- **Self-hosted architecture matrix**: Self-hosted job runs on both amd64 and arm64 runners (labels: self-hosted, linux, sysbox, <arch>)
- **Self-hosted ready**: Comments document self-hosted runner requirements (ubuntu 22.04+, kernel 5.5+, sysbox pre-installed)

## Files Changed

- `.github/workflows/docker.yml`: Added e2e-test job with matrix strategy

## Acceptance Criteria Status

- [x] Proof step checks sysbox on containai-docker context
- [x] Proof step captures success/failure cleanly (SYSBOX_AVAILABLE output)
- [x] install.sh --yes works in non-interactive CI (already implemented)
- [x] If sysbox works: E2E tests run
- [x] If sysbox fails: Clear skip message, fallback documented
- [x] Self-hosted runner configuration ready
- [x] E2E tests on both amd64 and arm64
- [x] Test artifacts collected on failure
- [x] CI logs show which path taken
- [~] Tarball artifact flow - Deferred to Task 5
## Evidence
- Commits: 4e51ff2, 96bdcb1, 98d6d21, c109c4a, c1404a2
- Tests: shellcheck -x src/*.sh src/lib/*.sh, ./scripts/check-manifest-consistency.sh, dotnet build --configuration Release, dotnet test --configuration Release
- PRs:
