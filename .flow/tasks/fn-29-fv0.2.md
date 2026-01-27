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
Implement merge in a post-sync host-side step (after rsync completes) using `jq` or similar - the rsync container script has no JSON tooling.

### 4. Suppress "source not found" noise
The noisy messages are emitted inside the rsync container script (`echo "[INFO] Source not found, skipping: …"` at `src/lib/import.sh:1816-1823`), NOT in the host CLI.
- Pass `IMPORT_VERBOSE=1` env var into the rsync container when host `--verbose` flag is set
- Gate those `echo` statements behind `[ "$IMPORT_VERBOSE" = "1" ]`
- Default should be silent for missing sources, with opt-in verbose output

### 5. Fix base64 truncated input error
The actual failure occurs from `base64 -d` in the rsync container script decoding `MANIFEST_DATA_B64` (at `src/lib/import.sh:2019`, `2168`, `2330`, or per-entry excludes at `1711`). With `sh -e`, any decode error aborts the whole sync.

Two fixes needed:
1. Make decode non-fatal: `… | base64 -d 2>/dev/null || manifest=""` so import can proceed even if symlink relinking fails
2. Consider embedding MANIFEST_DATA in the heredoc alongside `MAP_DATA` (or write to temp file inside container) instead of passing via `--env` to eliminate truncation/quoting/line-ending issues

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
