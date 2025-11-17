#!/usr/bin/env bash
# git-safe-operation - Wrapper for destructive git operations with automatic snapshots
# Provides safety net for operations that could lose work
set -euo pipefail

if [ $# -lt 1 ]; then
    echo "Usage: git-safe-operation <git-command> [args...]" >&2
    echo "Example: git-safe-operation reset --hard HEAD~1" >&2
    exit 1
fi

OPERATION="$1"
shift

# List of operations that get automatic snapshots
SNAPSHOT_OPERATIONS=(
    "reset"
    "rebase"
    "filter-branch"
    "filter-repo"
    "checkout"  # Only if checking out older commit
)

# Check if operation needs a snapshot
NEEDS_SNAPSHOT=false
for snapshot_op in "${SNAPSHOT_OPERATIONS[@]}"; do
    if [ "$OPERATION" = "$snapshot_op" ]; then
        NEEDS_SNAPSHOT=true
        break
    fi
done

# Create snapshot tag for destructive operations
if [ "$NEEDS_SNAPSHOT" = true ]; then
    SNAPSHOT_TAG="agent-snapshot-$(date +%s)"
    
    if git tag "$SNAPSHOT_TAG" 2>/dev/null; then
        echo "📸 Snapshot created: $SNAPSHOT_TAG" >&2
        echo "💡 To restore: git reset --hard $SNAPSHOT_TAG" >&2
        echo "" >&2
    else
        echo "⚠️  Warning: Could not create snapshot tag" >&2
    fi
fi

# Execute the git operation
exec git "$OPERATION" "$@"
