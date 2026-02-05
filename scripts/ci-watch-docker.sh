#!/usr/bin/env bash
set -euo pipefail

workflow_name="Build and Push Docker Image"
branch="main"
interval_seconds="${CI_WATCH_INTERVAL_SECONDS:-60}"

if ! command -v gh >/dev/null 2>&1; then
    printf 'ERROR: gh CLI is required
' >&2
    exit 1
fi

last_run_id=""

while true; do
    run_id="$(gh run list -L 1 --workflow "$workflow_name" --branch "$branch" --json databaseId --jq '.[0].databaseId')"
    if [[ -z "$run_id" ]]; then
        printf 'ERROR: no runs found for %s on %s
' "$workflow_name" "$branch" >&2
        exit 1
    fi

    if [[ "$run_id" != "$last_run_id" ]]; then
        printf 'Watching run %s for %s on %s
' "$run_id" "$workflow_name" "$branch"
        last_run_id="$run_id"
    else
        sleep "$interval_seconds"
        continue
    fi

    # Stream progress until completion
    if gh run watch "$run_id" --exit-status --interval "$interval_seconds"; then
        printf 'OK: latest %s run on %s is green (%s)
' "$workflow_name" "$branch" "$run_id"
        exit 0
    fi

    # On failure, dump failing job URLs
    gh run view "$run_id" --json jobs --jq '.jobs[] | select(.conclusion=="failure") | "\(.name) \(.url)"'
    printf 'FAIL: latest %s run on %s finished with failure (%s)
' "$workflow_name" "$branch" "$run_id" >&2
    exit 1

    sleep "$interval_seconds"
done
