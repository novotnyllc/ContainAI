# fn-31-gib.1 Fix SSH keygen noise during import

## Description
The `eeacms/rsync` image runs ssh-keygen in its entrypoint during mount preflight checks. Override the entrypoint to eliminate this noise. Currently, tests filter out "Generating SSH … ssh-keygen …" messages in `run_in_rsync`.

**Root cause:** `src/lib/import.sh` runs `docker ... eeacms/rsync true` for mount preflight, which triggers the image's entrypoint.

**Fix:** Use `--entrypoint` to bypass the rsync image's default entrypoint.

## Acceptance
- [ ] `cai import` produces no ssh-keygen related output in stdout/stderr
- [ ] `src/lib/import.sh` rsync invocations use `--entrypoint sh` or `--entrypoint rsync` to bypass entrypoint
- [ ] `tests/integration/test-sync-integration.sh` `run_in_rsync` no longer needs to filter ssh-keygen messages
- [ ] New test case explicitly verifies: `cai import 2>&1 | grep -q ssh-keygen && exit 1` passes

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
