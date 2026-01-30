# fn-36-rb7.13 Implement nested workspace detection

## Description
Resolve implicit workspace by checking parent directories for existing workspace state or containers with workspace labels. Use a single docker query and in-memory checks.

## Acceptance
- [ ] Walks up from cwd checking workspace config entries
- [ ] Also checks for containers with `containai.workspace` label on parent paths
- [ ] Uses nearest matching parent as workspace
- [ ] Logs INFO: "Using existing workspace at /parent (parent of /parent/child)"
- [ ] Normalizes paths via `_cai_normalize_path`
- [ ] Explicit `--workspace` with nested path errors if parent has workspace
- [ ] Efficient implementation: parse config once, compute ancestors once, single docker query
- [ ] Does not call docker per ancestor

## Verification
- [ ] Create container at `/tmp/foo`, `cd /tmp/foo/bar`, `cai shell` uses `/tmp/foo`
- [ ] Explicit `--workspace /tmp/foo/bar` errors with parent conflict

## Done summary
# fn-36-rb7.13 Implementation Summary

## Changes Made

### 1. `src/lib/config.sh` - Nested workspace detection functions

Added two functions for efficient nested workspace detection:

#### `_containai_detect_parent_workspace(path, docker_context)`
- Detects if a path is nested under an existing workspace
- Checks BOTH sources efficiently:
  1. **Workspace config entries**: Parses user config once, extracts all workspace paths
  2. **Container labels**: Queries docker ONCE for all containers with `containai.workspace` label
- Uses Python for O(1) set membership lookup
- Special-cases root path (/) to avoid self-nesting false positives
- Uses `{{index .Labels "containai.workspace"}}` format for docker consistency

#### `_containai_resolve_workspace_with_nesting(path, docker_context, strict_mode)`
- If implicit (cwd): returns parent workspace with INFO message
- If explicit (`--workspace`): errors if nested under parent workspace

### 2. `src/containai.sh` - Integration

Modified `_containai_shell_cmd()` and `_containai_import_cmd()` to use nesting detection with strict mode for explicit --workspace flag.

## Acceptance Criteria Met

All 8 acceptance criteria verified:
- [x] Walks up from cwd checking workspace config entries
- [x] Checks containers with containai.workspace label on parent paths
- [x] Uses nearest matching parent as workspace
- [x] Logs INFO message when using parent workspace
- [x] Normalizes paths via _cai_normalize_path
- [x] Explicit --workspace errors if nested
- [x] Efficient: parse config once, ancestors once, single docker query
- [x] Does not call docker per ancestor

## Review Fixes Applied

- Changed docker label format from `.Label` to `{{index .Labels}}` for consistency
- Added root path special case to prevent self-nesting
- Updated python3 fallback documentation

## Review Status

Codex impl-review verdict: **SHIP** (iteration 8)
## Changes Made

### 1. `src/lib/config.sh` - Added nested workspace detection functions

Added two new functions at the end of config.sh:

#### `_containai_detect_parent_workspace(path, docker_context)`
- Detects if a path is nested under an existing workspace
- Checks BOTH sources efficiently:
  1. **Workspace config entries**: Parses user config once, extracts all workspace paths into a set
  2. **Container labels**: Queries docker ONCE for all containers with `containai.workspace` label
- Uses Python for O(1) set membership lookup
- Returns parent workspace path if found, exit 1 if not nested, exit 2 on error

#### `_containai_resolve_workspace_with_nesting(path, docker_context, strict_mode)`
- Wrapper that resolves workspace with nesting detection
- If implicit (cwd): returns parent workspace with INFO message
- If explicit (`--workspace`): errors if nested under parent workspace

### 2. `src/containai.sh` - Updated `cai shell` command

Modified the workspace resolution flow in `_containai_shell_cmd()`:
- Added strict mode detection based on whether `--workspace` was explicitly provided
- Integrated `_containai_resolve_workspace_with_nesting()` after context selection
- Preserves existing behavior for volume resolution using resolved workspace

## Acceptance Criteria Met

- [x] Walks up from cwd checking workspace config entries
- [x] Also checks for containers with `containai.workspace` label on parent paths
- [x] Uses nearest matching parent as workspace
- [x] Logs INFO: "Using existing workspace at /parent (parent of /parent/child)"
- [x] Normalizes paths via `_cai_normalize_path`
- [x] Explicit `--workspace` with nested path errors if parent has workspace
- [x] Efficient implementation: parse config once, compute ancestors once, single docker query
- [x] Does not call docker per ancestor

## Tests Run

1. **No workspaces configured**: Correctly returns exit 1 (no parent)
2. **Parent workspace in config**: Correctly detects parent from user config
3. **Resolve implicit nested**: Returns parent with INFO message
4. **Resolve explicit nested (strict)**: Correctly errors with guidance message
5. **Docker label detection**: Correctly finds parent via container labels

## Files Modified

1. `src/lib/config.sh` - Added ~130 lines for nested detection functions
2. `src/containai.sh` - Modified ~20 lines in shell command handler
## Evidence
- Commits:
- Tests: {'name': 'Function existence', 'result': 'PASS', 'description': 'Both _containai_detect_parent_workspace and _containai_resolve_workspace_with_nesting functions exist'}, {'name': 'Implicit nested workspace detection', 'result': 'PASS', 'description': 'Implicit (cwd) resolution correctly finds parent workspace and logs INFO message'}, {'name': 'Explicit nested workspace error', 'result': 'PASS', 'description': 'Explicit --workspace with nested path correctly errors with guidance'}, {'name': 'Root path special case', 'result': 'PASS', 'description': 'Root path (/) correctly returns not-nested (cannot be nested under itself)'}, {'name': 'Non-nested workspace resolution', 'result': 'PASS', 'description': 'Path without parent workspace returns requested path unchanged'}, {'name': 'Shellcheck validation', 'result': 'PASS', 'description': 'src/lib/config.sh and src/containai.sh pass shellcheck'}, {'name': 'Codex impl-review', 'result': 'PASS', 'description': 'Received SHIP verdict after fixing docker label format, root path handling, and python3 fallback docs'}
- PRs:
