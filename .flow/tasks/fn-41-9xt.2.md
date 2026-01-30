# fn-41-9xt.2 Add --verbose flag to CLI commands

## Description
Add `--verbose` flag parsing to all CLI commands in `src/containai.sh` and call `_cai_set_verbose` when flag is present. **Long form only** - do NOT add `-v` short form due to conflicts with `--version` and `--volume`.

**Size:** L
**Files:** `src/containai.sh`

## Flag Conflict Avoidance

The `-v` short flag has existing uses:
- Top-level: `-v` = `--version` (in `containai()` dispatch)
- `run`/`shell`: `-v` may conflict with Docker `-v` volume convention

**Resolution:** Use `--verbose` long form only throughout. Do NOT add `-v` as verbose shorthand.

## Approach

1. At start of `containai()` function, reset verbose/quiet state: `_CAI_VERBOSE="" _CAI_QUIET=""`
2. Add `--verbose)` case (long form only) to argument parsing in each command function
3. Call `_cai_set_verbose` when flag is detected
4. Existing `--quiet` flags should call `_cai_set_quiet`
5. Update help text for each command to document `--verbose`
6. Ensure exempt commands (`doctor`, `help`, `version`) call `_cai_set_verbose` unconditionally

Commands to update (actual codebase commands):

**Top-level commands:**
- `run` - container creation
- `shell` - shell into container
- `stop` - stop container
- `exec` - execute command in container
- `import` - sync configs
- `export` - export volume
- `setup` - initial setup
- `uninstall` - remove containai
- `update` - update containai
- `validate` - validate config
- `sandbox` - run sandboxed command

**Subcommands:**
- `ssh cleanup` - cleanup SSH keys
- `config list`, `config get`, `config set`, `config unset` - config management
- `links check`, `links fix` - symlinks management
- `completion bash`, `completion zsh` - shell completions

**Passthrough (DO NOT intercept --verbose):**
- `docker` - passes through to Docker; do not intercept flags

**Exempt (auto-enable verbose, no flag needed):**
- `doctor` - diagnostic tool
- `help` / `--help` - output is the point
- `version` / `--version` - output is the point

Follow existing pattern at `src/containai.sh:3374-3380` for flag parsing.

## Key context

Some commands already have `--verbose` flag but with `verbose_flag=false` default. These need to call `_cai_set_verbose` instead of using local boolean.

The verbose/quiet state must be reset at the start of each `containai()` invocation to prevent state leaking between commands in sourced/dev mode.

## Acceptance
- [ ] All main commands accept `--verbose` flag (long form only, NO `-v`)
- [ ] `--verbose` flag calls `_cai_set_verbose`
- [ ] Existing `--quiet` flags call `_cai_set_quiet`
- [ ] Verbose/quiet state is reset at start of `containai()`: `_CAI_VERBOSE="" _CAI_QUIET=""`
- [ ] `doctor` command auto-enables verbose
- [ ] `docker` passthrough does NOT intercept `--verbose`
- [ ] Help text for each command documents `--verbose`
- [ ] Main help text updated with `--verbose` description
- [ ] shellcheck passes on containai.sh
## Done summary
# fn-41-9xt.2: Add --verbose flag to CLI commands

## Summary

Added `--verbose` flag (long form only) to all CLI commands in `src/containai.sh` and updated supporting library files. Each command now calls `_cai_set_verbose` when the flag is present, integrating with the centralized verbose state in `src/lib/core.sh`.

## Changes Made

### State Management
- Added verbose/quiet state reset at start of `containai()` function: `_CAI_VERBOSE="" _CAI_QUIET=""`
- All `--verbose` flag handlers now call `_cai_set_verbose`
- All `--quiet` flag handlers now call `_cai_set_quiet`

### Commands Updated in `src/containai.sh`
- `run` - Added `_cai_set_verbose` and `_cai_set_quiet` calls
- `shell` - Added `_cai_set_verbose` and `_cai_set_quiet` calls
- `exec` - Added `_cai_set_verbose` and `_cai_set_quiet` calls
- `stop` - Added `--verbose` flag parsing with `_cai_set_verbose`
- `import` - Changed from `--verbose|-v` to `--verbose` only, added `_cai_set_verbose`
- `export` - Added `--verbose` flag with `_cai_set_verbose`
- `ssh cleanup` - Added `--verbose` flag with `_cai_set_verbose`
- `config list/get/set/unset` - Added `--verbose` flag with `_cai_set_verbose`
- `links check` - Added `--verbose` flag and updated `--quiet` to call `_cai_set_quiet`
- `links fix` - Added `--verbose` flag and updated `--quiet` to call `_cai_set_quiet`
- `doctor` - Added auto-enable verbose at start (exempt command - diagnostic tool)

### Commands Updated in Library Files
- `src/lib/container.sh`: `_containai_start_container` - Added `_cai_set_verbose` and `_cai_set_quiet` calls
- `src/lib/setup.sh`: `_cai_setup` - Changed from `--verbose|-v` to `--verbose` only, added `_cai_set_verbose`
- `src/lib/setup.sh`: `_cai_secure_engine_validate` - Changed from `--verbose|-v` to `--verbose` only, added `_cai_set_verbose`
- `src/lib/update.sh`: `_cai_update` - Changed from `--verbose|-v` to `--verbose` only, added `_cai_set_verbose`
- `src/lib/uninstall.sh`: `_cai_uninstall` - Added `--verbose` flag with `_cai_set_verbose`

### Help Text Updates
- Updated help text for: stop, exec, export, ssh cleanup, config, links, uninstall, update, validate
- Removed `-v` shorthand from import help text
- Added `--verbose` documentation to all relevant commands

### Zsh Completion Updates
- Removed `-v` shorthand from verbose completion entries (setup, update, validate)

### Not Modified (per spec)
- `docker` passthrough - Does not intercept `--verbose`
- `doctor`, `help`, `version` - Exempt commands, auto-enable verbose

## Verification

```bash
shellcheck -x src/containai.sh src/lib/core.sh src/lib/container.sh src/lib/setup.sh src/lib/update.sh src/lib/uninstall.sh
# Passes with no errors
```
## Evidence
- Commits:
- Tests:
- PRs:
