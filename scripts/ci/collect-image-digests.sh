#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Collect image digests for a set of image names and write a JSON array.

Args:
  --images LIST      Comma-separated image names (e.g., containai,containai-copilot)
  --repo-prefix PFX  Registry/repo prefix (e.g., ghcr.io/owner)
  --out PATH         Output file
EOF
}

IMAGES=""
PREFIX=""
OUT_PATH=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --images) IMAGES="$2"; shift 2 ;;
        --repo-prefix) PREFIX="$2"; shift 2 ;;
        --out) OUT_PATH="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown arg: $1" >&2; usage >&2; exit 1 ;;
    esac
done

[[ -n "$IMAGES" && -n "$PREFIX" && -n "$OUT_PATH" ]] || { usage >&2; exit 1; }

mkdir -p "$(dirname "$OUT_PATH")"
mapfile -t image_arr < <(echo "$IMAGES" | tr ',' '\n' | sed '/^$/d')
json_entries=()

for img in "${image_arr[@]}"; do
    full="${PREFIX}/${img}"
    digest="$(docker inspect --format='{{index .RepoDigests 0}}' "$full" | cut -d@ -f2 || true)"
    if [[ -z "$digest" ]]; then
        echo "Digest not found for $full" >&2
        exit 1
    fi
    json_entries+=("{\"image\":\"${img}\",\"repository\":\"${PREFIX}/${img%:*}\",\"digest\":\"${digest}\"}")
done

printf '[%s]\n' "$(IFS=,; echo "${json_entries[*]}")" > "$OUT_PATH"
