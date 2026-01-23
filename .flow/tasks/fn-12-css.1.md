# fn-12-css.1 Add workspace state helpers to lib/config.sh

## Description

Add helper functions to lib/config.sh for managing workspace state persistence. These functions enable automatic volume association tracking so users don't need to repeatedly specify `--data-volume`.

**Functions to add:**

1. `_containai_get_workspace_volume()` - Resolve volume for a workspace
   - Check if workspace has a saved volume association in user config
   - If not found, auto-generate volume name from workspace path basename
   - Format: `containai-<basename>-data` (e.g., `containai-myapp-data`)
   - Handle edge cases: sanitize basename for Docker volume name rules

2. `_containai_save_workspace_state()` - Persist workspace→volume mapping
   - Write to user config file (`~/.config/containai/config.toml`)
   - Create `[workspace."<path>"]` section with `data_volume` and `created_at`
   - Preserve existing config content, only add/update workspace section

3. `_containai_user_config_path()` - Get user config file path
   - Return `$XDG_CONFIG_HOME/containai/config.toml` or `~/.config/containai/config.toml`
   - Create directory structure if needed

**Volume name generation rules:**
- Use workspace directory basename
- Prefix with `containai-`, suffix with `-data`
- Sanitize: lowercase, replace invalid chars with `-`
- Match Docker volume name pattern: `[a-zA-Z0-9][a-zA-Z0-9_.-]*`

## Acceptance

- [ ] `_containai_get_workspace_volume /home/user/myapp` returns saved volume or generates `containai-myapp-data`
- [ ] `_containai_save_workspace_state /home/user/myapp myvolume` creates `[workspace."/home/user/myapp"]` section in user config
- [ ] Existing config file content is preserved when adding workspace section
- [ ] Volume names are sanitized to match Docker naming rules
- [ ] User config directory is created if it doesn't exist

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
