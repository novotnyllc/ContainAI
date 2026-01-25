# fn-17-axl.4 Agent secret sync with --no-secrets opt-out

## Description

Implement `--no-secrets` flag for `cai import` to optionally skip syncing agent secret files (OAuth tokens, API keys, auth.json files).

**Agent secret files (synced by default):**
- `~/.claude/.credentials.json` (Claude OAuth tokens)
- `~/.codex/auth.json` (Codex API key)
- `~/.gemini/google_accounts.json` (Gemini OAuth)
- `~/.gemini/oauth_creds.json` (Gemini OAuth)
- `~/.local/share/opencode/auth.json` (OpenCode auth)
- `~/.config/gh/hosts.yml` (GitHub CLI tokens)
- `~/.ssh/id_*` (SSH private keys)

**Implementation:**
1. Define secret files list in sync manifest (flag: `s` for secret)
2. Add `--no-secrets` flag to `cai import` command
3. When `--no-secrets` is set, skip entries with `s` flag
4. Update `_containai_import()` to accept no_secrets parameter
5. Update help text to document the flag

**Terminology clarification:**
- This does NOT affect `--credentials=host` which controls bind-mounting host credential stores
- `--no-secrets` only affects which files are copied into the data volume

## Acceptance

- [ ] `cai import` (default) syncs all agent secret files
- [ ] `cai import --no-secrets` skips agent secret files
- [ ] `cai import --dry-run --no-secrets` shows which files would be skipped
- [ ] Secret files identified by `s` flag in sync manifest
- [ ] SSH private keys (id_*) respect --no-secrets
- [ ] Help text documents --no-secrets flag
- [ ] No conflict with existing --credentials flag
- [ ] Secret files have 600 permissions when synced

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
