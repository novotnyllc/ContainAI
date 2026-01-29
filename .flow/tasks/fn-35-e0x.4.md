# fn-35-e0x.4 Run generators and rebuild image

## Description
Verify that symlinks are created correctly in the container and configs would sync properly.

**Size:** S
**Files:** None (verification only)

## Approach

```bash
# Start container
cai shell

# Verify symlinks exist
ls -la ~/.pi/agent/
ls -la ~/.kimi/

# Check that symlinks point to correct targets
readlink ~/.pi/agent/settings.json
readlink ~/.kimi/config.toml

# Verify Pi and Kimi still work
pi --version
kimi --version
```

## Key context

- Symlinks should point to /mnt/agent-data/pi/ and /mnt/agent-data/kimi/
- Agents should still function with symlinked configs
## Acceptance
- [ ] Pi symlinks resolve correctly
- [ ] Kimi symlinks resolve correctly
- [ ] pi --version works
- [ ] kimi --version works
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
