# Silent by Default CLI Output

## Overview

Implement Unix CLI best practices for output handling. All commands should be silent by default (no informational messages), with `--verbose` flag to opt-in to status messages. This ensures piping works correctly and follows the Unix "Rule of Silence."

**Current behavior:** Commands emit info messages by default, requiring `--quiet|-q` to suppress.
**Target behavior:** Commands are silent by default, requiring `--verbose` to see info messages.

## Scope

**In scope:**
- Add `--verbose` flag to all commands (long form only - see Flag Conflicts below)
- Add `CONTAINAI_VERBOSE=1` environment variable support
- Modify `_cai_info()`, `_cai_step()`, `_cai_ok()` to respect verbose state
- Gate direct `[INFO]`/progress prints in all source files
- Keep `_cai_warn()` and `_cai_error()` always emitting (stderr, unconditionally)
- Remove `quiet` gating around warnings (warnings should always emit)
- Reset verbose state at start of each `containai()` invocation
- Add quiet state handling for `--quiet > --verbose > env` precedence
- Update help text and documentation

**Out of scope:**
- Verbosity levels (-v, -vv, -vvv) - defer to future
- Config file `verbose = true` - defer to future
- Deprecating existing `--quiet` flags - keep for backwards compatibility

**Exempt commands** (always emit output regardless of verbose):
- `doctor` - diagnostic tool, output is the point
- `help` / `--help` - output is the point
- `version` / `--version` - output is the point

## Flag Conflicts

The `-v` short flag has existing uses:
- Top-level: `-v` = `--version` (in `containai()` dispatch)
- `run`/`shell`: `-v` may be parsed as volume (Docker convention)

**Resolution:** Use `--verbose` long form only. Do NOT add `-v` as verbose shorthand. This avoids ambiguity and maintains backwards compatibility.

## Precedence Rules

When multiple verbosity controls are specified:
1. `--quiet` overrides everything (sets `_CAI_QUIET=1`, suppresses info/step/ok)
2. `--verbose` takes next priority (sets `_CAI_VERBOSE=1`, enables info/step/ok)
3. `CONTAINAI_VERBOSE=1` env var is default fallback

Implementation:
```bash
_cai_is_verbose() {
    [[ "${_CAI_QUIET:-}" == "1" ]] && return 1  # --quiet wins
    [[ "${_CAI_VERBOSE:-}" == "1" ]] || [[ "${CONTAINAI_VERBOSE:-}" == "1" ]]
}
```

Warnings and errors always emit to stderr regardless of verbosity settings.

## Commands to Update

All commands that parse arguments need `--verbose` support. Complete list from actual codebase:

**Top-level commands:**
- `run`, `shell`, `stop`, `exec`
- `import`, `export`, `setup`, `uninstall`, `update`
- `validate`, `sandbox`

**Subcommands:**
- `ssh cleanup`
- `config list`, `config get`, `config set`, `config unset`
- `links check`, `links fix`
- `completion bash`, `completion zsh`

**Passthrough command (special handling):**
- `docker` - This passes through to Docker. Do NOT intercept `--verbose`. The command itself should not emit ContainAI info messages (already silent).

**Exempt (no --verbose needed, auto-enable verbose internally):**
- `doctor`, `help`, `--help`, `version`, `--version`

## Files Requiring Audit

All files with direct `[INFO]`/progress output need gating:
- `src/containai.sh` - main CLI
- `src/lib/core.sh` - logging functions (primary change)
- `src/lib/ssh.sh` - SSH connection messages
- `src/lib/container.sh` - container lifecycle
- `src/lib/import.sh` - import progress
- `src/lib/export.sh` - export progress
- `src/lib/setup.sh` - setup progress
- `src/lib/config.sh` - config messages
- `src/lib/links.sh` - links messages
- `src/lib/env.sh` - environment messages
- `src/lib/version.sh` - version/update messages
- `src/lib/uninstall.sh` - uninstall messages
- `src/lib/doctor.sh` - diagnostic messages (exempt, always verbose)

## Approach

1. Add global verbose/quiet state to `src/lib/core.sh`:
   ```bash
   _CAI_VERBOSE=""  # Reset each invocation
   _CAI_QUIET=""    # Reset each invocation

   _cai_set_verbose() { _CAI_VERBOSE=1; }
   _cai_set_quiet() { _CAI_QUIET=1; }

   _cai_is_verbose() {
       [[ "${_CAI_QUIET:-}" == "1" ]] && return 1
       [[ "${_CAI_VERBOSE:-}" == "1" ]] || [[ "${CONTAINAI_VERBOSE:-}" == "1" ]]
   }
   ```

2. Modify logging functions to check verbose state:
   ```bash
   _cai_info() {
       _cai_is_verbose || return 0
       printf '[INFO] %s\n' "$*" >&2
   }

   _cai_ok() {
       _cai_is_verbose || return 0
       printf '[OK] %s\n' "$*" >&2
   }

   _cai_step() {
       _cai_is_verbose || return 0
       printf '-> %s\n' "$*" >&2
   }
   ```
   Note: Output goes to stderr for pipe safety.

3. At start of `containai()` function, reset state:
   ```bash
   _CAI_VERBOSE=""
   _CAI_QUIET=""
   ```

4. Add `--verbose` flag parsing to each command's argument loop

5. Audit and gate direct `[INFO]` prints in all lib files:
   - Replace `echo "[INFO] ..."` with `_cai_info "..."`
   - Or wrap in `if _cai_is_verbose; then ... fi`

6. Remove `quiet` gating around warnings:
   - Find: `if [[ "$quiet" != "true" ]]; then _cai_warn`
   - Replace: unconditional `_cai_warn`

## Quick commands

```bash
# Test silent default (shell command triggers SSH connect message)
cai shell /tmp/test 2>&1 | grep -c "INFO\|Connecting"  # Should be 0

# Test verbose mode
cai shell /tmp/test --verbose 2>&1 | grep -c "Connecting"  # Should be 1

# Test env var
CONTAINAI_VERBOSE=1 cai shell /tmp/test 2>&1 | grep -c "Connecting"  # Should be 1

# Test precedence: --quiet beats env var
CONTAINAI_VERBOSE=1 cai shell /tmp/test --quiet 2>&1 | grep -c "Connecting"  # Should be 0

# Lint
shellcheck -x src/*.sh src/lib/*.sh
```

## Risks & Dependencies

**Breaking change:** Scripts parsing `[INFO]` lines from stdout/stderr will break. Acceptable per user request.

**Dependency:** fn-36-rb7 (CLI UX Consistency) already added `--verbose` to some commands. This work builds on that foundation.

## Acceptance

- [ ] All commands accept `--verbose` flag (long form only, no `-v`)
- [ ] `CONTAINAI_VERBOSE=1` environment variable works
- [ ] Default output is silent (no info/step/ok messages)
- [ ] Errors and warnings always emit to stderr (never gated by `quiet`)
- [ ] `doctor`, `help`, `version` commands unaffected
- [ ] Verbose state is reset at start of each invocation
- [ ] Direct `[INFO]` prints in all lib files are gated
- [ ] Precedence works: --quiet > --verbose > CONTAINAI_VERBOSE
- [ ] `docker` passthrough does not intercept --verbose
- [ ] Documentation updated (help text, README, AGENTS.md)
- [ ] shellcheck passes

## References

- Unix Rule of Silence: http://www.catb.org/esr/writings/taoup/html/ch11s09.html
- CLI Guidelines: https://clig.dev/
- GNU Option Table: https://www.gnu.org/prep/standards/html_node/Option-Table.html
- Current logging: `src/lib/core.sh:55-84`
- Current shell/exec SSH messages: `src/lib/ssh.sh` (_cai_ssh_shell, _cai_ssh_run)
