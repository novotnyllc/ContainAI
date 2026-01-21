# fn-10-vep.32 Remove docker sandbox run code path from lib/container.sh

## Description
Remove the `docker sandbox run` code path from `lib/container.sh` and clean up the entire ECI-related CLI surface. ContainAI will no longer support Docker Desktop's sandbox feature.

**Size:** M  
**Files:** `src/lib/container.sh`, `src/lib/docker.sh`, `src/containai.sh`, `docs/architecture.md`, `docs/quickstart.md`

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
- [ ] `docker sandbox run` code path removed from `_containai_run()`
- [ ] `_cai_sandbox_feature_enabled()` no longer called in container creation flow
- [ ] Context selection prefers Sysbox context unconditionally
- [ ] ECI-specific flags (`--credentials`, `--mount-docker-socket`) removed
- [ ] `cai run` works without Docker Desktop installed
- [ ] `cai sandbox` subcommands removed or show deprecation message
- [ ] docs/architecture.md updated (ECI paths removed or marked legacy)
- [ ] docs/quickstart.md updated (ECI not shown as option)
- [ ] Help strings no longer mention ECI
- [ ] Tests referencing `docker sandbox` updated
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
