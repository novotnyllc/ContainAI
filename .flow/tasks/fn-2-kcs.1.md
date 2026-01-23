# fn-2-kcs.1: PR1 - aliases.sh cleanup and label fix

## Description

Clean up aliases.sh with consistent naming, add container label flag, and improve isolation detection output.

## File to Modify

- `agent-sandbox/aliases.sh` (660 lines)

## Changes Required

### 1. Variable Renames (5 variables)

| Line | Current | Target |
|------|---------|--------|
| 16 | `_CSD_IMAGE` | `_ASB_IMAGE` |
| 17 | `_CSD_LABEL` | `_ASB_LABEL` |
| 18 | `_CSD_SCRIPT_DIR` | `_ASB_SCRIPT_DIR` |
| 21-23 | `_CSD_VOLUMES` | `_ASB_VOLUMES` |

All references throughout the file must also be updated.

### 2. Remove Dead Code

- Lines 25-26: Delete `_CSD_MOUNT_ONLY_VOLUMES=()` declaration (unused empty array)

### 3. Function Renames (9 functions)

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

All function calls throughout the file must also be updated.

### 4. Comment Updates

| Line | Current | Change to |
|------|---------|-----------|
| 24 | "not created by csd" | "not created by asb" |
| 498 | "created by csd" | "created by asb" |
| 517 | "created by csd" | "created by asb" |
| 534 | "csd-managed" | "asb-managed" |

### 5. Branding Fix

- Line 608: Change `"Dotnet sandbox containers:"` to `"Agent Sandbox containers:"`

### 6. Add --label Flag to docker sandbox run

Add capability detection and `--label` flag (lines 568-580):

```bash
# Check if docker sandbox supports --label
if docker sandbox run --help 2>&1 | grep -q '\-\-label'; then
    args=(
        --name "$container_name"
        --label "$_ASB_LABEL"
        "${vol_args[@]}"
        "${detached_args[@]}"
        --template "$_ASB_IMAGE"
        claude
    )
else
    args=(
        --name "$container_name"
        "${vol_args[@]}"
        "${detached_args[@]}"
        --template "$_ASB_IMAGE"
        claude
    )
fi
```

### 7. Isolation Detection Rewrite

Replace `_csd_check_eci` with `_asb_check_isolation` using conservative detection:

```bash
_asb_check_isolation() {
    local runtime rootless info_output

    info_output=$(docker info --format '{{.DefaultRuntime}}\t{{.Rootless}}' 2>/dev/null)
    if [[ $? -ne 0 ]] || [[ -z "$info_output" ]]; then
        echo "[WARN] Unable to determine isolation status" >&2
        return 2
    fi

    IFS=$'\t' read -r runtime rootless <<< "$info_output"

    if [[ "$runtime" == "sysbox-runc" ]]; then
        echo "[OK] Isolation: sysbox-runc" >&2
        return 0
    fi
    if [[ "$rootless" == "true" ]]; then
        echo "[OK] Isolation: rootless mode" >&2
        return 0
    fi

    if [[ "$runtime" == "runc" ]] && [[ "$rootless" == "false" ]]; then
        echo "[WARN] No isolation detected (default runtime)" >&2
        return 1
    fi

    echo "[WARN] Unable to determine isolation status" >&2
    return 2
}
```

### 8. ASB_REQUIRE_ISOLATION Environment Variable

In preflight checks, if `ASB_REQUIRE_ISOLATION=1`:
- Return 0: proceed normally
- Return 1: fail with "ERROR: Container isolation required but not detected. Use --force to bypass."
- Return 2: fail with "ERROR: Cannot verify isolation status. Use --force to bypass."

When both `ASB_REQUIRE_ISOLATION=1` and `--force` are set, print warning then proceed:
```
*** WARNING: Bypassing isolation requirement with --force
*** Running without verified isolation may expose host system
```

### 9. Variable Hygiene

Use `local` for all temporary variables in functions (e.g., `local args=()`, `local status`).

## Testing

```bash
# Source and test basic functionality
source agent-sandbox/aliases.sh && asb --help

# Verify all variables/functions renamed
grep -E '_CSD_|_csd_' agent-sandbox/aliases.sh  # Should return nothing

# Test isolation output
_asb_check_isolation

# Test with require flag
ASB_REQUIRE_ISOLATION=1 _asb_check_isolation
```

## Acceptance

- [ ] All `_CSD_*` references removed (no compatibility layer needed)
- [ ] All `_CSD_*` variables renamed to `_ASB_*` (5 total)
- [ ] All `_csd_*` functions renamed to `_asb_*` (9 total)
- [ ] `_csd_check_eci` renamed to `_asb_check_isolation` with conservative detection
- [ ] Dead code `_CSD_MOUNT_ONLY_VOLUMES` removed
- [ ] All "csd" comments updated to "asb" (4 locations)
- [ ] "Dotnet sandbox containers:" changed to "Agent Sandbox containers:"
- [ ] `--label` flag added with capability detection via help output
- [ ] All temporary variables in functions declared with `local`
- [ ] Isolation detection uses tab-separated docker info output
- [ ] Isolation detection returns 2 for ambiguous cases
- [ ] Output uses ASCII-only markers ([OK], [WARN], [ERROR])
- [ ] `ASB_REQUIRE_ISOLATION=1` + `--force` prints bypass warning
- [ ] `grep -E '_CSD_|_csd_' agent-sandbox/aliases.sh` returns nothing
- [ ] `source aliases.sh && asb --help` works correctly

## Done summary
## Summary

Cleaned up aliases.sh: renamed _CSD_* to _ASB_*, _csd_* to _asb_*, added --label flag with capability detection, rewrote isolation detection, added local variable hygiene.

## Changes Made

1. **Variable Renames**: _CSD_IMAGE → _ASB_IMAGE, _CSD_LABEL → _ASB_LABEL, _CSD_SCRIPT_DIR → _ASB_SCRIPT_DIR, _CSD_VOLUMES → _ASB_VOLUMES
2. **Function Renames**: All 9 _csd_* functions renamed to _asb_* including _csd_check_eci → _asb_check_isolation
3. **Dead Code Removed**: _CSD_MOUNT_ONLY_VOLUMES (unused empty array)
4. **Comment Updates**: 4 "csd" references updated to "asb"
5. **Branding Fix**: "Dotnet sandbox containers:" → "Agent Sandbox containers:"
6. **--label Flag**: Added capability detection via help output with proper regex pattern
7. **Isolation Detection**: Conservative detection with return codes 0/1/2, ASCII markers
8. **ASB_REQUIRE_ISOLATION**: Environment variable support with --force bypass warning
9. **Variable Hygiene**: All temporary variables declared with local keyword
## Evidence
- Commits: c0c5972
- Tests: source agent-sandbox/aliases.sh && asb --help, grep -E '_CSD_|_csd_' agent-sandbox/aliases.sh # returns nothing
- PRs:
