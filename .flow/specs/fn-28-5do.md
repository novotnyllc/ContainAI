# Fix fn-27-hbi Bugs: Sysbox Fallback, Update Prompts, SSH Keys

## Overview

Bug fixes for issues discovered in fn-27-hbi (ContainAI Reliability Pack) implementation. Three critical issues need resolution:

1. **Sysbox upstream fallback** - The code falls back to upstream nestybox releases if ContainAI fetch fails. This caused a downgrade from ContainAI sysbox to upstream. NO fallback should ever happen - fail if ContainAI unavailable.

2. **Update container abort** - When containers are running during update, it aborts instead of prompting user to stop them. Should prompt interactively.

3. **SSH key issues** - User reports "many keys" being generated incorrectly. Need investigation.

## Scope

- `src/lib/setup.sh` - Remove upstream fallback from `_cai_resolve_sysbox_download_url`
- `src/lib/update.sh` - Add interactive prompt for container stop
- `src/lib/ssh.sh` - Investigate and fix key management issues

## Approach

### Task 1: Remove upstream sysbox fallback

**File**: `src/lib/setup.sh:755-818`

Current behavior: If ContainAI release fetch fails, falls back to upstream nestybox.
Required behavior: Fail with clear error message. NO FALLBACK.

Changes:
- Remove "Priority 4: Fall back to upstream" section (lines ~755-818)
- Return error with actionable message when ContainAI fetch fails
- Keep CAI_SYSBOX_URL and CAI_SYSBOX_VERSION overrides for manual workarounds

### Task 2: Update prompts to stop containers

**File**: `src/lib/update.sh`

Current behavior: Aborts with message when containers running.
Required behavior: Prompt user "Containers are running. Stop them to continue? [y/N]"

Changes:
- Add interactive prompt when containers detected and update needed
- On "y", call container stop and proceed
- On "n" or timeout, abort as before
- Keep `--stop-containers` flag for non-interactive use

### Task 3: Investigate SSH key issues

**Files**: `src/lib/ssh.sh`

User reports: "many keys" being regenerated incorrectly

Investigation needed:
- Check if key generation is triggered multiple times
- Check known_hosts accumulation
- Verify one key per host design is working

## Quick commands

```bash
# Verify sysbox source (should only show containai, never upstream)
source src/containai.sh && _cai_resolve_sysbox_download_url amd64 true

# Test update behavior
cai update --dry-run

# Check SSH key state
ls -la ~/.config/containai/id_containai*
cat ~/.config/containai/known_hosts

# Run shellcheck
shellcheck -x src/lib/setup.sh src/lib/update.sh src/lib/ssh.sh
```

## Acceptance

- [ ] `_cai_resolve_sysbox_download_url` returns error (not fallback) when ContainAI unavailable
- [ ] `cai update` prompts to stop containers instead of aborting
- [ ] SSH key management verified working correctly
- [ ] All shellcheck passes
- [ ] Existing tests pass

## References

- Original epic: fn-27-hbi (ContainAI Reliability Pack)
- Sysbox download resolution: `src/lib/setup.sh:642-820`
- Update flow: `src/lib/update.sh`
- SSH key management: `src/lib/ssh.sh`
