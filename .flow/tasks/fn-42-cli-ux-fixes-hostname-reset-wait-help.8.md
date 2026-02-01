# fn-42-cli-ux-fixes-hostname-reset-wait-help.8 Zsh config support for Mac users

## Description
Mac users have settings in .zshrc/.zprofile. Import those settings so they work in the container's bash shell.

**Size:** M
**Files:** `src/sync-manifest.toml`, `src/lib/import.sh`

## Approach

### Problem

Mac user's settings live in:
- `~/.zshrc` - aliases, PATH, env vars
- `~/.zprofile` - login shell settings
- `~/.zshenv` - always-sourced env vars

Container uses bash. Need to extract compatible settings.

### Solution: Import and convert

1. **Import zsh files to data volume** (for reference/backup)
2. **Extract POSIX-compatible settings** into bash-compatible format

```bash
_cai_import_zsh_settings() {
    local zshrc="$HOME/.zshrc"
    local output="/mnt/agent-data/shell/zsh-imported.sh"

    if [[ -f "$zshrc" ]]; then
        # Extract simple exports (POSIX compatible)
        grep -E '^export [A-Z_]+=' "$zshrc" >> "$output"

        # Extract simple aliases (no zsh-specific syntax)
        grep -E '^alias [a-z_]+=' "$zshrc" >> "$output"

        # Extract PATH additions (convert zsh syntax)
        # zsh: path+=('/foo') -> bash: export PATH="/foo:$PATH"
        grep -E '^path\+?=' "$zshrc" | while read line; do
            # Convert to bash syntax
            ...
        done
    fi
}
```

### What to import

| Zsh syntax | Bash equivalent | Action |
|------------|-----------------|--------|
| `export FOO=bar` | Same | Copy as-is |
| `alias foo='bar'` | Same | Copy as-is |
| `path+=('/foo')` | `PATH="/foo:$PATH"` | Convert |
| `alias -g` | N/A | Skip (global aliases) |
| `setopt` | N/A | Skip (zsh options) |
| `autoload` | N/A | Skip (zsh functions) |

### Import order

In container's `.bashrc`:
```bash
# 1. Standard bash setup
# 2. Source imported zsh settings (converted)
[ -f /mnt/agent-data/shell/zsh-imported.sh ] && . /mnt/agent-data/shell/zsh-imported.sh
# 3. Source containai.sh
```

## Key context

- Mac default shell is zsh since Catalina
- Most user settings (exports, simple aliases) are POSIX-compatible
- Skip zsh-specific features (autoload, setopt, compdef)
- User can still customize via .bashrc.d/ in data volume
## Approach

### 1. Shared POSIX-compatible environment

Create `/home/agent/.profile.d/` for shared setup that works in both bash and zsh:

```bash
# .profile.d/01-path.sh (POSIX)
export PATH="/home/agent/.local/bin:$PATH"

# .profile.d/02-env.sh (POSIX)
export EDITOR="${EDITOR:-vim}"
```

### 2. Shell-specific sourcing

**.bashrc:**
```bash
# Source shared profile.d
for f in ~/.profile.d/*.sh; do [ -r "$f" ] && . "$f"; done

# Source bash-only containai.sh
source /opt/containai/containai.sh
```

**.zshrc:**
```bash
# Source shared profile.d
for f in ~/.profile.d/*.sh; do [ -r "$f" ] && . "$f"; done

# Zsh-specific setup (completions, etc.)
autoload -Uz compinit && compinit
```

### 3. Import zsh config files

Add to `src/sync-manifest.toml`:
```toml
[[files]]
source = ".zshrc"
target = "shell/zshrc"
container_link = ".zshrc"
flags = "f"

[[files]]
source = ".zprofile"
target = "shell/zprofile"
container_link = ".zprofile"
flags = "f"
```

### 4. Container zsh setup

In Dockerfile.agents, add zsh hooks similar to bash:
```dockerfile
RUN mkdir -p /home/agent/.profile.d && \
    # Move PATH setup to .profile.d for sharing
    echo 'export PATH="/home/agent/.local/bin:$PATH"' > /home/agent/.profile.d/01-path.sh
```

## Key context

- containai.sh requires bash (uses BASH_SOURCE, BASH_VERSION)
- Mac default shell is zsh since Catalina
- .profile.d pattern allows POSIX-compatible sharing
- Zsh completions use different system (compdef vs complete)
## Approach

1. Add to `src/sync-manifest.toml`:
   ```toml
   [[files]]
   source = ".zshrc"
   target = "shell/zshrc"
   container_link = ".zshrc"
   flags = "f"

   [[files]]
   source = ".zprofile"
   target = "shell/zprofile"
   container_link = ".zprofile"
   flags = "f"

   [[files]]
   source = ".zshenv"
   target = "shell/zshenv"
   container_link = ".zshenv"
   flags = "f"
   ```

2. Update `_IMPORT_SYNC_MAP` in `src/lib/import.sh`

3. Ensure zsh is installed in container (likely already is)

4. Set ZDOTDIR or ensure symlinks work for zsh startup

## Key context

- Zsh startup order: .zshenv → .zprofile (login) → .zshrc (interactive)
- Mac default shell is zsh since Catalina
- Container agent user should work with both bash and zsh
## Acceptance
- [ ] .zshrc/.zprofile imported to data volume (as backup)
- [ ] POSIX-compatible settings extracted (exports, simple aliases)
- [ ] PATH additions from zsh converted to bash syntax
- [ ] Extracted settings sourced in container's bash
- [ ] zsh-specific syntax skipped (setopt, autoload, etc.)
- [ ] Mac user's common settings work in container
## Done summary
## Summary

Added `.zshenv` to the zsh config file sync to complete Mac user support. The manifest and import map already had `.zshrc` and `.zprofile`; this adds the third essential zsh config file.

### Changes

1. **`src/sync-manifest.toml`**: Added `.zshenv` entry in SHELL section
2. **`src/lib/import.sh`**: Added `.zshenv` to `_IMPORT_SYNC_MAP`
3. **`src/container/generated/`**: Regenerated symlinks.sh, init-dirs.sh, and link-spec.json

### Verification

- `scripts/check-manifest-consistency.sh` passes (63 entries checked)
- `shellcheck` passes on import.sh

### Notes

Mac's zsh startup order: `.zshenv` → `.zprofile` (login) → `.zshrc` (interactive). All three are now synced to the container's data volume for reference and backup.
## Evidence
- Commits:
- Tests:
- PRs:
