# fn-10-vep.15 Start dockerd and verify DinD works in sysbox

## Description
Verify that dockerd can start and run inside our current sysbox container without --privileged.

**Size:** S
**Files:** None (verification only)

## Context

We're already running in an ECI/sysbox container. The user confirmed:
- Sysbox containers can run dockerd natively
- No --privileged flag needed
- dockerd just isn't started yet

## Approach

1. Start dockerd with sysbox-compatible flags:
   ```bash
   sudo dockerd --iptables=false --ip-masq=false &
   ```

2. Wait for dockerd to be ready:
   ```bash
   timeout 30 bash -c 'until docker info >/dev/null 2>&1; do sleep 1; done'
   ```

3. Verify basic operations:
   - `docker info` shows daemon running
   - `docker run --rm alpine echo "test"` works
   - `docker build` works

4. Document what flags are needed/optional

## Key context

- Storage driver: Let dockerd auto-select (vfs may be required in some nested scenarios)
- Network: `--iptables=false --ip-masq=false` because NAT may not work in nested container
- Socket: Standard `/var/run/docker.sock` is fine (not running inside Dockerfile.test)
## Acceptance
- [ ] dockerd starts without --privileged flag
- [ ] `docker info` shows daemon running
- [ ] `docker run --rm alpine echo "nested works"` succeeds
- [ ] `docker build -t test - <<< "FROM alpine"` succeeds
- [ ] Document required/optional flags for sysbox DinD
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
