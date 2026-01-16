# Agent Sandbox Refactor: Image Size & Aliases Cleanup

## Problem

The agent-sandbox project has several issues requiring cleanup:

1. **Naming inconsistency**: Variables use `_CSD_` prefix, functions use `_csd_`, comments reference old "csd" naming
2. **Missing container labels**: `docker sandbox run` doesn't pass `--label` flag for container identification
3. **Docker image could be smaller**: No layer optimization, caches left in image
4. **Build script limitations**: No CLI options for DOTNET_CHANNEL or base image, no OCI labels
5. **Stale documentation**: README.md, sync-all.sh, and other files have "csd" / "dotnet-sandbox" references

## Approach

Split into **3 PRs** (merging Dockerfile changes to avoid conflicts):

### PR 1: aliases.sh Cleanup (fn-2-kcs.1)

**Renaming:**
- Rename `_CSD_*` variables to `_ASB_*` (5 variables, lines 16-26)
- Rename `_csd_*` functions to `_asb_*` (9 functions)
- Remove dead code: `_CSD_MOUNT_ONLY_VOLUMES` array (lines 25-26)
- Update comments referencing "csd" to "asb" (4 locations)
- Fix branding: "Dotnet sandbox" → "Agent Sandbox" (line 608)

**Label flag with capability detection:**
- Check if `docker sandbox run --help 2>&1 | grep -q '\-\-label'`
- Only add `--label "$_ASB_LABEL"` when supported
- Gracefully proceed without it otherwise (keeping existing ambiguous ownership messaging)

**Variable hygiene:**
- Use `local` for all temporary variables in functions (e.g., `local args=()`, `local status`, etc.)

**Isolation Detection (renamed from ECI check):**

The function `_asb_check_isolation` will query `docker info` and return:

Detection logic (conservative - prefer return 2 over false positive/negative):
```bash
local runtime rootless
local info_output

# Query docker info with tab-separated fields for reliable parsing
info_output=$(docker info --format '{{.DefaultRuntime}}\t{{.Rootless}}' 2>/dev/null)
if [[ $? -ne 0 ]] || [[ -z "$info_output" ]]; then
  return 2  # Unable to query
fi

# Parse tab-separated values
IFS=$'\t' read -r runtime rootless <<< "$info_output"

# Return 0 only for unambiguous isolation
if [[ "$runtime" == "sysbox-runc" ]]; then return 0; fi
if [[ "$rootless" == "true" ]]; then return 0; fi

# Return 1 only for unambiguous non-isolation
if [[ "$runtime" == "runc" ]] && [[ "$rootless" == "false" ]]; then return 1; fi

# Everything else is ambiguous
return 2
```

Note: `userns` in SecurityOptions is not reliably indicative; omitted from detection.

Output (ASCII-only):
- `[OK] Isolation: sysbox-runc`
- `[OK] Isolation: rootless mode`
- `[WARN] No isolation detected (default runtime)`
- `[WARN] Unable to determine isolation status`

**`ASB_REQUIRE_ISOLATION=1` behavior:**
- On return 0: proceed normally
- On return 1: fail with "ERROR: Container isolation required but not detected. Use --force to bypass (not recommended)."
- On return 2: fail with "ERROR: Cannot verify isolation status. Use --force to bypass (not recommended)."

**`--force` interaction with `ASB_REQUIRE_ISOLATION`:**
When both are set, print ASCII warning:
```
*** WARNING: Bypassing isolation requirement with --force
*** Running without verified isolation may expose host system
```
Then proceed.

Precedence: `--force` overrides `ASB_REQUIRE_ISOLATION`. Existing `--force` behavior (skip sandbox checks) remains unchanged; this adds isolation bypass.

### PR 2: Dockerfile & Build Pipeline (fn-2-kcs.2)

**Prerequisites:**
1. Fix line continuation issues (trailing spaces after backslashes on lines 30, 127, 133)
2. Verify Dockerfile builds successfully before optimization

**Baseline Capture:**
Build script captures single tag size with explicit handling for missing image:
```bash
# Capture baseline (latest tag only)
BASELINE_SIZE=$(docker images agent-sandbox:latest --format '{{.Size}}' 2>/dev/null | head -1)
if [[ -z "$BASELINE_SIZE" ]]; then
  echo "=== Baseline: (no existing image - size reduction target N/A for first build) ==="
  HAVE_BASELINE=0
else
  echo "=== Baseline: $BASELINE_SIZE ==="
  HAVE_BASELINE=1
fi

# ... build ...

# Capture result (should always exist after build)
RESULT_SIZE=$(docker images agent-sandbox:latest --format '{{.Size}}' | head -1)
if [[ -z "$RESULT_SIZE" ]]; then
  echo "ERROR: Build did not produce agent-sandbox:latest"
  exit 1
fi
echo "=== Result: $RESULT_SIZE ==="

if [[ "$HAVE_BASELINE" == "1" ]]; then
  echo "=== Manual verification: compare baseline vs result for >=10% reduction ==="
else
  echo "=== First build complete. Run again to measure size reduction. ==="
fi
```
Note: Size is human-readable (e.g., "2.5GB"); manual comparison required. First build has no reduction target.

**Image Size Reduction:**
- **Target**: Reduce image size by >=10% from baseline (verify manually; skip for first build)
- Remove on-image caches/artifacts in same RUN layer:
  - `rm -rf /var/lib/apt/lists/*` after apt-get (already present line 58)
  - `rm -rf ~/.npm ~/.cache ~/.nvm/.cache` after npm/nvm operations
  - `rm -rf /tmp/* /var/tmp/*` after tool installs
  - Clear dotnet NuGet cache: `dotnet nuget locals all --clear`
- Combine related RUN commands to minimize layer count where logical
- BuildKit cache mounts as secondary improvement (for rebuild speed, not size)

**Build Script Enhancements:**

`--dotnet-channel` option:
- Pass value to existing `DOTNET_CHANNEL` ARG in Dockerfile
- Default: `10.0` (matching current Dockerfile default)

`--base-image` option:
- Add `ARG BASE_IMAGE=docker/sandbox-templates:claude-code` as first line after syntax comment
- Change `FROM` line to `FROM ${BASE_IMAGE}`
- build.sh passes `--build-arg BASE_IMAGE=<value>` when option provided
- Default: `docker/sandbox-templates:claude-code` (current base)
- Document: "Changing base image is advanced; ensure sandbox compatibility"

**OCI Labels Implementation:**
Add to Dockerfile after FROM:
```dockerfile
ARG BUILD_DATE
ARG VCS_REF
ARG VERSION=1.0.0

LABEL org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.source="https://github.com/clairernovotny/agent-sandbox" \
      org.opencontainers.image.title="agent-sandbox" \
      org.opencontainers.image.description="Sandboxed development environment for AI agents"
```

build.sh passes:
```bash
--build-arg BUILD_DATE="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
--build-arg VCS_REF="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
```

Fix stale comment: "dotnet-sandbox" → "agent-sandbox" (line 7)

**Verification:**
```bash
./build.sh  # Outputs baseline and result sizes
docker history agent-sandbox:latest  # Confirm layer optimization
docker inspect agent-sandbox:latest --format '{{json .Config.Labels}}' | jq  # Verify OCI labels
```

### PR 3: Documentation Update (fn-2-kcs.3)

**Scope: All user-facing strings and volume names.**

**Breaking Change**: Renaming volumes will orphan existing Docker volumes. Users with existing data must manually migrate.

**Volumes to rename:**
| Old Name | New Name | Used By |
|----------|----------|---------|
| `dotnet-sandbox-vscode` | `agent-sandbox-vscode` | sync-all.sh (VS Code settings) |
| `dotnet-sandbox-nuget` | `agent-sandbox-nuget` | README.md (NuGet cache) |
| `dotnet-sandbox-gh` | `agent-sandbox-gh` | sync-all.sh (GitHub CLI config) |

**Unchanged volumes:**
| Volume | Reason |
|--------|--------|
| `sandbox-agent-data` | Already uses correct naming (in `_CSD_VOLUMES` array) |
| `docker-claude-sandbox-data` | Different naming pattern (Claude credentials volume) |
| `docker-claude-plugins` | Different naming pattern (Claude plugins volume) |

```bash
# Manual migration (if needed):
for vol in vscode nuget gh; do
  docker volume create "agent-sandbox-$vol"
  docker run --rm -v "dotnet-sandbox-$vol:/from" -v "agent-sandbox-$vol:/to" alpine sh -c "cp -a /from/. /to/"
done
# Then remove old volumes: docker volume rm dotnet-sandbox-vscode dotnet-sandbox-nuget dotnet-sandbox-gh
```
No automatic migration is provided - backward compatibility is explicitly not required.

**Updates:**
- README.md: all "csd" → "asb" command references
- README.md: all "dotnet-sandbox" → "agent-sandbox" (including volume names)
- sync-all.sh: user-facing output strings referencing "csd"
- `_ASB_VOLUMES` array: rename `dotnet-sandbox-*` to `agent-sandbox-*`
- Search and review:
  ```bash
  # Find all csd references
  rg "\bcsd\b" --type-add 'docs:*.md' --type-add 'scripts:*.sh'

  # Find all dotnet-sandbox references (all should be renamed)
  rg "dotnet-sandbox"
  ```
- Clarify that `_ASB_LABEL` identifies containers as "managed by asb" (not per-user ownership)
- Manual review of each hit before changing

## Research Findings

### aliases.sh Analysis (660 lines)
**Variables to rename:**
| Line | Current | Target |
|------|---------|--------|
| 16 | `_CSD_IMAGE` | `_ASB_IMAGE` |
| 17 | `_CSD_LABEL` | `_ASB_LABEL` |
| 18 | `_CSD_SCRIPT_DIR` | `_ASB_SCRIPT_DIR` |
| 21-23 | `_CSD_VOLUMES` | `_ASB_VOLUMES` |
| 25-26 | `_CSD_MOUNT_ONLY_VOLUMES` | **REMOVE** |

**Functions to rename:**
| Line | Current | Target |
|------|---------|--------|
| 30 | `_csd_container_name` | `_asb_container_name` |
| 94 | `_csd_check_eci` | `_asb_check_isolation` |
| 128 | `_csd_check_sandbox` | `_asb_check_sandbox` |
| 230 | `_csd_preflight_checks` | `_asb_preflight_checks` |
| 251 | `_csd_get_container_label` | `_asb_get_container_label` |
| 257 | `_csd_get_container_image` | `_asb_get_container_image` |
| 265 | `_csd_is_our_container` | `_asb_is_our_container` |
| 292 | `_csd_check_container_ownership` | `_asb_check_container_ownership` |
| 333 | `_csd_ensure_volumes` | `_asb_ensure_volumes` |

### Dockerfile Analysis (161 lines)
- Base image: `docker/sandbox-templates:claude-code`
- Already has `DOTNET_CHANNEL` ARG defaulting to `10.0` (line 77)
- Already has `# syntax=docker/dockerfile:1` for BuildKit
- Partial cleanup exists (line 58, 83, 99)
- **Known issue**: Trailing spaces after backslash on lines 30, 127, 133
- Missing: consolidated cleanup, OCI labels, BASE_IMAGE ARG

### build.sh Analysis (33 lines)
- No CLI options, just passes `$@` to docker build
- Stale comment on line 7

## Quick commands

```bash
# Pre-work: Check for external variable references
rg "_CSD_" --type sh

# Test aliases after changes
source agent-sandbox/aliases.sh && asb --help

# Build with size tracking
cd agent-sandbox && ./build.sh  # Shows baseline and result in output

# Check image layers
docker history agent-sandbox:latest

# Verify OCI labels
docker inspect agent-sandbox:latest --format '{{json .Config.Labels}}' | jq

# Search for remaining references (all should be renamed)
rg "\bcsd\b"
rg "dotnet-sandbox"
```

## Task Dependencies

```
fn-2-kcs.1 (PR1: aliases.sh)
    └── fn-2-kcs.3 (PR3: docs - depends on new command names)

fn-2-kcs.2 (PR2: Dockerfile + build.sh - independent)
```

## Acceptance

**PR 1:**
- [ ] All `_CSD_*` references removed (no compatibility layer needed)
- [ ] All `_CSD_*` variables renamed to `_ASB_*` in aliases.sh
- [ ] All `_csd_*` functions renamed to `_asb_*` in aliases.sh
- [ ] `_csd_check_eci` renamed to `_asb_check_isolation` with conservative detection
- [ ] Dead code `_CSD_MOUNT_ONLY_VOLUMES` removed
- [ ] Comments updated from "csd" to "asb"
- [ ] "Dotnet sandbox" branding fixed to "Agent Sandbox"
- [ ] `--label` flag added with capability detection via help output
- [ ] All temporary variables in functions declared with `local`
- [ ] Isolation detection uses tab-separated docker info output
- [ ] Isolation detection returns 2 for ambiguous cases (not false positive)
- [ ] Output uses ASCII-only markers ([OK], [WARN], [ERROR])
- [ ] `ASB_REQUIRE_ISOLATION=1` + `--force` prints ASCII bypass warning

**PR 2:**
- [ ] Dockerfile line continuations fixed (lines 30, 127, 133)
- [ ] Build script handles missing baseline with explicit message and skips reduction target
- [ ] Build script outputs baseline and result sizes for :latest tag
- [ ] Build script errors if result image missing after build
- [ ] `ARG BASE_IMAGE=docker/sandbox-templates:claude-code` added before FROM
- [ ] FROM uses `${BASE_IMAGE}`
- [ ] Image size reduced by >=10% from baseline (manual verification; skip for first build)
- [ ] `docker history` confirms layer optimization
- [ ] `--dotnet-channel` option works (default: 10.0)
- [ ] `--base-image` option works (default: docker/sandbox-templates:claude-code)
- [ ] OCI ARGs (BUILD_DATE, VCS_REF, VERSION) declared in Dockerfile
- [ ] OCI labels with correct source URL present
- [ ] build.sh passes BUILD_DATE and VCS_REF at build time
- [ ] `docker inspect` shows correct OCI labels

**PR 3:**
- [ ] README.md updated with "asb" command references
- [ ] README.md updated with "agent-sandbox" project references
- [ ] Volume names renamed from `dotnet-sandbox-*` to `agent-sandbox-*`
- [ ] sync-all.sh output strings updated
- [ ] Each `rg "\bcsd\b"` hit manually reviewed and resolved
- [ ] Each `rg "dotnet-sandbox"` hit manually reviewed and resolved
