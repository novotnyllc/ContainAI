# fn-1.7 Create VS Code sync scripts

## Description
Create VS Code sync scripts (split into multiple scripts):

**sync-vscode.sh:**
- Syncs VS Code settings and extension list to `dotnet-sandbox-vscode` volume
- **OS-specific source paths:**
  - macOS: `~/Library/Application Support/Code/User/`
  - Linux: `~/.config/Code/User/`
  - Windows (WSL): `/mnt/c/Users/<user>/AppData/Roaming/Code/User/`
- **Files synced:** `settings.json`, `keybindings.json`
- **Extensions:** use `code --list-extensions` to generate list, sync to volume
- Exits non-zero on failure (permission denied, actual errors)
- **"Not found" vs error:** exit 0 with message if VS Code not installed; exit 1 on actual errors

**sync-vscode-insiders.sh:**
- Same as above for VS Code Insiders
- **OS-specific source paths:**
  - macOS: `~/Library/Application Support/Code - Insiders/User/`
  - Linux: `~/.config/Code - Insiders/User/`
- Exits non-zero on failure

**sync-all.sh:**
- Detects what VS Code installations are available (check if paths exist)
- Calls appropriate sync scripts
- Won't call sync-vscode-insiders if no Insiders data exists
- Also syncs gh CLI config

**gh CLI:**
- Sync ~/.config/gh to `dotnet-sandbox-gh` volume
## Acceptance
- [ ] sync-vscode.sh detects host OS and uses correct source path
- [ ] sync-vscode.sh syncs settings.json and keybindings.json
- [ ] sync-vscode.sh syncs extensions list via `code --list-extensions`
- [ ] sync-vscode.sh exits 0 with message if VS Code not installed
- [ ] sync-vscode.sh exits non-zero on permission errors
- [ ] sync-vscode-insiders.sh works for Insiders with correct paths
- [ ] sync-vscode-insiders.sh exits non-zero on failure
- [ ] sync-all.sh detects available VS Code installations
- [ ] sync-all.sh skips unavailable installations gracefully
- [ ] sync-all.sh syncs gh CLI config
- [ ] All scripts require jq
## Done summary
- Implemented sync-vscode.sh with OS detection (macOS/Linux/WSL)
- Implemented sync-vscode-insiders.sh with separate data-insiders/ directory
- Implemented sync-all.sh to orchestrate VS Code + gh CLI syncs
- All scripts support --dry-run mode and graceful handling when apps not installed

Verification:
- bash -n syntax check passed for all scripts
- --dry-run mode tested successfully
- --help output verified for all scripts
## Evidence
- Commits: a187e4b0126bcde47f4b4e830ddbe9b1832b85b2
- Tests: bash -n sync-vscode.sh, bash -n sync-vscode-insiders.sh, bash -n sync-all.sh, ./sync-vscode.sh --dry-run, ./sync-vscode-insiders.sh --dry-run, ./sync-all.sh --dry-run
- PRs:
