#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Write channels.json for installer metadata.

Args:
  --channel NAME
  --version VERSION
  --immutable TAG
  --moving-tags TEXT      Newline-separated moving tags
  --images-json JSON      JSON array of {"image","repository","digest"}
  --payload-ref REF
  --payload-digest DIGEST
  --out PATH              Output file
EOF
}

CHANNEL=""
VERSION=""
IMMUTABLE=""
MOVING_TAGS=""
IMAGES_JSON=""
PAYLOAD_REF=""
PAYLOAD_DIGEST=""
OUT_PATH=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --channel) CHANNEL="$2"; shift 2 ;;
        --version) VERSION="$2"; shift 2 ;;
        --immutable) IMMUTABLE="$2"; shift 2 ;;
        --moving-tags) MOVING_TAGS="$2"; shift 2 ;;
        --images-json) IMAGES_JSON="$2"; shift 2 ;;
        --payload-ref) PAYLOAD_REF="$2"; shift 2 ;;
        --payload-digest) PAYLOAD_DIGEST="$2"; shift 2 ;;
        --out) OUT_PATH="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown arg: $1" >&2; usage >&2; exit 1 ;;
    esac
done

[[ -n "$IMAGES_JSON" && -n "$OUT_PATH" ]] || { usage >&2; exit 1; }

if ! command -v jq >/dev/null 2>&1; then
    echo "❌ jq is required but not found." >&2
    exit 1
fi

echo "$IMAGES_JSON" | jq -e . >/dev/null 2>&1 || { echo "❌ Invalid JSON in IMAGES_JSON" >&2; exit 1; }

moving_json=$(printf '%s\n' "$MOVING_TAGS" | jq -R -s 'split("\n")|map(select(length>0))')
images_compact=$(echo "$IMAGES_JSON" | jq -c '.')
generated="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

jq -n \
  --arg channel "$CHANNEL" \
  --arg version "$VERSION" \
  --arg immutable "$IMMUTABLE" \
  --argjson moving "$moving_json" \
  --argjson images "$images_compact" \
  --arg payload_ref "$PAYLOAD_REF" \
  --arg payload_digest "$PAYLOAD_DIGEST" \
  --arg generated "$generated" \
  '{channel:$channel,version:$version,immutable_tag:$immutable,moving_tags:$moving,images:$images,payload:{ref:$payload_ref,digest:$payload_digest},generated_at:$generated}' \
  > "$OUT_PATH"
