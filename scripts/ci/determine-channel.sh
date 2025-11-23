#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Determine channel/version for CI and emit outputs for GitHub Actions.

Args:
  --event-name NAME        GitHub event name (push, pull_request, schedule, workflow_dispatch)
  --ref-name REF           Ref name (e.g., main, v1.2.3)
  --dispatch-channel CH    Optional workflow_dispatch channel override
  --dispatch-version VER   Optional workflow_dispatch version override

Outputs (GITHUB_OUTPUT):
  channel, version, immutable_tag (sha-<sha>), moving_tags (newline list), push (true/false)
EOF
}

EVENT_NAME=""
REF_NAME=""
DISPATCH_CHANNEL=""
DISPATCH_VERSION=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --event-name) EVENT_NAME="$2"; shift 2 ;;
        --ref-name) REF_NAME="$2"; shift 2 ;;
        --dispatch-channel) DISPATCH_CHANNEL="$2"; shift 2 ;;
        --dispatch-version) DISPATCH_VERSION="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown arg: $1" >&2; usage >&2; exit 1 ;;
    esac
done

[[ -n "$EVENT_NAME" && -n "$REF_NAME" ]] || { usage >&2; exit 1; }

channel="${DISPATCH_CHANNEL:-}"
version="${DISPATCH_VERSION:-}"

if [[ -z "$channel" ]]; then
    if [[ "$EVENT_NAME" == "schedule" ]]; then
        channel="nightly"
    elif [[ "${GITHUB_REF:-}" == refs/tags/v* ]]; then
        channel="prod"
    else
        channel="dev"
    fi
fi

if [[ -z "$version" ]]; then
    if [[ "$channel" == "prod" && "${GITHUB_REF:-}" == refs/tags/v* ]]; then
        version="$REF_NAME"
    else
        version="$channel"
    fi
fi

immutable_tag="sha-${GITHUB_SHA}"
moving_tags="$channel"
if [[ "$channel" == "prod" && -n "$version" && "$version" != "$channel" ]]; then
    moving_tags="${moving_tags}
${version}"
fi

push_flag="true"
if [[ "$EVENT_NAME" == "pull_request" ]]; then
    push_flag="false"
fi

{
    echo "channel=${channel}"
    echo "version=${version}"
    echo "immutable_tag=${immutable_tag}"
    echo "push=${push_flag}"
    printf "moving_tags<<'EOF'\n%s\nEOF\n" "$moving_tags"
} >> "${GITHUB_OUTPUT}"
