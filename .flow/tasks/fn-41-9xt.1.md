# fn-41-9xt.1 Add verbose state to core logging functions

## Description
Add global verbose state management to `src/lib/core.sh` and modify logging functions to respect it.

**Size:** M
**Files:** `src/lib/core.sh`

## Approach

1. Add `_CAI_VERBOSE` global variable (default: empty/false)
2. Add `_cai_set_verbose()` function to set state
3. Modify `_cai_info()` to check `_CAI_VERBOSE` before emitting
4. Modify `_cai_step()` to check `_CAI_VERBOSE` before emitting
5. Modify `_cai_ok()` to check `_CAI_VERBOSE` before emitting
6. Support `CONTAINAI_VERBOSE=1` environment variable (like `CONTAINAI_DEBUG`)
7. Keep `_cai_warn()` and `_cai_error()` unchanged (always emit to stderr)

Follow pattern at `src/lib/core.sh:75-79` for `_cai_debug()`.

## Key context

The codebase already has `CONTAINAI_DEBUG=1` pattern. Use same style:
```bash
_cai_info() {
    [[ "${_CAI_VERBOSE:-}" == "1" || "${CONTAINAI_VERBOSE:-}" == "1" ]] || return 0
    printf '[INFO] %s\n' "$*"
}
```
## Acceptance
- [ ] `_CAI_VERBOSE` global variable exists
- [ ] `_cai_set_verbose()` function sets `_CAI_VERBOSE=1`
- [ ] `_cai_info()` only emits when verbose is set
- [ ] `_cai_step()` only emits when verbose is set
- [ ] `_cai_ok()` only emits when verbose is set
- [ ] `CONTAINAI_VERBOSE=1` environment variable works
- [ ] `_cai_warn()` and `_cai_error()` still always emit
- [ ] shellcheck passes on core.sh
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
