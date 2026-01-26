#!/bin/bash
# ContainAI link watcher - monitors for new imports and triggers link repair
#
# Watches for new imports by comparing timestamps:
# - /.containai-imported-at - Written by `cai import` on completion
# - /.containai-links-checked-at - Written by link-repair.sh after ANY successful run
#
# When imported > checked, runs link-repair.sh to restore symlinks
#
# Usage: link-watcher.sh [--poll-interval SECONDS]
#   Default poll interval: 60 seconds
#
# Designed to run as a systemd service with output to journald
set -euo pipefail

: "${HOME:=/home/agent}"
IMPORTED_FILE="/mnt/agent-data/.containai-imported-at"
CHECKED_FILE="/mnt/agent-data/.containai-links-checked-at"
REPAIR_SCRIPT="/usr/local/lib/containai/link-repair.sh"
POLL_INTERVAL=60

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --poll-interval)
            POLL_INTERVAL="$2"
            shift 2
            ;;
        *)
            printf 'ERROR: Unknown option: %s\n' "$1" >&2
            exit 1
            ;;
    esac
done

# Validate poll interval is a positive integer
if ! [[ "$POLL_INTERVAL" =~ ^[0-9]+$ ]] || [[ "$POLL_INTERVAL" -lt 1 ]]; then
    printf 'ERROR: Poll interval must be a positive integer: %s\n' "$POLL_INTERVAL" >&2
    exit 1
fi

log() {
    # ISO 8601 timestamp prefix for journald-friendly output
    printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"
}

log_err() {
    printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >&2
}

log "Link watcher started (poll interval: ${POLL_INTERVAL}s)"
log "Watching: $IMPORTED_FILE vs $CHECKED_FILE"

while true; do
    sleep "$POLL_INTERVAL"

    # Skip if no import timestamp (nothing has been imported yet)
    if [[ ! -f "$IMPORTED_FILE" ]]; then
        continue
    fi

    # Read timestamps
    imported_ts=""
    if ! imported_ts=$(cat "$IMPORTED_FILE" 2>/dev/null); then
        log_err "Failed to read imported timestamp"
        continue
    fi

    checked_ts=""
    if [[ -f "$CHECKED_FILE" ]]; then
        checked_ts=$(cat "$CHECKED_FILE" 2>/dev/null) || true
    fi

    # Compare timestamps (ISO 8601 format sorts lexicographically)
    # Run repair if:
    # - No checked timestamp exists (never checked), OR
    # - Imported timestamp is newer than checked timestamp
    if [[ -z "$checked_ts" ]] || [[ "$imported_ts" > "$checked_ts" ]]; then
        log "Import newer than last check (imported=$imported_ts, checked=${checked_ts:-never}), running repair..."

        # Run repair script with --fix and --quiet flags
        # --quiet suppresses verbose output (still logs to journald via our log wrapper)
        # The repair script handles updating .containai-links-checked-at on success
        if "$REPAIR_SCRIPT" --fix --quiet; then
            log "Repair completed successfully"
        else
            log_err "Repair script failed (exit code: $?)"
            # Continue watching - transient failures shouldn't stop the watcher
        fi
    fi
done
