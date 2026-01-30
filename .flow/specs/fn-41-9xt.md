# Silent by Default CLI Output

## Overview

Implement Unix CLI best practices for output handling. All commands should be silent by default (no informational messages), with `--verbose|-v` flag to opt-in to status messages. This ensures piping works correctly and follows the Unix "Rule of Silence."

**Current behavior:** Commands emit info messages by default, requiring `--quiet|-q` to suppress.
**Target behavior:** Commands are silent by default, requiring `--verbose|-v` to see info messages.

## Scope

**In scope:**
- Add `--verbose|-v` flag to all commands
- Add `CONTAINAI_VERBOSE=1` environment variable support
- Modify `_cai_info()`, `_cai_step()`, `_cai_ok()` to respect verbose state
- Keep `_cai_warn()` and `_cai_error()` always emitting (stderr)
- Update help text and documentation

**Out of scope:**
- Verbosity levels (-v, -vv, -vvv) - defer to future
- Config file `verbose = true` - defer to future
- Deprecating existing `--quiet` flags - keep for backwards compatibility

**Exempt commands** (always emit output regardless of verbose):
- `doctor` - diagnostic tool, output is the point
- `help` / `--help` - output is the point
- `version` / `--version` - output is the point

## Approach

1. Add global verbose state to `src/lib/core.sh`
2. Modify logging functions to check `_CAI_VERBOSE` variable
3. Add `--verbose|-v` flag parsing to each command
4. Support `CONTAINAI_VERBOSE=1` environment variable
5. Update documentation

Pattern to follow (from `src/lib/core.sh:75-79` debug pattern):
```bash
_cai_debug() {
    [[ "${CONTAINAI_DEBUG:-}" == "1" ]] || return 0
    printf '[DEBUG] %s\n' "$*" >&2
}
```

## Quick commands

```bash
# Test silent default
cai ssh mycontainer 2>&1 | grep -c "INFO\|Connecting"  # Should be 0

# Test verbose mode
cai ssh mycontainer --verbose 2>&1 | grep -c "Connecting"  # Should be 1

# Test env var
CONTAINAI_VERBOSE=1 cai ssh mycontainer 2>&1 | grep -c "Connecting"  # Should be 1

# Lint
shellcheck -x src/*.sh src/lib/*.sh
```

## Risks & Dependencies

**Breaking change:** Scripts parsing `[INFO]` lines from stdout/stderr will break. Acceptable per user request.

**Dependency:** fn-36-rb7 (CLI UX Consistency) already added `--verbose` to some commands. This work builds on that foundation.

## Acceptance

- [ ] All commands accept `--verbose|-v` flag
- [ ] `CONTAINAI_VERBOSE=1` environment variable works
- [ ] Default output is silent (no info/step/ok messages)
- [ ] Errors and warnings still emit to stderr
- [ ] `doctor`, `help`, `version` commands unaffected
- [ ] Documentation updated (help text, README, AGENTS.md)
- [ ] shellcheck passes

## References

- Unix Rule of Silence: http://www.catb.org/esr/writings/taoup/html/ch11s09.html
- CLI Guidelines: https://clig.dev/
- GNU Option Table: https://www.gnu.org/prep/standards/html_node/Option-Table.html
- Current logging: `src/lib/core.sh:55-84`
- Current SSH messages: `src/lib/ssh.sh:1877-1878`
