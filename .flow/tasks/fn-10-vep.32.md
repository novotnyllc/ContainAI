# fn-10-vep.32 Remove docker sandbox run code path from lib/container.sh

## Description
Remove all legacy code from lib/container.sh and delete lib/eci.sh entirely. Start fresh with Sysbox-only implementation.

**Size:** M
**Files:** lib/container.sh, lib/eci.sh (delete), lib/docker.sh

## Approach

1. Delete `lib/eci.sh` file completely
2. Remove all references to ECI from lib/container.sh
3. Remove `docker sandbox run` code path
4. Remove any `_cai_sandbox_*` functions
5. Clean up lib/docker.sh to remove ECI-related code
6. Update any imports/sources that reference eci.sh
## Approach

1. In `lib/container.sh`, find the ECI/sandbox code path in `_containai_run()` (~L1411-1476)
2. Remove the entire `docker sandbox run` branch
3. Keep only the Sysbox path (`docker run --runtime=sysbox-runc`)
4. Remove `_cai_sandbox_feature_enabled()` check from `lib/docker.sh`
5. Update `_cai_select_context()` to always use Sysbox context (no ECI fallback)
6. Remove any `--credentials host` and `--mount-docker-socket` handling (ECI-only features)
7. **Remove or deprecate `cai sandbox` subcommands** with helpful migration message
8. **Update help strings** to remove ECI references
9. **Update docs/architecture.md** - remove or mark ECI paths as legacy
10. **Update docs/quickstart.md** - remove ECI as a prerequisite option

## Key context

- `docker sandbox run` is Docker Desktop 4.50+ only
- ECI path uses `--workspace`, `--template`, `--credentials` flags
- Sysbox path uses standard `docker run` with `-v` for volumes
- Users attempting `cai sandbox` should get helpful "use cai run instead" message
## Approach

1. In `lib/container.sh`, find the ECI/sandbox code path in `_containai_run()` (~L1411-1476)
2. Remove the entire `docker sandbox run` branch
3. Keep only the Sysbox path (`docker run --runtime=sysbox-runc`)
4. Remove `_cai_sandbox_feature_enabled()` check from `lib/docker.sh`
5. Update `_cai_select_context()` to always use Sysbox context (no ECI fallback)
6. Remove any `--credentials host` and `--mount-docker-socket` handling (ECI-only features)

## Key context

- `docker sandbox run` is Docker Desktop 4.50+ only
- ECI path uses `--workspace`, `--template`, `--credentials` flags
- Sysbox path uses standard `docker run` with `-v` for volumes
- The `discover_mirrored_workspace()` in entrypoint relies on sandbox mirror mounts - will need update later (separate task)

## References

- Current ECI path: `src/lib/container.sh:1411-1476`
- Sandbox feature check: `src/lib/docker.sh:_cai_sandbox_feature_enabled`
- Context selection: `src/lib/doctor.sh:_cai_select_context`
## Acceptance
- [ ] lib/eci.sh deleted entirely
- [ ] No ECI references in any lib/*.sh files
- [ ] No `docker sandbox` code paths
- [ ] Clean codebase with no legacy references
- [ ] All tests still pass (or are updated)
## Done summary
Removed all ECI (Enhanced Container Isolation) and Docker Desktop sandbox code paths from lib files, leaving Sysbox as the sole isolation mechanism. Updated documentation (architecture.md, quickstart.md) to reflect Sysbox-only mode.
## Evidence
- Commits: 57fd235029b7cee4d8d0e619c0976d642bd8ac09, 1bef06e, 0a7b9ac, 71929a0, 7e6b4d8, 4759080
- Tests: bash -n src/containai.sh, bash -n src/lib/container.sh, bash -n src/lib/doctor.sh
- PRs:
