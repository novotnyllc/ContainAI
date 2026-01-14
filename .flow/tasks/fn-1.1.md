# fn-1.1 Create dotnet-wasm directory structure

## Description
Create the `dotnet-wasm/` directory structure following existing repo patterns from `claude/`.

### Files to Create

```
dotnet-wasm/
├── Dockerfile           # Main container definition (created in fn-1.2)
├── build.sh             # Build helper (created in fn-1.4)
├── aliases.sh           # Shell aliases to source (created in fn-1.4)
├── init-volumes.sh      # Volume initialization (created in fn-1.4)
├── check-sandbox.sh     # Sandbox/ECI detection (created in fn-1.11)
├── sync-vscode-data.sh  # VS Code data sync script (created in fn-1.7)
└── README.md            # Documentation (created in fn-1.10)
```

### Reference Pattern

Follow the existing structure at `claude/`:
- `claude/Dockerfile:1-34` - Dockerfile pattern
- `claude/sync-plugins.sh` - Script style with `set -euo pipefail`

### Implementation Notes

- Create directory only; actual file content comes in subsequent tasks
- Ensure proper permissions (755 for directory)

## Acceptance
- [ ] `dotnet-wasm/` directory exists
- [ ] Directory has correct permissions (755)
- [ ] `ls -la dotnet-wasm/` shows expected structure
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
