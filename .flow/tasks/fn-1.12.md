# fn-1.12 Research and define volume strategy

## Description
Research and define the optimal volume strategy for the dotnet-sandbox.

**Status: COMPLETED** - Volume strategy defined in epic spec.

### Volume Strategy (Defined in Spec)

| Volume Name | Mount Point | Purpose | Created By |
|-------------|-------------|---------|------------|
| `docker-claude-data` | `/mnt/claude-data` | Claude credentials (managed by sandbox) | Docker sandbox |
| `docker-claude-plugins` | `/home/agent/.claude/plugins` | Claude plugins | sync-plugins.sh |
| `dotnet-sandbox-vscode` | `/home/agent/.vscode-server` | VS Code server data | csd/init |
| `dotnet-sandbox-nuget` | `/home/agent/.nuget` | NuGet package cache | csd/init |
| `dotnet-sandbox-gh` | `/home/agent/.config/gh` | GitHub CLI config | sync-all.sh |

### Key Decisions

1. **docker-claude-data**: DO NOT create or modify - docker sandbox manages it
2. **Ownership**: All volumes created with uid 1000 (agent user)
3. **Zero-friction**: `csd` wrapper creates missing volumes automatically
4. **Permission fixing**: Minimal helper container (`docker run --rm -v vol:/data alpine chown 1000:1000 /data`)
5. **No separate init script**: `csd` handles everything

### Integration with Existing Scripts

- `docker-claude-plugins` volume reused from existing `sync-plugins.sh`
- New volumes follow naming pattern: `dotnet-sandbox-*`

## Acceptance
- [x] Volume strategy documented in epic spec
- [x] Each volume has clear name and mount point
- [x] Ownership strategy defined (uid 1000)
- [x] Integration with existing sync-plugins.sh considered
- [x] Zero-friction startup approach documented
## Done summary
Volume strategy defined in epic spec
## Evidence
- Commits:
- Tests:
- PRs: