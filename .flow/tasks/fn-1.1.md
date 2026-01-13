# fn-1.1 Create dotnet-wasm directory structure

## Description
Create the `dotnet-wasm/` directory structure following existing repo patterns from `claude/`.

### Files to Create

```
dotnet-wasm/
├── Dockerfile           # Main container definition (created in fn-1.2)
├── .devcontainer/
│   └── devcontainer.json  # VS Code config (created in fn-1.3)
├── build.sh             # Build helper (created in fn-1.4)
└── run.sh               # Run helper (created in fn-1.4)
```

### Reference Pattern

Follow the existing structure at `claude/`:
- `claude/Dockerfile:1-34` - Dockerfile pattern
- `claude/sync-plugins.sh` - Script style with `set -euo pipefail`

### Implementation Notes

- Create directories only; actual file content comes in subsequent tasks
- Ensure proper permissions (755 for directories)
- Add `.gitkeep` to `.devcontainer/` if needed to preserve directory in git
## Acceptance
- [ ] `dotnet-wasm/` directory exists
- [ ] `dotnet-wasm/.devcontainer/` directory exists
- [ ] Directories have correct permissions (755)
- [ ] `ls -la dotnet-wasm/` shows expected structure
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
