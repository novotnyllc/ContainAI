# fn-17-axl.11 Timestamp-based auto-fix watcher

## Description

Implement automatic link repair inside container when import is newer than last check.

**Timestamp files (in data volume, accessed via /target during import, /mnt/agent-data in container):**
- `/.containai-imported-at` - Written by `cai import` on completion
- `/.containai-links-checked-at` - Written by link-repair.sh after ANY successful run

**IMPORTANT: Path during import vs runtime:**
- Import runs in rsync container where volume is mounted at `/target`
- Container runtime has volume at `/mnt/agent-data`
- Same file, different mount points

**Watcher behavior:**
1. Runs in container as lightweight background process
2. Polls every 60 seconds
3. Compares timestamps: if imported > checked → run repair
4. After ANY successful repair run (regardless of changes made), update checked timestamp
5. This prevents infinite loops when links are already correct

**Loop prevention (CRITICAL):**
The previous design had a bug: "update timestamp only if changes made" causes infinite loops when `imported > checked` but links are already OK.

**Correct design:**
- `/.containai-links-checked-at` is updated after ANY successful repair script run
- This acknowledges "I've checked and handled the import at this timestamp"
- Even if no changes needed, the check was performed

**Implementation:**

**Host-side (import.sh):**
```bash
# At end of successful import, write timestamp to volume
# Volume is mounted at /target inside rsync container
date -u +%Y-%m-%dT%H:%M:%SZ > /target/.containai-imported-at
```

**Container-side (link-repair.sh update):**
```bash
# After successful completion (regardless of changes_made):
date -u +%Y-%m-%dT%H:%M:%SZ > /mnt/agent-data/.containai-links-checked-at
```

**Container-side (link-watcher.sh):**
```bash
#!/bin/bash
IMPORTED_FILE="/mnt/agent-data/.containai-imported-at"
CHECKED_FILE="/mnt/agent-data/.containai-links-checked-at"
REPAIR_SCRIPT="/usr/local/lib/containai/link-repair.sh"
POLL_INTERVAL=60

while true; do
    sleep "$POLL_INTERVAL"

    # Skip if no import timestamp
    [ -f "$IMPORTED_FILE" ] || continue

    imported_ts=$(cat "$IMPORTED_FILE")
    checked_ts=""
    [ -f "$CHECKED_FILE" ] && checked_ts=$(cat "$CHECKED_FILE")

    # Compare timestamps (ISO 8601 sorts lexicographically)
    if [ -z "$checked_ts" ] || [[ "$imported_ts" > "$checked_ts" ]]; then
        echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Import newer than last check, running repair..."
        if "$REPAIR_SCRIPT"; then
            echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Repair complete"
        else
            echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Repair failed" >&2
        fi
    fi
done
```

**Components shipped in image:**
- `/usr/local/lib/containai/link-repair.sh` - from fn-17-axl.10 (updated to write checked-at)
- `/usr/local/lib/containai/link-spec.json` - from fn-17-axl.9
- `/usr/local/lib/containai/link-watcher.sh` - this task
- `/etc/systemd/system/containai-link-watcher.service` - this task

## Acceptance

- [ ] `cai import` writes `/.containai-imported-at` to volume (via `/target/` path)
- [ ] link-repair.sh writes `/.containai-links-checked-at` after ANY successful run
- [ ] Timestamps in ISO 8601 format
- [ ] Watcher script shipped at `/usr/local/lib/containai/link-watcher.sh`
- [ ] Watcher compares imported vs checked timestamps
- [ ] Watcher triggers repair when imported > checked
- [ ] **No infinite loop: checked timestamp updated even when no changes needed**
- [ ] Polling interval: 60 seconds
- [ ] Systemd service starts watcher on boot
- [ ] Watcher logs to journald
- [ ] Service handles watcher crash/restart

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
