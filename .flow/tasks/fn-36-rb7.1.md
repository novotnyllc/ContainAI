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
- [ ] Unit test: `_containai_write_workspace_state /tmp/test key value` creates config with correct permissions
- [ ] Unit test: `parse-toml.py --set-workspace-key` creates atomic update preserving comments

NOTE: Full integration verification ("`cai shell` creates entry") is deferred to fn-36-rb7.12 which wires these helpers into commands.

## Done summary
Implemented workspace state persistence with atomic TOML updates. Added `_containai_read_workspace_state`, `_containai_write_workspace_state`, and `_containai_user_config_path` to config.sh, and extended parse-toml.py with `--set-workspace-key` and `--get-workspace` modes. Uses temp file + rename for atomicity, preserves comments, creates files with 0600/0700 permissions, and normalizes paths via `_cai_normalize_path`.
## Evidence
- Commits: 4a5e6049537fda34e111b0590ff0a01f734b0781
- Tests: acceptance criteria verification script (AC1-AC10), shellcheck -x src/lib/config.sh, python3 -m py_compile src/parse-toml.py, ./tests/unit/test-exclude-rewrite.sh
- PRs:
