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
last_summary=""

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
        last_summary=""
    fi

    status="$(gh run view "$run_id" --json status --jq '.status')"
    conclusion="$(gh run view "$run_id" --json conclusion --jq '.conclusion // ""')"
    jobs_summary="$(gh run view "$run_id" --json jobs --jq '.jobs[] | [.name, .status, (.conclusion // "")] | @tsv')"
    summary_key="${status}|${conclusion}|${jobs_summary}"

    if [[ "$summary_key" != "$last_summary" ]]; then
        printf 'Run status: %s%s
' "$status" "${conclusion:+ (conclusion=$conclusion)}"
        if [[ -n "$jobs_summary" ]]; then
            printf 'Jobs:
'
            while IFS=$'\t' read -r job_name job_status job_conclusion; do
                if [[ -n "$job_conclusion" ]]; then
                    printf '  - %s: %s (%s)
' "$job_name" "$job_status" "$job_conclusion"
                else
                    printf '  - %s: %s
' "$job_name" "$job_status"
                fi
            done <<<"$jobs_summary"
        fi
        last_summary="$summary_key"
    fi

    if [[ "$status" != "completed" ]]; then
        sleep "$interval_seconds"
        continue
    fi

    if [[ "$conclusion" == "success" ]]; then
        printf 'OK: latest %s run on %s is green (%s)
' "$workflow_name" "$branch" "$run_id"
        exit 0
    fi

    printf 'FAIL: latest %s run on %s finished with %s (%s)
' "$workflow_name" "$branch" "${conclusion:-unknown}" "$run_id" >&2

    mkdir -p /tmp/containai-logs
    failing_jobs="$(gh run view "$run_id" --json jobs --jq '.jobs[] | select(.conclusion=="failure") | [.databaseId, .name, .url] | @tsv')"
    if [[ -n "$failing_jobs" ]]; then
        while IFS=$'\t' read -r job_id job_name job_url; do
            log_path="/tmp/containai-logs/ci-watch-${run_id}-${job_id}.log"
            printf 'Failed job: %s %s
' "$job_name" "$job_url" >&2
            if gh run view "$run_id" --log --job "$job_id" > "$log_path" 2>/dev/null; then
                printf '--- %s (tail) ---
' "$log_path" >&2
                tail -n 200 "$log_path" >&2 || true
            else
                printf 'WARN: failed to fetch logs for %s
' "$job_name" >&2
            fi
        done <<<"$failing_jobs"
    fi
    exit 1
done
