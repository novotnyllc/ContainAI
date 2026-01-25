# fn-19-qni.2 Add --docker-bundle to uninstall

## Description
Add `--docker-bundle` flag to `cai uninstall` to remove the managed Docker binaries at `/opt/containai/docker/`. Currently uninstall preserves this directory, but users should be able to fully remove all ContainAI artifacts.

**Size:** S
**Files:** `src/lib/uninstall.sh`

## Approach

1. Add `--docker-bundle` flag parsing in `_cai_uninstall()` at line 441
2. Before removing, check if `containai-docker.service` is running and stop it
3. Remove `/opt/containai/docker/` directory and `/opt/containai/bin/` symlinks
4. Update help text

### Reuse points

- Follow pattern of existing `--containers` and `--volumes` flags
- Use `_cai_uninstall_service()` pattern for service handling at line 505
- Use `_cai_step`, `_cai_ok`, `_cai_warn` for progress reporting

### Safety checks

- Warn if any containers are still running (require `--force` or stop first)
- Check if Docker socket is in use by other processes
- Require explicit confirmation (or `--yes` flag)
## Acceptance
- [ ] `cai uninstall --docker-bundle` removes `/opt/containai/docker/`
- [ ] `cai uninstall --docker-bundle` removes `/opt/containai/bin/` symlinks
- [ ] Stops `containai-docker.service` before removal
- [ ] Warns if containers still running (must use `--containers` too or stop first)
- [ ] Requires confirmation unless `--yes` flag provided
- [ ] Works with existing flags: `--docker-bundle --containers --volumes`
- [ ] `cai uninstall --help` documents new flag
- [ ] Passes `shellcheck -x src/lib/uninstall.sh`
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
