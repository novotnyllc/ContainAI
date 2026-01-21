# fn-10-vep.47 Implement SSH port allocation (2300-2500 range)

## Description
Implement SSH port allocation in the 2300-2500 range.

**Size:** S
**Files:** lib/ssh.sh

## Approach

1. Create `_cai_find_available_port()`:
   - Use `ss -Htan` to get used ports (more reliable than netstat)
   - Iterate through 2300-2500 range
   - Return first available port
   - Return error if all ports exhausted

2. Port range configurable via `[ssh].port_range_start` and `[ssh].port_range_end` in config.toml

## Key context

- Pattern from github-scout: apache/systemds uses `ss -tulpn`
- Don't use ephemeral range (32768+) to avoid conflicts with Docker/OS
- Store allocated port in container label: `containai.ssh-port`
## Acceptance
- [ ] `_cai_find_available_port()` function created
- [ ] Uses `ss` (not netstat) for port detection
- [ ] Default range is 2300-2500
- [ ] Range is configurable via config.toml
- [ ] Returns error with clear message if no ports available
- [ ] Port stored in container label on creation
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
