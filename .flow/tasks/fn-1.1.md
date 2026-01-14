# fn-1.1 Create dotnet-sandbox directory structure

## Description
Create the `dotnet-sandbox/` directory structure with placeholder files:

- `dotnet-sandbox/Dockerfile`
- `dotnet-sandbox/build.sh`
- `dotnet-sandbox/aliases.sh`
- `dotnet-sandbox/sync-vscode.sh`
- `dotnet-sandbox/sync-vscode-insiders.sh`
- `dotnet-sandbox/sync-all.sh`
- `dotnet-sandbox/README.md`

Note: Directory is `dotnet-sandbox/` to match the image name per naming standards in spec.
## Acceptance
- [x] `dotnet-sandbox/` directory exists
- [x] Directory has correct permissions (755)
- [x] `ls -la dotnet-sandbox/` shows expected structure
## Done summary
Created `dotnet-sandbox/` directory structure with all placeholder files:
- `Dockerfile` - placeholder for container definition
- `build.sh` - executable placeholder for build script
- `aliases.sh` - executable placeholder for shell aliases (csd)
- `sync-vscode.sh` - executable placeholder for VS Code sync
- `sync-vscode-insiders.sh` - executable placeholder for VS Code Insiders sync
- `sync-all.sh` - executable placeholder for combined sync
- `README.md` - placeholder documentation

Directory has 755 permissions. All shell scripts are executable.
## Evidence
- Commits: 4a72197, 903739e, 014b571
- Tests: ls -la dotnet-sandbox/, stat -c '%a' dotnet-sandbox
- PRs: