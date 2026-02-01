# fn-42-cli-ux-fixes-hostname-reset-wait-help.6 Sync timezone from host to container

## Description
Container should inherit host timezone so timestamps match.

**Size:** S
**Files:** `src/lib/container.sh`

## Approach

Add to docker run args at container creation:

**Option A - Environment variable (simpler):**
```bash
# Detect host timezone
if [[ -f /etc/timezone ]]; then
    host_tz=$(cat /etc/timezone)
elif [[ -L /etc/localtime ]]; then
    host_tz=$(readlink /etc/localtime | sed 's|.*/zoneinfo/||')
else
    host_tz="UTC"
fi
args+=(-e "TZ=$host_tz")
```

**Option B - Mount (more robust):**
```bash
args+=(-v /etc/localtime:/etc/localtime:ro)
```

Recommend Option A for portability (works on Mac where /etc/localtime path differs).

## Key context

- Container creation at `src/lib/container.sh:2299-2400`
- Mac uses `/var/db/timezone/zoneinfo/` not `/usr/share/zoneinfo/`
## Acceptance
- [ ] Container timezone matches host
- [ ] `date` command in container shows correct local time
- [ ] Works on Linux and macOS hosts
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
