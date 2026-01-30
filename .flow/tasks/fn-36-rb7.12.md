# fn-36-rb7.12 Update all commands to use workspace state

## Description
Update shell, run, exec, import, export, and stop to read/write workspace state with proper precedence and persistence.

## Acceptance
- [x] `cai shell` reads workspace state, creates if missing, saves on first use
- [x] `cai run` same behavior as shell
- [x] `cai exec` same behavior as shell
- [x] `cai import` reads workspace state to resolve container/volume
- [x] `cai export` reads workspace state
- [x] `cai stop` reads workspace state
- [x] Precedence order enforced: CLI > env > workspace > repo-local > user-global > defaults
- [x] CLI overrides are saved back to workspace state
- [x] `--data-volume` with existing container using different volume errors with guidance

## Verification
- [x] `cai shell` in new dir, exit, `cai import` uses same container/volume
- [x] Set env/CLI overrides and verify precedence

## Done summary
# fn-36-rb7.12 Summary: Update all commands to use workspace state

## Changes Made

### 1. src/lib/config.sh - `_containai_resolve_volume`
Updated to read from workspace state after env var but before config file lookup, implementing the full precedence order:
1. CLI flags (`--data-volume`)
2. Environment variables (`CONTAINAI_DATA_VOLUME`)
3. User workspace state (`~/.config/containai/config.toml` `[workspace."path"]` section)
4. Repo-local config (`.containai/config.toml`)
5. User global config (`~/.config/containai/config.toml` top-level)
6. Built-in defaults

### 2. src/containai.sh - `_containai_shell_cmd`
- Added `data_volume` save to workspace state on container create
- Added volume mismatch check when CLI `--data-volume` conflicts with existing container's volume
- When CLI override is provided with existing container, saves volume back to workspace state

### 3. src/containai.sh - `_containai_exec_cmd`
- Added `data_volume` save to workspace state on container create
- Added volume mismatch check when CLI `--data-volume` conflicts with existing container's volume

### 4. src/containai.sh - `_containai_run_cmd`
- Added `data_volume` save when CLI override is provided

## Behavior

### Volume Mismatch Error
When `--data-volume` is provided and the container already exists with a different volume:
```
[ERROR] Container 'containai-myapp-main' already uses volume 'old-volume'.
        Use --fresh to recreate with new volume, or remove container first.
```

### Workspace State Persistence
- First time using `cai shell/run/exec`: auto-generates names, saves to workspace state
- Subsequent uses: reads from workspace state (no flags needed)
- CLI overrides: use the override AND save back to workspace state

## Files Modified
- `src/lib/config.sh`: 15-line change to `_containai_resolve_volume`
- `src/containai.sh`: ~40 lines added across shell, exec, run commands

## Tests
- All 11 workspace state unit tests pass
- Shellcheck passes with no errors
## Changes Made

### 1. src/lib/config.sh - `_containai_resolve_volume`
Updated to read from workspace state after env var but before config file lookup, implementing the full precedence order:
1. CLI flags (`--data-volume`)
2. Environment variables (`CONTAINAI_DATA_VOLUME`)
3. User workspace state (`~/.config/containai/config.toml` `[workspace."path"]` section)
4. Repo-local config (`.containai/config.toml`)
5. User global config (`~/.config/containai/config.toml` top-level)
6. Built-in defaults

### 2. src/containai.sh - `_containai_shell_cmd`
- Added `data_volume` save to workspace state on container create (line 3218)
- Added volume mismatch check when CLI `--data-volume` conflicts with existing container's volume (lines 3232-3241)
- When CLI override is provided with existing container, saves volume back to workspace state (lines 3254-3257)

### 3. src/containai.sh - `_containai_exec_cmd`
- Added `data_volume` save to workspace state on container create (line 3762)
- Added volume mismatch check when CLI `--data-volume` conflicts with existing container's volume (lines 3773-3782)

### 4. src/containai.sh - `_containai_run_cmd`
- Added `data_volume` save when CLI override is provided (lines 4373-4376)

## Behavior

### Volume Mismatch Error
When `--data-volume` is provided and the container already exists with a different volume:
```
[ERROR] Container 'containai-myapp-main' already uses volume 'old-volume'.
        Use --fresh to recreate with new volume, or remove container first.
```

### Workspace State Persistence
- First time using `cai shell/run/exec`: auto-generates names, saves to workspace state
- Subsequent uses: reads from workspace state (no flags needed)
- CLI overrides: use the override AND save back to workspace state

## Files Modified
- `src/lib/config.sh`: 15-line change to `_containai_resolve_volume`
- `src/containai.sh`: ~40 lines added across shell, exec, run commands

## Tests
- Existing workspace state unit tests pass (11/11)
- Manual precedence tests pass (CLI > env > workspace state)
- Shellcheck passes with no errors
## Evidence
- Commits: 8c409af
- Tests: tests/unit/test-workspace-state.sh (11/11 passed), shellcheck -x src/containai.sh src/lib/config.sh (no errors)
- PRs:
