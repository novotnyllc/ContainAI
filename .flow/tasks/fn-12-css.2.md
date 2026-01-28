# fn-12-css.2 Update workspace-specific commands to persist workspace state

## Description

Modify all workspace-specific commands in src/containai.sh to automatically use and persist workspace state. After this change, users only need to specify `--data-volume` once; all subsequent workspace commands remember the association.

**Affected commands:**
- `cai run` - Start/attach to container
- `cai shell` - Open interactive shell
- `cai import` - Sync configs to volume
- `cai export` - Export volume to archive
- `cai stop` - Stop container
- `cai exec` (new, task 3) - One-shot command

**Volume resolution order (all commands):**
1. CLI flag `--data-volume` (highest priority)
2. Workspace state from user config (saved association)
3. Config file `[workspace."<path>"].data_volume`
4. Config file `[agent].data_volume`
5. Auto-generated from workspace basename (lowest priority)

**State persistence:**
- After successful container creation (run/shell/exec), call `_containai_save_workspace_state()`
- Only save if volume was auto-generated (not from CLI flag or existing config)
- This makes the auto-generated volume "sticky" for future invocations

**Behavior examples:**
- First `cai shell` in `/home/user/myapp`: generates `containai-myapp-data`, saves it
- Second `cai import` in same dir: uses saved volume automatically
- `cai export` in same dir: uses saved volume automatically
- `cai stop` in same dir: finds container by workspace, uses saved volume
- `cai shell --data-volume custom`: uses `custom`, does NOT save (explicit override)

**Implementation approach:**
- Create shared `_containai_resolve_workspace_volume()` that all commands use
- Call `_containai_save_workspace_state()` only on new volume creation
- Track whether volume was auto-generated vs explicit for save decision

## Acceptance

- [ ] `cai shell` without `--data-volume` auto-generates and saves volume association
- [ ] `cai run` uses same workspace state as shell
- [ ] `cai import` uses saved workspace volume
- [ ] `cai export` uses saved workspace volume
- [ ] `cai stop` uses saved workspace volume
- [ ] Second command in same workspace uses saved volume
- [ ] `--data-volume custom` uses custom but does not persist it
- [ ] Existing config file settings still work (precedence preserved)

## Done summary
Superseded by fn-36-rb7 or fn-31-gib
## Evidence
- Commits:
- Tests:
- PRs:
