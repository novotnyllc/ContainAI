# fn-29-fv0.3 Restructure doctor command to subcommand hierarchy

## Description
Restructure the doctor command from `--fix`/`--repair` flags to a subcommand hierarchy.

**Size:** M
**Files:** `src/containai.sh`, `src/lib/doctor.sh`

## Current state (before implementation)

- `_containai_doctor_cmd()` in containai.sh parsed `--fix` and `--repair` flags
- Routed to `_cai_doctor_fix`, `_cai_doctor_json`, or `_cai_doctor`
- `_cai_doctor_fix()` in doctor.sh implemented auto-remediation
- `_cai_doctor_repair()` in doctor.sh implemented volume ownership repair

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
   - Use `_cai_select_context("$(_containai_resolve_secure_engine_context …)")` for context resolution
   - Use `docker --context "$ctx"` consistently for container listing and SSH refresh
   - Don't hardcode to `$_CAI_CONTAINAI_DOCKER_CONTEXT`

## Key context

- Volume fix = permission/ownership repair (existing `_cai_doctor_repair`) - **Linux/WSL2 host only** (uses `$_CAI_CONTAINAI_DOCKER_DATA/volumes/...` paths, not valid for macOS Lima, nested mode, or non-default engine layouts)
- Container fix = SSH config refresh + restart if needed
- Use `_cai_doctor_get_container_volumes()` in doctor.sh for volume lookup
## Acceptance
- [x] `cai doctor fix --all` runs all available fixes
- [x] `cai doctor fix volume` lists available volumes
- [x] `cai doctor fix volume <name>` fixes specific volume
- [x] `cai doctor fix volume --all` fixes all volumes
- [x] `cai doctor fix volume` shows Linux/WSL2 host limitation note (not supported on macOS/nested mode)
- [x] `cai doctor fix container` lists available containers
- [x] `cai doctor fix container <name>` fixes specific container, including ssh key auth
- [x] `cai doctor fix container --all` fixes all containers
- [x] `cai doctor --fix` no longer present
- [x] `cai doctor --repair` no longer present
- [x] Help text documents new subcommand structure
## Done summary
Restructured doctor command from flag-based (--fix, --repair) to subcommand hierarchy (fix [volume|container]). Added context-aware helper functions for volume and UID detection. Updated troubleshooting docs to reflect new commands.
## Evidence
- Commits: 18524e8, 36b201a, 33f0038, 5bc82c9, 2364e97, c70ac24, 0eeb5cb, 0944a60
- Tests: shellcheck src/lib/doctor.sh, grep verification of --fix/--repair removal
- PRs:
