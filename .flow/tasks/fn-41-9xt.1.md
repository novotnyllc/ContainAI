# fn-41-9xt.1 Add verbose state to core logging functions

## Description
Add global verbose and quiet state management to `src/lib/core.sh` and modify logging functions to respect it.

**Size:** M
**Files:** `src/lib/core.sh`

## Approach

1. Add `_CAI_VERBOSE` global variable (default: empty/false)
2. Add `_CAI_QUIET` global variable (default: empty/false) for precedence handling
3. Add `_cai_set_verbose()` function to set verbose state
4. Add `_cai_set_quiet()` function to set quiet state
5. Add `_cai_is_verbose()` helper function that implements precedence:
   - Returns false if `_CAI_QUIET=1` (--quiet wins)
   - Returns true if `_CAI_VERBOSE=1` or `CONTAINAI_VERBOSE=1`
6. Modify `_cai_info()` to check verbose state before emitting (output to stderr)
7. Modify `_cai_step()` to check verbose state before emitting (output to stderr)
8. Modify `_cai_ok()` to check verbose state before emitting (output to stderr)
9. Keep `_cai_warn()` and `_cai_error()` unchanged (always emit to stderr, unconditionally)

Follow pattern at `src/lib/core.sh:75-79` for `_cai_debug()`.

## Key context

The codebase already has `CONTAINAI_DEBUG=1` pattern. Use same style:
```bash
_CAI_VERBOSE=""
_CAI_QUIET=""

_cai_set_verbose() { _CAI_VERBOSE=1; }
_cai_set_quiet() { _CAI_QUIET=1; }

_cai_is_verbose() {
    [[ "${_CAI_QUIET:-}" == "1" ]] && return 1  # --quiet wins
    [[ "${_CAI_VERBOSE:-}" == "1" ]] || [[ "${CONTAINAI_VERBOSE:-}" == "1" ]]
}

_cai_info() {
    _cai_is_verbose || return 0
    printf '[INFO] %s\n' "$*" >&2
}
```

Note: Verbose output goes to stderr (not stdout) for pipe safety. Update the header comments in core.sh to reflect this change.

## Acceptance
- [ ] `_CAI_VERBOSE` global variable exists
- [ ] `_CAI_QUIET` global variable exists
- [ ] `_cai_set_verbose()` function sets `_CAI_VERBOSE=1`
- [ ] `_cai_set_quiet()` function sets `_CAI_QUIET=1`
- [ ] `_cai_is_verbose()` helper implements precedence (quiet > verbose > env)
- [ ] `_cai_info()` only emits when verbose is set, outputs to stderr
- [ ] `_cai_step()` only emits when verbose is set, outputs to stderr
- [ ] `_cai_ok()` only emits when verbose is set, outputs to stderr
- [ ] `CONTAINAI_VERBOSE=1` environment variable works
- [ ] `_cai_warn()` and `_cai_error()` still always emit (unconditionally)
- [ ] Header comments in core.sh updated to document stderr for info/step/ok
- [ ] shellcheck passes on core.sh
## Done summary
## Summary

Added verbose state management to `src/lib/core.sh`:

1. **Global variables added:**
   - `_CAI_VERBOSE=""` - tracks verbose state
   - `_CAI_QUIET=""` - tracks quiet state

2. **Functions added:**
   - `_cai_set_verbose()` - sets `_CAI_VERBOSE=1`
   - `_cai_set_quiet()` - sets `_CAI_QUIET=1`
   - `_cai_is_verbose()` - returns true if verbose output enabled, respects precedence

3. **Logging functions modified:**
   - `_cai_info()` - now checks `_cai_is_verbose()` before emitting, outputs to stderr
   - `_cai_ok()` - now checks `_cai_is_verbose()` before emitting, outputs to stderr
   - `_cai_step()` - now checks `_cai_is_verbose()` before emitting, outputs to stderr

4. **Precedence implemented:**
   - `_CAI_QUIET=1` overrides everything (--quiet wins)
   - `_CAI_VERBOSE=1` enables verbose output (--verbose)
   - `CONTAINAI_VERBOSE=1` env var fallback

5. **Header comments updated** to document:
   - stderr output for info/step/ok
   - New functions added
   - Verbosity precedence rules
## Evidence
- Commits:
- Tests: Verified default silent behavior - info/ok/step do not emit without verbose, Verified _cai_set_verbose() enables output, Verified _cai_set_quiet() overrides verbose, Verified _cai_warn() and _cai_error() always emit, Verified CONTAINAI_VERBOSE=1 env var enables output, Verified all output goes to stderr, shellcheck passes on src/lib/core.sh
- PRs:
