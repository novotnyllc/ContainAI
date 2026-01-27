# fn-29-fv0.2 Update import defaults and credential handling

## Description
Update import defaults to remove `~/.ssh`, handle credential files intelligently, and fix base64 errors.

**Size:** M
**Files:** `src/lib/import.sh`

## Changes

### 1. Remove ~/.ssh from default imports
- Remove entries at `import.sh:378-383` that import SSH config/known_hosts/keys
- Remove `_import_discover_ssh_keys()` call from defaults (lines 745-800)
- Document that users can add `~/.ssh` to `[import] additional_paths` if wanted

### 2. Skip profile credentials
For these files, skip import if source is from user's home profile directory:
- `~/.claude/.credentials.json` (line 357) - skip if `$source_path` starts with `$HOME/.claude/`
- `~/.codex/auth.json` (line 455) - skip if from `$HOME/.codex/`

Keep the symlink to volume mount so container can write its own tokens after `claude login`.

### 3. Copilot config.json minimum structure
At `import.sh:441-442`, ensure the imported/created config.json has at minimum:
```json
{
  "trusted_folders": ["/home/agent/workspace"],
  "banner": "never"
}
```
If file exists with content, merge these properties (replace trusted_folders array, preserve other properties).

### 4. Suppress "source not found" noise
- Change logging for missing source files from always-visible to only when `--verbose` is set
- Look for `_cai_warn` or `_cai_info` calls about "source not found" or "source missing"

### 5. Fix base64 truncated input error
- Debug the error at `import.sh:2600` where `base64 | tr -d '\n'` fails
- Likely cause: large file or encoding issue in MANIFEST_DATA_B64
- May need chunked encoding or alternative approach

## Key context

- Import uses rsync with base64-encoded manifest for atomic sync
- Profile detection: compare `$source_path` to `$HOME/.<tool>/` prefix
- Credential files use `fs` flag (secret) - symlink behavior should be preserved
## Acceptance
- [ ] `~/.ssh` is NOT imported by default
- [ ] Claude `.credentials.json` from `~/.claude/` is NOT imported (symlink still created)
- [ ] Codex `auth.json` from `~/.codex/` is NOT imported (symlink still created)
- [ ] Copilot config.json has minimum `trusted_folders` and `banner` structure
- [ ] "source not found/missing" messages only appear with `--verbose`
- [ ] No "base64: truncated input" errors during import
- [ ] Rsync sync completes successfully
- [ ] Users can still add `~/.ssh` via config if they want it
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
