#!/usr/bin/env bash
# Cleanup stale GitHub Actions cache entries.
# GitHub Actions cache has a 10GB limit per repo. With multi-arch builds and many scopes,
# cache can balloon to 20GB+. This script aggressively prunes old cache entries.
set -euo pipefail

: "${GH_TOKEN:?GH_TOKEN is required}"
: "${REPO:?REPO is required}"

# Configuration
MAX_AGE_DAYS="${MAX_AGE_DAYS:-7}"
SIZE_THRESHOLD_GB="${SIZE_THRESHOLD_GB:-8}"
SIZE_THRESHOLD_BYTES=$((SIZE_THRESHOLD_GB * 1073741824))

echo "🧹 Cleaning up stale GitHub Actions cache entries..."

# Get current cache usage
cache_list=$(gh cache list --repo "$REPO" --json id,key,createdAt,sizeInBytes --limit 100 2>/dev/null || echo "[]")
total_size=$(echo "$cache_list" | jq '[.[].sizeInBytes] | add // 0')
total_size_gb=$(echo "scale=2; $total_size / 1073741824" | bc)
echo "Current cache usage: ${total_size_gb}GB"

# Delete caches older than MAX_AGE_DAYS
cutoff_date=$(date -u -d "${MAX_AGE_DAYS} days ago" +%Y-%m-%dT%H:%M:%SZ)
old_caches=$(echo "$cache_list" | jq -r --arg cutoff "$cutoff_date" '.[] | select(.createdAt < $cutoff) | .id')

deleted_count=0
for cache_id in $old_caches; do
  echo "Deleting old cache: $cache_id"
  if gh cache delete "$cache_id" --repo "$REPO" 2>/dev/null; then
    ((deleted_count++)) || true
  fi
done

# If still over threshold, delete oldest caches until under threshold
if (( $(echo "$total_size > $SIZE_THRESHOLD_BYTES" | bc -l) )); then
  echo "Cache over ${SIZE_THRESHOLD_GB}GB threshold, deleting oldest entries..."
  oldest_caches=$(echo "$cache_list" | jq -r 'sort_by(.createdAt) | .[0:10] | .[].id')
  for cache_id in $oldest_caches; do
    echo "Deleting cache to free space: $cache_id"
    gh cache delete "$cache_id" --repo "$REPO" 2>/dev/null || true
    ((deleted_count++)) || true
  done
fi

echo "✓ Deleted $deleted_count cache entries"

# Report final usage
final_list=$(gh cache list --repo "$REPO" --json sizeInBytes --limit 100 2>/dev/null || echo "[]")
final_size=$(echo "$final_list" | jq '[.[].sizeInBytes] | add // 0')
final_size_gb=$(echo "scale=2; $final_size / 1073741824" | bc)
echo "Final cache usage: ${final_size_gb}GB"
