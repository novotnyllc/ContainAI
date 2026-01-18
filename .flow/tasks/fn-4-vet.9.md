# fn-4-vet.9 Create lib/container.sh - container operations

## Description
Create `agent-sandbox/lib/container.sh` - container operations extracted from aliases.sh.

## Functions to Extract

### `_containai_container_name()`
Generate sanitized container name from git repo/branch or directory.
(Copy from `_asb_container_name()` in aliases.sh:28-87)

### `_containai_check_isolation()`
Container isolation detection.
(Copy from `_asb_check_isolation()` in aliases.sh:91-127)

### `_containai_check_sandbox()`
Check if inside sandbox container.
(Copy from `_asb_check_sandbox()` in aliases.sh:130-229)

### `_containai_preflight_checks()`
Run preflight checks before container operations.
(Copy from `_asb_preflight_checks()` in aliases.sh:232-276)

### `_containai_ensure_volumes(volume_name)`
Ensure data volume exists. Takes volume name as parameter.
(Modify from `_asb_ensure_volumes()` in aliases.sh:349-369)

### `_containai_start_container(options...)`
Start or attach to container. Core logic from `asb()`.

### `_containai_stop_all()`
Stop all ContainAI containers.
(From `asb-stop-all()` in aliases.sh:827-894)

## Key Changes
- Rename all `_asb_` prefixes to `_containai_`
- `_containai_ensure_volumes` takes volume name parameter
- Update labels to use `containai.sandbox` instead of `asb.sandbox`
## Acceptance
- [ ] File exists at `agent-sandbox/lib/container.sh`
- [ ] All functions renamed from `_asb_*` to `_containai_*`
- [ ] `_containai_ensure_volumes` accepts volume name parameter
- [ ] Labels changed to `containai.sandbox=containai`
- [ ] `_containai_stop_all` works correctly
- [ ] Functions are self-contained (can be sourced independently with config.sh)
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
