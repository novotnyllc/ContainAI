# fn-4-vet.8 Create lib/config.sh - config loading & volume resolution

<!-- Updated by plan-sync: fn-4-vet.4 implemented config functions directly in aliases.sh -->
<!-- Functions already exist: _containai_find_config, _containai_parse_config_for_workspace, _containai_resolve_volume -->
<!-- This task may involve extracting to lib/ OR verifying existing implementation is complete -->

## Description
Create `agent-sandbox/lib/config.sh` - config loading and volume resolution for bash.

## Functions

### `_containai_find_config(workspace)`
Walk up from workspace to git root (or /) looking for `.containai/config.toml`.
Then check `~/.config/containai/config.toml`. Return first found path or empty.

### `_containai_parse_config(config_file, workspace)`
Call `parse-toml.py` and capture JSON output. Parse with jq or bash.
Return associative array or set global vars: `_CAI_VOLUME`, `_CAI_EXCLUDES`.

### `_containai_resolve_volume(cli_volume, workspace, explicit_config)`
Implements precedence:
1. `cli_volume` if set → return immediately (skip config)
2. `CONTAINAI_DATA_VOLUME` env → return immediately (skip config)
3. Find and parse config → return `data_volume`
4. Default: `sandbox-agent-data`

### `_containai_resolve_excludes(workspace, explicit_config)`
Parse config, return excludes array (cumulative default + workspace).

## Key Points
- Check `command -v python3` before calling parser
- If Python unavailable but config exists, warn and use default
- If `--config` specified but file missing, error exit
## Acceptance
- [ ] File exists at `agent-sandbox/lib/config.sh`
- [ ] `_containai_find_config` walks up from workspace correctly
- [ ] `_containai_parse_config` calls parse-toml.py and parses JSON
- [ ] `_containai_resolve_volume` implements correct precedence
- [ ] `_containai_resolve_excludes` returns cumulative excludes
- [ ] Graceful fallback when Python unavailable
- [ ] Error exit when explicit `--config` file missing
## Done summary
Fixed RETURN trap causing unbound variable error in _containai_parse_config. Added strict mode for explicit configs (parse failures return error instead of fallback). Improved robustness with proper JSON extraction error handling and stderr warning display.
## Evidence
- Commits: 56b840f, 9ed8bcd, d8e86b0
- Tests: manual function tests for all acceptance criteria
- PRs:
