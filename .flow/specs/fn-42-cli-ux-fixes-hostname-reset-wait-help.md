# fn-42 CLI UX Fixes: Hostname, Reset Wait, Help Defaults

## Overview

Collection of small CLI UX fixes that improve daily usage of ContainAI.

## Scope

### In Scope
1. **Short container names (max 24 chars)** - Format: `{repo}-{branch_leaf}`
2. **Container hostname matches name** - Add `-h` flag to `docker run`
3. **--fresh/--reset wait for ready** - Wait for SSH-ready before returning

### Out of Scope (handled by fn-34-fk5)
- `cai` no-params shows help, `cai run` redesign, exec/run/shell consolidation

## Approach

### Fix 1: Short Container Names

**Current format:** `containai-{repo}-{branch}` (up to 59 chars)
**New format:** `{repo}-{branch_leaf}` (max 24 chars)

**Branch leaf extraction:**
- `feature/oauth` → `oauth`
- `bugfix/login-fix` → `login-fix`
- `main` → `main`
- On conflict, include parent segment: `feature-oauth` vs `bugfix-oauth`

**Examples:**
| Workspace           | Branch           | Result                                      |
|---------------------|------------------|---------------------------------------------|
| `containai`         | `main`           | `containai-main`                            |
| `my-app`            | `feature/oauth`  | `my-app-oauth`                              |
| `my-app`            | `bugfix/oauth`   | `my-app-bugfix-oauth` (conflict with above) |
| `project`           | `feat/ui/button` | `project-button`                            |
| `long-project-name` | `dev`            | `long-project-name-dev`                     |

**Algorithm:**
1. Sanitize repo (lowercase, alphanumeric + dash)
2. Extract branch leaf (last `/` segment)
3. Check for collision with existing containers
4. On collision: prepend parent segment(s) until unique
5. Truncate to fit 24 chars (prefer repo, then branch)
6. Final collision fallback: append `-2`, `-3`

**Location:** `src/lib/container.sh:313` (`_containai_container_name`)

### Fix 2: Container Hostname

With short names, hostname = container name:
```bash
args+=(--hostname "$container_name")
```

**Location:** `src/lib/container.sh:2306`

### Fix 3: --fresh/--reset Wait for Ready

Add state flag during recreation:
```bash
touch "$_CONTAINAI_STATE_DIR/.container_recreating"
# ... recreate ...
rm -f "$_CONTAINAI_STATE_DIR/.container_recreating"
```

SSH functions check flag and wait gracefully.

### Migration

- Existing containers keep long names until `--fresh`
- Lookup order: saved config → legacy name → new short name

## Quick commands

```bash
# Test new naming
cai shell
hostname  # Shows: containai-main (or similar)

# Check names
docker ps --format "{{.Names}}" | head
```

## Acceptance

- [ ] New containers max 24 chars
- [ ] Format: `{repo}-{branch_leaf}`, no prefix, no hashes
- [ ] Branch uses last segment of `/` path
- [ ] Conflicts resolved by including parent segment
- [ ] Hostname matches container name
- [ ] Existing long-named containers still work
- [ ] --fresh waits for SSH-ready
- [ ] Docs updated

## References

- Container naming: `src/lib/container.sh:313`
- Container creation: `src/lib/container.sh:2306`
- Fresh/reset: `src/containai.sh:3254-3300`
