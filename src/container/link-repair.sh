#!/usr/bin/env bash
# ContainAI link repair script
# Verifies and repairs symlinks in the container based on link-spec.json
# Usage: link-repair.sh [--check|--fix|--dry-run] [--quiet]
#   --check    Verify symlinks without making changes (default)
#   --fix      Repair broken or missing symlinks
#   --dry-run  Show what would be fixed without making changes
#   --quiet    Suppress output for cron/watcher use
#
# Exit codes:
#   0 = Success (all OK in check mode, or fix completed)
#   1 = Issues found (check mode) or errors occurred
set -euo pipefail

: "${HOME:=/home/agent}"
BUILTIN_SPEC="/usr/local/lib/containai/link-spec.json"
USER_SPEC="/mnt/agent-data/containai/user-link-spec.json"
DATA_DIR="/mnt/agent-data"
CHECKED_AT_FILE="${DATA_DIR}/.containai-links-checked-at"

MODE="check"
QUIET=0

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --check)
            MODE="check"
            shift
            ;;
        --fix)
            MODE="fix"
            shift
            ;;
        --dry-run)
            MODE="dry-run"
            shift
            ;;
        --quiet)
            QUIET=1
            shift
            ;;
        *)
            printf 'ERROR: Unknown option: %s\n' "$1" >&2
            exit 1
            ;;
    esac
done

log() {
    [[ $QUIET -eq 1 ]] && return 0
    printf '%s\n' "$*"
}

log_err() {
    printf '%s\n' "$*" >&2
}

# Check for jq
if ! command -v jq >/dev/null 2>&1; then
    log_err "ERROR: jq is required but not installed"
    exit 1
fi

# Global counters (modified by process_link_spec)
broken=0
missing=0
ok=0
fixed=0
errors=0

# Process a single link spec file
# Arguments: $1 = path to link-spec.json
process_link_spec() {
    local spec_file="$1"
    local spec_name="${2:-}"

    if [[ ! -f "$spec_file" ]]; then
        return 0
    fi

    local links_count
    links_count=$(jq -r '.links | length' "$spec_file" 2>/dev/null) || {
        log_err "ERROR: Failed to parse link spec: $spec_file"
        errors=$((errors + 1))
        return 1
    }

    if [[ "$links_count" -eq 0 ]]; then
        return 0
    fi

    [[ -n "$spec_name" ]] && log "[INFO] Processing $spec_name ($links_count links)"

    local i link target remove_first
    for i in $(seq 0 $((links_count - 1))); do
        link=$(jq -r ".links[$i].link" "$spec_file")
        target=$(jq -r ".links[$i].target" "$spec_file")
        remove_first=$(jq -r ".links[$i].remove_first" "$spec_file")

        # Check current state
        # States: OK, MISSING, WRONG_TARGET, BROKEN (dangling), EXISTS_FILE, EXISTS_DIR
        if [[ -L "$link" ]]; then
            # It's a symlink - check if it points to the right target
            local current_target
            current_target=$(readlink "$link")
            if [[ "$current_target" == "$target" ]]; then
                # Target text matches - but is the symlink dangling?
                if [[ ! -e "$link" ]]; then
                    log "[BROKEN] $link -> $target (dangling symlink)"
                    broken=$((broken + 1))
                else
                    ok=$((ok + 1))
                    continue
                fi
            else
                log "[WRONG_TARGET] $link -> $current_target (expected: $target)"
                broken=$((broken + 1))
            fi
        elif [[ -e "$link" ]]; then
            # Exists but is not a symlink - check if it's a file or directory
            if [[ -d "$link" ]]; then
                # Directory requires R flag to remove
                # remove_first can be true, false, 1, or 0 depending on JSON format
                if [[ "$remove_first" == "true" || "$remove_first" == "1" || "$remove_first" -eq 1 ]] 2>/dev/null; then
                    log "[EXISTS_DIR] $link is a directory (will remove with R flag)"
                    broken=$((broken + 1))
                else
                    log "[CONFLICT] $link exists as directory (no R flag - cannot fix)"
                    errors=$((errors + 1))
                    continue
                fi
            else
                # Regular file - ln -sfn can replace it without R flag
                log "[EXISTS_FILE] $link is a regular file (will replace)"
                broken=$((broken + 1))
            fi
        else
            # Does not exist
            log "[MISSING] $link -> $target"
            missing=$((missing + 1))
        fi

        # Fix mode (or dry-run)
        if [[ "$MODE" == "fix" || "$MODE" == "dry-run" ]]; then
            # Create parent directory if needed
            local parent
            parent=$(dirname "$link")
            if [[ ! -d "$parent" ]]; then
                if [[ "$MODE" == "dry-run" ]]; then
                    log "[WOULD] Create parent directory: $parent"
                else
                    if ! mkdir -p "$parent"; then
                        log_err "ERROR: Failed to create parent: $parent"
                        errors=$((errors + 1))
                        continue
                    fi
                fi
            fi

            # Remove existing if needed before creating symlink
            # - Symlinks: always safe to replace with ln -sfn
            # - Regular files: ln -sfn can replace them
            # - Directories: require R flag (rm -rf) before ln -sfn
            if [[ -e "$link" || -L "$link" ]]; then
                if [[ -d "$link" && ! -L "$link" ]]; then
                    # Directory (not symlink to directory) - requires R flag
                    # Check remove_first flag (can be true, 1, or integer 1)
                    local can_remove=0
                    if [[ "$remove_first" == "true" || "$remove_first" == "1" ]]; then
                        can_remove=1
                    elif [[ "$remove_first" -eq 1 ]] 2>/dev/null; then
                        can_remove=1
                    fi
                    if [[ $can_remove -eq 1 ]]; then
                        if [[ "$MODE" == "dry-run" ]]; then
                            log "[WOULD] Remove directory: $link"
                        else
                            if ! rm -rf "$link"; then
                                log_err "ERROR: Failed to remove directory: $link"
                                errors=$((errors + 1))
                                continue
                            fi
                        fi
                    else
                        log_err "ERROR: Cannot fix - directory exists without R flag: $link"
                        errors=$((errors + 1))
                        continue
                    fi
                elif [[ -L "$link" ]]; then
                    # Symlink - ln -sfn handles replacement, but log for dry-run
                    if [[ "$MODE" == "dry-run" ]]; then
                        log "[WOULD] Replace symlink: $link"
                    fi
                    # ln -sfn will replace the symlink
                else
                    # Regular file - ln -sfn will replace it
                    if [[ "$MODE" == "dry-run" ]]; then
                        log "[WOULD] Replace file: $link"
                    fi
                    # ln -sfn will replace the file
                fi
            fi

            # Create symlink
            if [[ "$MODE" == "dry-run" ]]; then
                log "[WOULD] Create symlink: $link -> $target"
                fixed=$((fixed + 1))
            else
                if ln -sfn "$target" "$link"; then
                    log "[FIXED] $link -> $target"
                    fixed=$((fixed + 1))
                else
                    log_err "ERROR: Failed to create symlink: $link -> $target"
                    errors=$((errors + 1))
                fi
            fi
        fi
    done
}

# Check for built-in link-spec.json
if [[ ! -f "$BUILTIN_SPEC" ]]; then
    log_err "ERROR: Built-in link spec not found: $BUILTIN_SPEC"
    exit 1
fi

# Process built-in links
process_link_spec "$BUILTIN_SPEC" "built-in links"

# Process user links if spec exists (non-fatal - don't let user spec break built-in repairs)
if [[ -f "$USER_SPEC" ]]; then
    if ! process_link_spec "$USER_SPEC" "user-defined links"; then
        log_err "[WARN] Failed to process user link spec (continuing with built-in links)"
    fi
fi

# Update checked-at timestamp after any successful run (fix mode only, not dry-run)
# Per spec: updated on ALL successful runs (even if no changes made)
if [[ "$MODE" == "fix" && $errors -eq 0 ]]; then
    # Write atomically
    tmp_file="${CHECKED_AT_FILE}.tmp.$$"
    if date -u +%Y-%m-%dT%H:%M:%SZ > "$tmp_file" 2>/dev/null && mv "$tmp_file" "$CHECKED_AT_FILE" 2>/dev/null; then
        log "[INFO] Updated links-checked-at timestamp"
    else
        rm -f "$tmp_file" 2>/dev/null || true
        log_err "[WARN] Failed to update links-checked-at timestamp"
    fi
fi

# Summary
log ""
if [[ "$MODE" == "dry-run" ]]; then
    log "=== Dry-Run Summary ==="
else
    log "=== Link Status Summary ==="
fi
log "  OK:      $ok"
log "  Broken:  $broken"
log "  Missing: $missing"
if [[ "$MODE" == "fix" ]]; then
    log "  Fixed:   $fixed"
elif [[ "$MODE" == "dry-run" ]]; then
    log "  Would fix: $fixed"
fi
log "  Errors:  $errors"

# Exit code per spec:
#   0 = Success (all OK in check mode, fix completed, or dry-run completed)
#   1 = Issues found (check mode) or errors occurred
if [[ $errors -gt 0 ]]; then
    exit 1
elif [[ "$MODE" == "check" && $((broken + missing)) -gt 0 ]]; then
    exit 1
fi
exit 0
