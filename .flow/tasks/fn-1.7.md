# fn-1.7 Create sync-vscode-data.sh pre-population script

## Description
Create VS Code sync scripts (split into multiple scripts):

**sync-vscode.sh:**
- Syncs VS Code settings and extension list
- Extension list synced so VS Code auto-downloads on launch
- Exits non-zero on failure (permission denied, doesn't exist)

**sync-vscode-insiders.sh:**
- Same as above for VS Code Insiders
- Exits non-zero on failure

**sync-all.sh:**
- Detects what VS Code installations are available
- Calls appropriate sync scripts
- Won't call sync-vscode-insiders if no Insiders data exists
- Also syncs gh CLI config

**gh CLI:**
- Sync ~/.config/gh to container (in addition to github-copilot)
## Acceptance
- [ ] sync-vscode.sh syncs settings.json
- [ ] sync-vscode.sh syncs extensions list
- [ ] sync-vscode.sh exits non-zero on permission error
- [ ] sync-vscode.sh exits non-zero if no VS Code data
- [ ] sync-vscode-insiders.sh works for Insiders
- [ ] sync-vscode-insiders.sh exits non-zero on failure
- [ ] sync-all.sh detects available VS Code installations
- [ ] sync-all.sh skips unavailable installations gracefully
- [ ] sync-all.sh syncs gh CLI config
- [ ] All scripts require jq
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
