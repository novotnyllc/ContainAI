# fn-36-rb7.1 Implement workspace state persistence

## Description
Add workspace state read/write helpers in user config and extend TOML tooling for atomic updates. Workspace state must be stored in user config and always read regardless of repo-local config.

## Acceptance
- [ ] `_containai_read_workspace_state <path>` returns workspace section from user config
- [ ] `_containai_write_workspace_state <path> <key> <value>` writes to user config atomically
- [ ] `parse-toml.py --set-workspace-key <path> <key> <value>` exists and performs atomic update
- [ ] Uses temp file + rename for atomicity
- [ ] Preserves comments and non-workspace sections in config
- [ ] Works even when repo-local config exists (no conflict)
- [ ] Creates user config file with 0600 permissions if missing
- [ ] Creates config directory with 0700 permissions if missing
- [ ] Creates `[workspace."<normalized-path>"]` table correctly
- [ ] Path normalization uses `_cai_normalize_path` (not raw `realpath`)

## Verification
- [ ] `cai shell` in a new workspace creates entry in `~/.config/containai/config.toml` with correct permissions

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
