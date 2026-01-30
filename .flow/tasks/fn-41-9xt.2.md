# fn-41-9xt.2 Add --verbose flag to CLI commands

## Description
Add `--verbose|-v` flag parsing to all CLI commands in `src/containai.sh` and call `_cai_set_verbose` when flag is present.

**Size:** M
**Files:** `src/containai.sh`

## Approach

1. Add `--verbose|-v)` case to argument parsing in each command function
2. Call `_cai_set_verbose` when flag is detected
3. Update help text for each command to document `--verbose`
4. Ensure exempt commands (`doctor`, `help`, `version`) call `_cai_set_verbose` unconditionally

Commands to update:
- `shell` (line ~2600)
- `exec` (line ~3272)
- `run` (line ~1269 in container.sh)
- `ssh` (handled via ssh.sh)
- `import` (line ~252)
- `export` (line ~327)
- `stop` (line ~357)
- `setup`
- `update`
- `status`
- `links`
- `cleanup`

Follow existing pattern at `src/containai.sh:3374-3380` for flag parsing.

## Key context

Some commands already have `--verbose` flag but with `verbose_flag=false` default. These need to call `_cai_set_verbose` instead of using local boolean.
## Acceptance
- [ ] All main commands accept `--verbose|-v` flag
- [ ] `--verbose` flag calls `_cai_set_verbose`
- [ ] `doctor` command auto-enables verbose
- [ ] Help text for each command documents `--verbose`
- [ ] Main help text updated with `--verbose` description
- [ ] shellcheck passes on containai.sh
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
