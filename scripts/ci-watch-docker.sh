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

    conclusion="$(gh run view "$run_id" --json conclusion,status --jq '.conclusion // .status')"

    if [[ "$run_id" != "$last_run_id" ]]; then
        printf 'Run %s status: %s
' "$run_id" "$conclusion"
        last_run_id="$run_id"

        if [[ "$conclusion" != "success" ]]; then
            gh run view "$run_id" --json jobs --jq '.jobs[] | select(.conclusion=="failure") | "\(.name) \(.url)"'
        fi
    fi

    if [[ "$conclusion" == "success" ]]; then
        printf 'OK: latest %s run on %s is green (%s)
' "$workflow_name" "$branch" "$run_id"
        exit 0
    fi

    sleep "$interval_seconds"
done
