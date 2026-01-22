# fn-10-vep.47 Implement SSH port allocation (2300-2500 range)

## Description
Implement SSH port allocation in the 2300-2500 range with graceful error handling for port exhaustion.

**Size:** M
**Files:** lib/ssh.sh, lib/container.sh

## Approach

1. Port allocation function:
   - Scan ports 2300-2500 using `ss -tulpn`
   - Find first available port
   - Handle port exhaustion with clear error message

2. Port exhaustion handling:
   - If all 200 ports are in use, provide actionable error
   - Suggest running `cai ssh cleanup` to remove stale configs
   - List containers using ports for user review

3. Store allocated port in container label `containai.ssh-port`

4. Port reuse on container restart:
   - If container already has port label, try to reuse it
   - If port now in use, reallocate

## Key context

- Use `ss -tulpn` not netstat (more portable)
- Port must be stored in container label for persistence
- Consider concurrent allocation (file locking if needed)
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
- [ ] Port allocation scans 2300-2500 range
- [ ] Uses `ss -tulpn` for port checking
- [ ] Clear error message if all ports exhausted
- [ ] Error message suggests `cai ssh cleanup`
- [ ] Port stored in container label `containai.ssh-port`
- [ ] Port reused on container restart when available
- [ ] No silent failures - all errors are user-visible
## Done summary
Implemented SSH port allocation functions in lib/ssh.sh with automatic port assignment (range 2300-2500 by default, configurable via [ssh] section in config.toml). Integrated port allocation into container creation in container.sh with proper labeling, locking for concurrency safety, and automatic container recreation on port conflicts during restart.
## Evidence
- Commits: f7f3831, c8c3748, fb51ce0, 18f9fd6, 587df88, ca50262, e444d03, 89800ce
- Tests: bash -n src/lib/ssh.sh, bash -n src/lib/container.sh, bash -n src/lib/config.sh
- PRs: