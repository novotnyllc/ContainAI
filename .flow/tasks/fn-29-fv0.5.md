# fn-29-fv0.5 Auto-repair containai-docker context when endpoint wrong

## Description
Auto-repair the `containai-docker` Docker context when it reverts to wrong endpoint (happens after Docker Desktop updates).

**Size:** S
**Files:** `src/lib/docker.sh`, possibly `src/lib/container.sh`

## Problem

After Docker Desktop updates on Windows, the `containai-docker` context can revert from `ssh://containai-docker-daemon/...` to `unix://...`. Users have to manually fix this.

## Existing detection

At `docker.sh:514-539`, `_cai_containai_docker_context_exists()`:
- Checks if context exists via `docker context inspect`
- Compares actual endpoint to expected (`_cai_expected_docker_host()`)
- Sets `_CAI_CONTAINAI_CONTEXT_ERROR="wrong_endpoint"` on mismatch

## Approach

1. After detecting `wrong_endpoint`, automatically recreate the context:
   - Call existing context creation logic (look in `setup.sh:1813-1851`)
   - Use `docker context rm containai-docker` then `docker context create`

2. Trigger the check+repair at strategic points (not every command):
   - On `cai run` when context doesn't match
   - On `cai shell` when context doesn't match
   - On `cai doctor` (existing diagnostic flow)

3. Show user-friendly message when --verboase|-v is requested:
   ```
   [WARN] Docker context 'containai-docker' had wrong endpoint (was unix://, expected ssh://)
   [OK] Context auto-repaired
   ```

## Key context

- Expected endpoints by platform at `docker.sh:355-369`
- WSL2 expects: `ssh://containai-docker-daemon/var/run/containai-docker.sock`
- Context creation at `setup.sh:1813-1851` via `_cai_create_isolated_docker_context()`
## Acceptance
- [ ] Wrong context endpoint is detected automatically
- [ ] Context is auto-repaired without user intervention
- [ ] User sees warning about what was fixed
- [ ] Repair only happens when endpoint is actually wrong (not on every run)
- [ ] Works on WSL2 where ssh:// endpoint is expected
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
