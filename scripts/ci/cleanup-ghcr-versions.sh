#!/usr/bin/env bash
# Cleanup old container package versions from ghcr.io with production retention policy.
# Keeps:
#   - All versions updated within the last 6 months
#   - All prod-tagged versions within 6 months, plus the latest prod regardless of age
#   - Newest N non-prod versions (configured per package)
set -euo pipefail

: "${GH_TOKEN:?GH_TOKEN is required}"
: "${OWNER:?OWNER is required}"

cutoff_ts=$(date -u -d '180 days ago' +%s)

# Minimum versions to keep per package (non-prod)
declare -A min_keep=(
  [containai]=15
  [containai-base]=10
  [containai-copilot]=10
  [containai-codex]=10
  [containai-claude]=10
  [containai-proxy]=10
  [containai-log-forwarder]=10
  [containai-payload]=10
  [containai-metadata]=10
)

fetch_versions() {
  local pkg="$1"
  local res
  if res=$(gh api -H "Accept: application/vnd.github+json" \
    "/orgs/${OWNER}/packages/container/${pkg}/versions?per_page=100" 2>/dev/null); then
    echo "$res"
  else
    gh api -H "Accept: application/vnd.github+json" \
      "/user/packages/container/${pkg}/versions?per_page=100"
  fi
}

for pkg in "${!min_keep[@]}"; do
  echo "Processing $pkg..."
  json=$(fetch_versions "$pkg") || { echo "Failed to list versions for $pkg" >&2; continue; }
  count=$(jq 'length' <<<"$json")
  if [[ "$count" -eq 0 ]]; then
    echo "No versions for $pkg"
    continue
  fi

  prod_entries=$(jq -r '[.[] | {id:.id, updated:(.updated_at|fromdate), tags:(.metadata.container.tags // [])}]' <<<"$json")
  latest_prod_id=$(jq -r 'map(select(.tags|index("prod"))) | max_by(.updated) | .id // empty' <<<"$prod_entries")
  keep_ids=()

  # Keep anything updated within the last 6 months
  while IFS= read -r id; do
    keep_ids+=("$id")
  done < <(jq -r --argjson cutoff "$cutoff_ts" '.[] | select(.updated >= $cutoff) | .id' <<<"$prod_entries")

  # Keep prod-tagged within 6 months or latest prod regardless of age
  while IFS= read -r id; do
    keep_ids+=("$id")
  done < <(jq -r --argjson cutoff "$cutoff_ts" --arg latest "$latest_prod_id" \
    '.[] | select((.tags|index("prod")) and ((.updated >= $cutoff) or (.id == ($latest|tonumber)))) | .id' \
    <<<"$prod_entries")

  # Non-prod retention: keep newest N
  keep_nonprod=$(jq -r --argjson n "${min_keep[$pkg]}" \
    '[.[] | select(.tags|index("prod")|not) | {id, updated}] | sort_by(.updated) | reverse | .[:$n] | .[].id' \
    <<<"$prod_entries")
  while IFS= read -r id; do
    [[ -n "$id" ]] && keep_ids+=("$id")
  done <<<"$keep_nonprod"

  # Deduplicate keep_ids
  declare -A keep_map=()
  for id in "${keep_ids[@]}"; do
    keep_map[$id]=1
  done

  delete_ids=()
  while IFS= read -r id; do
    [[ -z "$id" ]] && continue
    if [[ -z "${keep_map[$id]:-}" ]]; then
      delete_ids+=("$id")
    fi
  done < <(jq -r '.[].id' <<<"$prod_entries")

  for id in "${delete_ids[@]}"; do
    echo "Deleting $pkg version $id"
    gh api --method DELETE \
      "/orgs/${OWNER}/packages/container/${pkg}/versions/${id}" 2>/dev/null \
      || gh api --method DELETE \
        "/user/packages/container/${pkg}/versions/${id}" 2>/dev/null \
      || echo "⚠️  Failed to delete $pkg version $id" >&2
  done
  
  # Reset keep_map for next iteration
  unset keep_map
done

echo "✓ Container version cleanup complete"
