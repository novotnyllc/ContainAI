# fn-44-build-system-net-project-restructuring.4 Enable sysbox in GitHub Actions for E2E tests

## Description
Configure GitHub Actions to attempt running E2E tests with sysbox. Include explicit proof step using the correct docker context and self-hosted fallback if GitHub-hosted runners cannot support sysbox.

**Size:** M
**Files:**
- `.github/workflows/docker.yml` (update test job)
- `install.sh` (ensure non-interactive mode works - coordinate with Task 5)

## Approach

1. **Coordinate with Task 5's install.sh rewrite**: Task 5 rewrites install.sh to be dual-mode (standalone download OR --local from tarball). This task must use the same artifact flow:
   - PR builds upload tarball to Actions artifacts (from Task 5)
   - Download PR artifact tarball
   - Extract and run `./install.sh --local`
   - This tests the real install path users will use

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
- [ ] E2E test job downloads PR artifact tarball (not repo-root install)
- [ ] E2E test job extracts tarball and runs `./install.sh --local`
- [ ] Proof step checks sysbox on `containai-docker` context (not default)
- [ ] Proof step captures success/failure cleanly
- [ ] `install.sh --yes` works in non-interactive CI context
- [ ] If sysbox works on GH-hosted: E2E tests run
- [ ] If sysbox fails on GH-hosted: Clear skip message, fallback documented
- [ ] Self-hosted runner configuration ready if needed
- [ ] E2E tests run on both amd64 and arm64 (on available runners)
- [ ] Test artifacts collected on failure
- [ ] CI logs show which path was taken (sysbox available / fallback)

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
