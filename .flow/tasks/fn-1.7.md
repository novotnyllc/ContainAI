# fn-1.7 Create sync-vscode-data.sh pre-population script

## Description
Create `sync-vscode-data.sh` script to pre-populate VS Code settings from host, following the pattern established in `claude/sync-plugins.sh`.

### Script Purpose

Allow users to sync their VS Code **settings and keybindings only** (not extensions) from the host into Docker volumes before running the container. This enables:
- Pre-authenticated GitHub Copilot CLI
- User settings and keybindings
- Code snippets

**Note**: Extension sync is NOT supported. VS Code Server manages extensions independently; host extensions are incompatible with the server. Users should rely on `customizations.vscode.extensions` in devcontainer.json for extension installation.

### Best-Effort Path Handling

VS Code Server paths vary across versions and remote modes. This script:
1. Detects VS Code variant (Stable vs Insiders) on host
2. Uses known paths but logs clearly when paths are missing
3. Documents tested VS Code version in comments

### Script Structure

Follow existing patterns from `claude/sync-plugins.sh`:
- `set -euo pipefail`
- Readonly constants for volume names
- Color output with fallback
- Dry-run mode support
- Use alpine container for file operations

### Sync Sources (Host) - with Insiders Support

| Host Variant | Host Path | Volume Target |
|--------------|-----------|---------------|
| **Stable (Linux)** | `~/.config/Code/User/` | `docker-vscode-server` |
| **Stable (macOS)** | `~/Library/Application Support/Code/User/` | `docker-vscode-server` |
| **Insiders (Linux)** | `~/.config/Code - Insiders/User/` | `docker-vscode-server` |
| **Insiders (macOS)** | `~/Library/Application Support/Code - Insiders/User/` | `docker-vscode-server` |
| **Copilot CLI** | `~/.config/github-copilot/` | `docker-github-copilot` |

**NOT synced**: Extensions (incompatible between host and server)

### VS Code Server Data Location

Inside the container, VS Code Server stores settings at:
- `~/.vscode-server/data/Machine/settings.json` (machine settings)
- User settings are typically synced via VS Code Settings Sync, but can be pre-seeded

**Note**: These paths may change between VS Code versions. Document the version tested.

### Implementation Sketch

```bash
#!/usr/bin/env bash
set -euo pipefail

# Script verified on VS Code 1.95+ (update if behavior changes)
readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly GITHUB_COPILOT_VOLUME="docker-github-copilot"
readonly VSCODE_SERVER_VOLUME="docker-vscode-server"

info() { echo "ℹ️  $*"; }
success() { echo "✅ $*"; }
warn() { echo "⚠️  $*" >&2; }
skip() { echo "⏭️  Skipping: $*"; }

# Detect VS Code variant on host (stable vs insiders)
detect_vscode_paths() {
  if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS paths
    if [[ -d "${HOME}/Library/Application Support/Code - Insiders/User" ]]; then
      HOST_VSCODE_USER="${HOME}/Library/Application Support/Code - Insiders/User"
      info "Detected VS Code Insiders (macOS)"
    elif [[ -d "${HOME}/Library/Application Support/Code/User" ]]; then
      HOST_VSCODE_USER="${HOME}/Library/Application Support/Code/User"
      info "Detected VS Code Stable (macOS)"
    else
      HOST_VSCODE_USER=""
      warn "No VS Code config found on macOS"
    fi
  else
    # Linux paths (including WSL)
    if [[ -d "${HOME}/.config/Code - Insiders/User" ]]; then
      HOST_VSCODE_USER="${HOME}/.config/Code - Insiders/User"
      info "Detected VS Code Insiders (Linux)"
    elif [[ -d "${HOME}/.config/Code/User" ]]; then
      HOST_VSCODE_USER="${HOME}/.config/Code/User"
      info "Detected VS Code Stable (Linux)"
    else
      HOST_VSCODE_USER=""
      warn "No VS Code config found on Linux"
    fi
  fi
}

detect_vscode_paths
HOST_COPILOT_DIR="${HOME}/.config/github-copilot"

# Create volumes if needed
docker volume create "$GITHUB_COPILOT_VOLUME" 2>/dev/null || true
docker volume create "$VSCODE_SERVER_VOLUME" 2>/dev/null || true

# Sync Copilot CLI auth
if [[ -d "$HOST_COPILOT_DIR" ]]; then
  info "Syncing GitHub Copilot CLI auth..."
  docker run --rm \
    -v "$GITHUB_COPILOT_VOLUME":/target \
    -v "$HOST_COPILOT_DIR":/source:ro \
    alpine sh -c "cp -r /source/* /target/ && chown -R 1000:1000 /target"
  success "Copilot CLI auth synced"
else
  skip "Copilot CLI dir not found: $HOST_COPILOT_DIR"
fi

# Sync VS Code settings (if found)
if [[ -n "$HOST_VSCODE_USER" && -f "$HOST_VSCODE_USER/settings.json" ]]; then
  info "Syncing VS Code settings..."
  docker run --rm \
    -v "$VSCODE_SERVER_VOLUME":/target \
    -v "$HOST_VSCODE_USER":/source:ro \
    alpine sh -c "mkdir -p /target/data/Machine && cp /source/settings.json /target/data/Machine/ && chown -R 1000:1000 /target"
  success "VS Code settings synced"
else
  skip "VS Code settings.json not found"
fi

# Similar for keybindings and snippets...

success "Sync complete (best-effort)"
```

### Reference

- Pattern: `claude/sync-plugins.sh:108-114` (volume mount pattern)
- Pattern: `claude/sync-plugins.sh:21-23` (volume naming)
- Pattern: `claude/sync-plugins.sh:37` (dry-run support)
- VS Code Server paths: `~/.vscode-server/data/`
## Acceptance
- [ ] `dotnet-wasm/sync-vscode-data.sh` exists and is executable
- [ ] Script uses `set -euo pipefail` pattern
- [ ] Script detects VS Code Stable vs Insiders paths on host
- [ ] Script syncs GitHub Copilot CLI auth from host if present
- [ ] Script syncs VS Code settings.json from host if present (to both User and Machine paths - heuristic)
- [ ] Script syncs VS Code keybindings.json from host if present
- [ ] Script syncs VS Code snippets from host if present
- [ ] Script does NOT sync extensions (documented limitation)
- [ ] Script logs clearly when paths are not found ("Skipping: ...")
- [ ] Files in volumes have correct ownership (UID 1000)
- [ ] Script supports `--dry-run` flag (shows what would be synced without syncing)
- [ ] Script handles missing host directories gracefully (no error, just skips with log)
- [ ] Script includes comment documenting tested VS Code version
- [ ] README documents this is best-effort and paths may vary
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
