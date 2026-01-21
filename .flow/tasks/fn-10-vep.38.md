# fn-10-vep.38 Add git config import to cai import command

## Description
Add git configuration import to the `cai import` command. This ensures git commits work inside the container with the user's identity.

**Size:** S  
**Files:** `src/lib/import.sh`, `src/scripts/entrypoint.sh`

## Approach

1. **In lib/import.sh**: Add `_cai_import_git_config()`:
   ```bash
   git_name=$(git config --global user.name 2>/dev/null || echo "")
   git_email=$(git config --global user.email 2>/dev/null || echo "")
   ```
   
2. Write to `/mnt/agent-data/.gitconfig`:
   ```ini
   [user]
       name = User Name
       email = user@example.com
   [safe]
       directory = /workspace
   ```

3. **In entrypoint.sh**: Copy .gitconfig to $HOME:
   ```bash
   if [[ -f "/mnt/agent-data/.gitconfig" ]]; then
     cp "/mnt/agent-data/.gitconfig" "$HOME/.gitconfig"
   fi
   ```

4. Handle edge cases:
   - No git config on host (skip gracefully)
   - Git not installed on host (skip gracefully)
   - Config already exists in volume (update it)

## Key context

- `safe.directory` is critical - without it, git refuses to operate on mounted workspace
- Git config location: `$HOME/.gitconfig` or `$XDG_CONFIG_HOME/git/config`
- Don't copy credentials - just identity and safe.directory
## Acceptance
- [ ] `cai import` extracts git user.name from host
- [ ] `cai import` extracts git user.email from host
- [ ] .gitconfig written to /mnt/agent-data/.gitconfig
- [ ] Entrypoint copies .gitconfig to $HOME/.gitconfig
- [ ] `safe.directory = /workspace` set in config
- [ ] `git config user.name` works inside container
- [ ] `git commit` works without "please tell me who you are" error
- [ ] Gracefully handles missing git or missing config on host
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
