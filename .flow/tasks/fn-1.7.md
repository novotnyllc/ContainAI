# fn-1.7 Create sync-vscode-data.sh pre-population script

## Description
Create `sync-vscode-data.sh` script to pre-populate VS Code volumes from host, following the pattern established in `claude/sync-plugins.sh`.

### Script Purpose

Allow users to sync their VS Code settings, extensions, and auth data from the host into Docker volumes before running the container. This enables:
- Pre-authenticated GitHub Copilot
- Pre-installed extensions
- User settings and keybindings
- Extension-specific data (globalStorage)

### Script Structure

Follow existing patterns from `claude/sync-plugins.sh`:
- `set -euo pipefail`
- Readonly constants for volume names
- Color output with fallback
- Dry-run mode support
- Use alpine container for file operations

### Sync Sources (Host)

| Source | Volume Target |
|--------|---------------|
| `~/.config/github-copilot/` | `docker-github-copilot` |
| `~/.config/Code/User/globalStorage/` | `docker-vscode-data` (subdirectory) |
| `~/.vscode/extensions/` | `docker-vscode-server` (extensions subdirectory) |
| `~/.omnisharp/` | `docker-omnisharp` |

### Implementation

```bash
#!/usr/bin/env bash
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly GITHUB_COPILOT_VOLUME="docker-github-copilot"
readonly VSCODE_DATA_VOLUME="docker-vscode-data"
readonly OMNISHARP_VOLUME="docker-omnisharp"

# Detect host paths
HOST_COPILOT_DIR="${HOME}/.config/github-copilot"
HOST_VSCODE_STORAGE="${HOME}/.config/Code/User/globalStorage"
HOST_OMNISHARP="${HOME}/.omnisharp"

# Create volumes if needed
docker volume create "$GITHUB_COPILOT_VOLUME" 2>/dev/null || true

# Sync using alpine container
if [[ -d "$HOST_COPILOT_DIR" ]]; then
    docker run --rm \
        -v "$GITHUB_COPILOT_VOLUME":/target \
        -v "$HOST_COPILOT_DIR":/source:ro \
        alpine sh -c "cp -r /source/* /target/ && chown -R 1000:1000 /target"
fi

# ... similar for other directories
```

### Reference

- Pattern: `claude/sync-plugins.sh:108-114` (volume mount pattern)
- Pattern: `claude/sync-plugins.sh:21-23` (volume naming)
- Pattern: `claude/sync-plugins.sh:37` (dry-run support)
## Acceptance
- [ ] `dotnet-wasm/sync-vscode-data.sh` exists and is executable
- [ ] Script uses `set -euo pipefail` pattern
- [ ] Script syncs GitHub Copilot auth from host if present
- [ ] Script syncs VS Code globalStorage from host if present
- [ ] Script syncs OmniSharp config from host if present
- [ ] Files in volumes have correct ownership (UID 1000)
- [ ] Script supports `--dry-run` flag
- [ ] Script handles missing host directories gracefully
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
