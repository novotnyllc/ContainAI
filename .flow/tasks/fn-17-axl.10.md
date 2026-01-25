# fn-17-axl.10 Add cai links check and cai links fix commands

## Description

Add commands to verify and repair container symlinks against the link spec.

**Important architectural note:** Container symlinks are created in the container filesystem (via Dockerfile), NOT in the data volume. They point INTO the data volume. This means:
- Links can only be checked/fixed in a running or stopped container
- "Offline" means: start container briefly, fix links, optionally stop
- The data volume alone cannot have links "fixed" - they don't live there

**Commands:**
- `cai links check [container]` - Verify all symlinks match link-spec.json
- `cai links fix [container]` - Recreate missing/broken symlinks

**How check works:**
1. Read `/usr/local/lib/containai/link-spec.json` from container (shipped in image)
2. For each entry, verify:
   - Symlink exists at link path
   - Points to correct target path
3. Report: OK, MISSING, WRONG_TARGET, BROKEN
4. Exit code: 0=all OK, 1=issues found

**How fix works (STATUS-DRIVEN):**
1. Run check logic to identify issues
2. Track `changes_made` counter
3. For each issue:
   - MISSING: create symlink (with R flag handling), increment changes
   - WRONG_TARGET: recreate symlink (with R flag handling), increment changes
   - BROKEN: recreate symlink (with R flag handling), increment changes
   - OK: no action
4. Create parent directories as needed
5. **Update `/.containai-links-checked-at` on ALL successful runs** (prevents watcher infinite loop)
6. Exit code: 0=success, 1=errors occurred

## R Flag Handling (CRITICAL)

The link-spec.json includes an `r_flag` boolean for each entry. When `r_flag=true`, the repair script MUST:
1. Remove existing path first (`rm -rf "$link_path"`)
2. Then create symlink (`ln -sfn "$target" "$link_path"`)

**Why this matters:** If the link path already exists as a directory, `ln -sfn` creates a nested symlink inside it instead of replacing it. This breaks persistence.

**link-spec.json format:**
```json
{
  "links": [
    {
      "link_path": "/home/agent/.copilot/skills",
      "target": "/mnt/agent-data/copilot/skills",
      "r_flag": true
    },
    {
      "link_path": "/home/agent/.copilot/config.json",
      "target": "/mnt/agent-data/copilot/config.json",
      "r_flag": false
    }
  ]
}
```

**link-repair.sh implementation (STATUS-DRIVEN):**
```bash
#!/bin/bash
set -euo pipefail

SPEC="/usr/local/lib/containai/link-spec.json"
CHECKED_FILE="/mnt/agent-data/.containai-links-checked-at"
changes_made=0
errors=0

# Check and fix each link
check_and_fix_link() {
    local link_path="$1"
    local target="$2"
    local r_flag="$3"

    # Determine current state
    local state="OK"
    if [ ! -e "$link_path" ] && [ ! -L "$link_path" ]; then
        state="MISSING"
    elif [ -L "$link_path" ]; then
        current_target=$(readlink "$link_path")
        if [ "$current_target" != "$target" ]; then
            state="WRONG_TARGET"
        elif [ ! -e "$link_path" ]; then
            state="BROKEN"
        fi
    else
        # Exists but not a symlink
        state="NOT_SYMLINK"
    fi

    # Take action based on state
    case "$state" in
        OK)
            echo "[OK] $link_path -> $target"
            ;;
        MISSING|WRONG_TARGET|BROKEN|NOT_SYMLINK)
            echo "[FIX] $link_path ($state)"

            # Ensure parent directory exists
            mkdir -p "$(dirname "$link_path")"

            # R flag: remove existing path first
            if [ "$r_flag" = "true" ]; then
                rm -rf "$link_path"
            fi

            # Create/recreate symlink
            ln -sfn "$target" "$link_path"
            changes_made=$((changes_made + 1))
            ;;
    esac
}

# Parse JSON and process each link
while IFS=$'\t' read -r link_path target r_flag; do
    check_and_fix_link "$link_path" "$target" "$r_flag" || errors=$((errors + 1))
done < <(jq -r '.links[] | [.link_path, .target, .r_flag] | @tsv' "$SPEC")

# Report changes
if [ "$changes_made" -gt 0 ]; then
    echo "[INFO] Made $changes_made changes"
else
    echo "[INFO] All links OK, no changes needed"
fi

# ALWAYS update checked timestamp on successful completion
# This prevents infinite loop in watcher when links are already correct
if [ "$errors" -eq 0 ]; then
    date -u +%Y-%m-%dT%H:%M:%SZ > "$CHECKED_FILE"
    echo "[INFO] Updated checked timestamp"
fi

# Exit code
if [ "$errors" -gt 0 ]; then
    exit 1
fi
exit 0
```

**Container-side implementation:**
Both host and container watcher use the same repair script:
- `/usr/local/lib/containai/link-repair.sh` shipped in image
- Reads `/usr/local/lib/containai/link-spec.json`
- `cai links fix` runs via SSH: `ssh container /usr/local/lib/containai/link-repair.sh`
- Watcher calls same script directly

**Implementation:**
1. Create `src/container/containai-link-repair.sh` (runs IN container)
2. Add `src/lib/links.sh` with `_containai_links_check` and `_containai_links_fix` (host wrappers)
3. Add `links` subcommand to containai.sh
4. Host commands SSH to container to run repair script

## Acceptance

- [ ] `cai links check` reports symlink status (OK/MISSING/WRONG_TARGET/BROKEN)
- [ ] `cai links check` returns 0 if all OK, 1 if issues found
- [ ] `cai links fix` repairs broken/missing symlinks
- [ ] `cai links fix` creates parent directories
- [ ] Status-driven: only fixes links that need fixing
- [ ] Tracks changes_made counter for reporting
- [ ] **Updates checked timestamp on ALL successful runs (not just when changes made)**
- [ ] R flag: entries with r_flag=true use rm -rf before ln -sfn
- [ ] R flag: entries with r_flag=false use ln -sfn only
- [ ] Test: directory at link path is properly replaced when r_flag=true
- [ ] Works on running container via SSH
- [ ] Works on stopped container (start, fix, optionally stop)
- [ ] Reads from link-spec.json (shipped in image from fn-17-axl.9)
- [ ] Repair script at /usr/local/lib/containai/link-repair.sh
- [ ] Same script used by host command and container watcher
- [ ] Dry-run mode shows what would be fixed (without making changes or updating timestamp)
- [ ] Exit codes: 0=success, 1=errors occurred

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
