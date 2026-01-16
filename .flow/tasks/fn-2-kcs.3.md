# fn-2-kcs.3: PR3 - README.md documentation update

## Description

Update README.md to reflect the renamed `asb` command and remove all stale `csd` references.

**Dependency**: This task should be done AFTER fn-2-kcs.1 (aliases.sh rename) is complete.

## File to Modify

- `agent-sandbox/README.md`

## Changes Required

### Stale References to Update

| Pattern | Change to |
|---------|-----------|
| `csd` command references | `asb` |
| `csd-stop-all` | `asb-stop-all` |
| "Claude Sandbox Dotnet" | "Agent Sandbox" |
| "Dotnet sandbox" | "Agent Sandbox" |
| "dotnet-sandbox" (project name) | "agent-sandbox" |

### Volume Names (Breaking Change)

Rename volume names from `dotnet-sandbox-*` to `agent-sandbox-*`:
- Update `_ASB_VOLUMES` array values in aliases.sh
- Update any `docker volume` commands in documentation
- Update variable definitions containing volume names

**Note**: This orphans existing Docker volumes. Users must manually migrate data if needed. No automatic migration - backward compatibility explicitly not required.

### Additional Updates

- Clarify that `_ASB_LABEL` identifies containers as "managed by asb" (not per-user ownership)

### Search Commands

```bash
# Find all csd references
rg "\bcsd\b" agent-sandbox/README.md

# Find dotnet-sandbox references (all should be renamed)
rg "dotnet-sandbox" agent-sandbox/README.md
```

## Testing

```bash
# Verify no stale references remain (word boundary search)
grep -i "\\bcsd\\b" agent-sandbox/README.md  # Should return nothing

# Verify no dotnet-sandbox references remain
grep "dotnet-sandbox" agent-sandbox/README.md  # Should return nothing
```

## Acceptance

- [ ] All `csd` command references changed to `asb`
- [ ] `csd-stop-all` changed to `asb-stop-all`
- [ ] "Claude Sandbox Dotnet" changed to "Agent Sandbox"
- [ ] "Dotnet sandbox" (title case) changed to "Agent Sandbox"
- [ ] "dotnet-sandbox" project references changed to "agent-sandbox"
- [ ] Volume names `dotnet-sandbox-*` renamed to `agent-sandbox-*`
- [ ] Title updated to reference "agent-sandbox"
- [ ] All command examples updated
- [ ] `grep -i "\\bcsd\\b" agent-sandbox/README.md` returns no matches
- [ ] Documentation accurately describes the renamed commands

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
