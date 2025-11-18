#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'USAGE'
Usage: sync-local-remote.sh --bare <bare_repo> --repo <host_repo> --branch <branch> [--container <name>] [--interval <seconds>]

Continuously sync the specified branch from the secure bare repository back to the host working tree.
USAGE
}

BARE_REPO=""
HOST_REPO=""
BRANCH_NAME=""
CONTAINER_NAME=""
INTERVAL_SECONDS="${CODING_AGENTS_LOCAL_SYNC_INTERVAL:-5}"

while [ $# -gt 0 ]; do
    case "$1" in
        --bare)
            BARE_REPO="$2"
            shift 2
            ;;
        --repo)
            HOST_REPO="$2"
            shift 2
            ;;
        --branch)
            BRANCH_NAME="$2"
            shift 2
            ;;
        --container)
            CONTAINER_NAME="$2"
            shift 2
            ;;
        --interval)
            INTERVAL_SECONDS="$2"
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

if [ -z "$BARE_REPO" ] || [ -z "$HOST_REPO" ] || [ -z "$BRANCH_NAME" ]; then
    echo "sync-local-remote.sh: missing required arguments" >&2
    usage >&2
    exit 1
fi

if [ ! -d "$BARE_REPO" ]; then
    echo "sync-local-remote.sh: bare repo not found at $BARE_REPO" >&2
    exit 1
fi

if [ ! -d "$HOST_REPO/.git" ]; then
    echo "sync-local-remote.sh: host repo not found at $HOST_REPO" >&2
    exit 1
fi

PROJECT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
# shellcheck source=../utils/common-functions.sh
source "$PROJECT_ROOT/scripts/utils/common-functions.sh"

LOCK_FILE="$BARE_REPO/.coding-agents-sync.lock"
LAST_SHA=""

log_debug() {
    if [ "${CODING_AGENTS_LOCAL_SYNC_DEBUG:-0}" = "1" ]; then
        printf '[%s] %s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "$1" >&2
    fi
}

should_continue() {
    if [ -n "$CONTAINER_NAME" ] && ! container_exists "$CONTAINER_NAME"; then
        return 1
    fi
    return 0
}

trap 'exit 0' TERM INT

while true; do
    if [ ! -d "$BARE_REPO" ]; then
        log_debug "Bare repo removed; exiting sync loop"
        break
    fi

    if ! should_continue; then
        log_debug "Container $CONTAINER_NAME no longer running; exiting sync loop"
        break
    fi

    SHA=$(git --git-dir="$BARE_REPO" rev-parse --verify --quiet "refs/heads/$BRANCH_NAME" 2>/dev/null || true)

    if [ -n "$SHA" ] && [ "$SHA" != "$LAST_SHA" ]; then
        (
            flock 9
            sync_local_remote_to_host "$HOST_REPO" "$BARE_REPO" "$BRANCH_NAME" || true
        ) 9>"$LOCK_FILE"
        LAST_SHA="$SHA"
    fi

    sleep "$INTERVAL_SECONDS"

done
