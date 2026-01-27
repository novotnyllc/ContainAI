# fn-29-fv0.3 Restructure doctor command to subcommand hierarchy

## Description
Restructure the doctor command from `--fix`/`--repair` flags to a subcommand hierarchy.

**Size:** M
**Files:** `src/containai.sh`, `src/lib/doctor.sh`

## Current state

- `src/containai.sh:1391-1395` parses `--fix` and `--repair` flags
- `src/containai.sh:1518-1522` routes to `_cai_doctor_fix`, `_cai_doctor_json`, or `_cai_doctor`
- `src/lib/doctor.sh:1041-1400` implements `_cai_doctor_fix()` auto-remediation
- `src/lib/doctor.sh:2051-2185` implements `_cai_doctor_repair()` volume ownership

## New CLI structure

```
cai doctor                      # Run diagnostics (existing behavior, plus ssh key auth checks)
cai doctor fix                  # Show available fix targets
cai doctor fix --all            # Fix everything fixable
cai doctor fix volume           # List volumes, offer to fix
cai doctor fix volume --all     # Fix all volumes
cai doctor fix volume <name>    # Fix specific volume
cai doctor fix container        # List containers, offer to fix
cai doctor fix container --all  # Fix all containers (including ssh key auth)
cai doctor fix container <name> # Fix specific container
```

## Approach

1. In `containai.sh`, add subcommand parsing after `doctor`:
   - If next arg is `fix`, enter fix subcommand mode
   - Parse `fix` target: `volume`, `container`, or `--all`
   - Parse optional name or `--all` after target

2. In `doctor.sh`, create new entry points:
   - `_cai_doctor_fix_dispatch()` - routes based on target
   - `_cai_doctor_fix_volume()` - takes name or `--all`
   - `_cai_doctor_fix_container()` - takes name or `--all`

3. List known volumes/containers when no name given:
   - Containers: from `docker ps -a --filter "label=containai.managed=true"` (containers have the label)
   - Volumes: derive from managed containers via `docker inspect` mounts (volumes aren't created with labels - use `_cai_doctor_get_container_volumes()` approach at `doctor.sh:1946-1956`)

4. Remove `--fix` and `--repair`, no backwards compat

5. In fix dispatch, resolve effective context:
   - Use `_cai_select_context("$(_containai_resolve_secure_engine_context …)")` (at `doctor.sh:152-230`)
   - Use `docker --context "$ctx"` consistently for container listing and SSH refresh
   - Don't hardcode to `$_CAI_CONTAINAI_DOCKER_CONTEXT`

## Key context

- Volume fix = permission/ownership repair (existing `_cai_doctor_repair`) - **Linux/WSL2 host only** (uses `$_CAI_CONTAINAI_DOCKER_DATA/volumes/...` paths, not valid for macOS Lima, nested mode, or non-default engine layouts)
- Container fix = SSH config refresh + restart if needed
- Use `_cai_doctor_get_container_volumes()` at `doctor.sh:1946-1956` for volume lookup
## Acceptance
- [ ] `cai doctor fix --all` runs all available fixes
- [ ] `cai doctor fix volume` lists available volumes
- [ ] `cai doctor fix volume <name>` fixes specific volume
- [ ] `cai doctor fix volume --all` fixes all volumes
- [ ] `cai doctor fix volume` shows Linux/WSL2 host limitation note (not supported on macOS/nested mode)
- [ ] `cai doctor fix container` lists available containers
- [ ] `cai doctor fix container <name>` fixes specific container, including ssh key auth
- [ ] `cai doctor fix container --all` fixes all containers
- [ ] `cai doctor --fix` no longer present
- [ ] `cai doctor --repair` no longer present
- [ ] Help text documents new subcommand structure
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
