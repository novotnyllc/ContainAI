#!/usr/bin/env bash
# Cleanup utilities for test resources (containers, networks, volumes)
set -euo pipefail

TEST_LABEL_PREFIX="${TEST_LABEL_PREFIX:-containai.test}"

cleanup_by_session() {
    local session_id="$1"
    local label="${TEST_LABEL_PREFIX}.session=${session_id}"

    docker ps -aq --filter "label=${label}" | xargs -r docker rm -f
    docker network ls -q --filter "label=${label}" | xargs -r docker network rm
    docker volume ls -q --filter "label=${label}" | xargs -r docker volume rm
}

cleanup_orphans() {
    local max_age_hours="${1:-24}"
    local cutoff_ts
    cutoff_ts=$(( $(date +%s) - max_age_hours * 3600 ))

    # Containers
    while IFS= read -r cid; do
        [[ -z "$cid" ]] && continue
        local created
        created=$(docker inspect -f '{{ index .Config.Labels "'"${TEST_LABEL_PREFIX}.created"'" }}' "$cid" 2>/dev/null || echo "")
        if [[ -n "$created" && "$created" =~ ^[0-9]+$ && "$created" -lt "$cutoff_ts" ]]; then
            docker rm -f "$cid" >/dev/null 2>&1 || true
        fi
    done < <(docker ps -aq --filter "label=${TEST_LABEL_PREFIX}.created" 2>/dev/null || true)

    # Networks
    while IFS= read -r nid; do
        [[ -z "$nid" ]] && continue
        local created
        created=$(docker network inspect -f '{{ index .Labels "'"${TEST_LABEL_PREFIX}.created"'" }}' "$nid" 2>/dev/null || echo "")
        if [[ -n "$created" && "$created" =~ ^[0-9]+$ && "$created" -lt "$cutoff_ts" ]]; then
            docker network rm "$nid" >/dev/null 2>&1 || true
        fi
    done < <(docker network ls -q --filter "label=${TEST_LABEL_PREFIX}.created" 2>/dev/null || true)

    # Volumes
    while IFS= read -r vid; do
        [[ -z "$vid" ]] && continue
        local created
        created=$(docker volume inspect -f '{{ index .Labels "'"${TEST_LABEL_PREFIX}.created"'" }}' "$vid" 2>/dev/null || echo "")
        if [[ -n "$created" && "$created" =~ ^[0-9]+$ && "$created" -lt "$cutoff_ts" ]]; then
            docker volume rm "$vid" >/dev/null 2>&1 || true
        fi
    done < <(docker volume ls -q --filter "label=${TEST_LABEL_PREFIX}.created" 2>/dev/null || true)
}
