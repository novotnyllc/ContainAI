#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
    cat <<'EOF'
Usage: write-profile-env.sh --prefix NAME --tag TAG --owner OWNER --out PATH

Resolves image digests for a prefix/tag and writes host/profile.env with pinned digests.
Images: <prefix>, <prefix>-copilot, <prefix>-codex, <prefix>-claude, <prefix>-proxy, <prefix>-log-forwarder
EOF
}

PREFIX=""
TAG=""
OWNER=""
OUT_PATH=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --prefix) PREFIX="$2"; shift 2 ;;
        --tag) TAG="$2"; shift 2 ;;
        --owner) OWNER="$2"; shift 2 ;;
        --out) OUT_PATH="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown arg: $1" >&2; usage >&2; exit 1 ;;
    esac
done

[[ -n "$PREFIX" && -n "$TAG" && -n "$OWNER" && -n "$OUT_PATH" ]] || { usage >&2; exit 1; }

images=(
    "${PREFIX}:${TAG}"
    "${PREFIX}-copilot:${TAG}"
    "${PREFIX}-codex:${TAG}"
    "${PREFIX}-claude:${TAG}"
    "${PREFIX}-proxy:${TAG}"
    "${PREFIX}-log-forwarder:${TAG}"
)

tmp_json="$(mktemp)"
scripts/ci/collect-image-digests.sh \
    --images "$(IFS=,; echo "${images[*]}")" \
    --repo-prefix "ghcr.io/${OWNER}" \
    --out "$tmp_json"
declare -A digests
while IFS= read -r row; do
    name=$(echo "$row" | jq -r '.image')
    digest=$(echo "$row" | jq -r '.digest')
    [[ -n "$name" && -n "$digest" ]] || continue
    digests["$name"]="$digest"
done < <(jq -c '.[]' "$tmp_json")
rm -f "$tmp_json"

mkdir -p "$(dirname "$OUT_PATH")"
{
    echo "PROFILE=prod"
    echo "IMAGE_PREFIX=${PREFIX}"
    echo "IMAGE_TAG=${TAG}"
    echo "REGISTRY=ghcr.io/${OWNER}"
    echo "IMAGE_DIGEST=${digests["${PREFIX}:${TAG}"]}"
    echo "IMAGE_DIGEST_COPILOT=${digests["${PREFIX}-copilot:${TAG}"]}"
    echo "IMAGE_DIGEST_CODEX=${digests["${PREFIX}-codex:${TAG}"]}"
    echo "IMAGE_DIGEST_CLAUDE=${digests["${PREFIX}-claude:${TAG}"]}"
    echo "IMAGE_DIGEST_PROXY=${digests["${PREFIX}-proxy:${TAG}"]}"
    echo "IMAGE_DIGEST_LOG_FORWARDER=${digests["${PREFIX}-log-forwarder:${TAG}"]}"
} > "$OUT_PATH"
