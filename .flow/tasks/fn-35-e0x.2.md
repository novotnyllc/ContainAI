# fn-35-e0x.2 Add Pi to sync-manifest.toml

## Description
Add mkdir -p for Pi and Kimi directories in Dockerfile.agents agent data directory block.

**Size:** S
**Files:** `src/container/Dockerfile.agents`

## Approach

Add to the existing mkdir block at lines 51-59:
```dockerfile
/home/agent/.pi \
/home/agent/.pi/agent \
/home/agent/.kimi
```

## Key context

- Pi uses nested structure: `~/.pi/agent/` for config
- Kimi uses flat structure: `~/.kimi/`
- These directories must exist before symlinks are created
## Acceptance
- [ ] ~/.pi directory added
- [ ] ~/.pi/agent directory added
- [ ] ~/.kimi directory added
- [ ] Directories in correct location (agent data block)
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
