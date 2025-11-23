#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Apply moving tags to image digests using docker buildx imagetools.

Args:
  --digests PATH          JSON array of {"image","repository","digest"}
  --immutable-tag TAG     Immutable tag (e.g., sha-<sha>)
  --moving-tags TEXT      Newline-separated moving tags (e.g., dev\nnightly)
EOF
}

DIGESTS_PATH=""
IMMUTABLE_TAG=""
MOVING_TAGS=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --digests) DIGESTS_PATH="$2"; shift 2 ;;
        --immutable-tag) IMMUTABLE_TAG="$2"; shift 2 ;;
        --moving-tags) MOVING_TAGS="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown arg: $1" >&2; usage >&2; exit 1 ;;
    esac
done

[[ -n "$DIGESTS_PATH" && -n "$IMMUTABLE_TAG" ]] || { usage >&2; exit 1; }

mapfile -t moving <<< "$(printf '%s\n' "$MOVING_TAGS" | sed '/^$/d')"

while IFS= read -r row; do
    repo=$(echo "$row" | jq -r '.repository')
    digest=$(echo "$row" | jq -r '.digest')
    [[ -n "$repo" && -n "$digest" ]] || continue
    args=(--tag "${repo}:${IMMUTABLE_TAG}")
    for tag in "${moving[@]}"; do
        args+=(--tag "${repo}:${tag}")
    done
    docker buildx imagetools create "${args[@]}" "${repo}@${digest}"
done < <(jq -c '.[]' "$DIGESTS_PATH")
