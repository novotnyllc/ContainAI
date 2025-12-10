#!/usr/bin/env bash
# Run the integration test suite directly on the host Docker daemon (no DinD)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
INTEGRATION_SCRIPT="$PROJECT_ROOT/scripts/test/integration-test-impl.sh"

# Helpers
# shellcheck source=scripts/test/test-labels.sh disable=SC1091
source "$SCRIPT_DIR/test-labels.sh"
# shellcheck source=scripts/test/cleanup-test-resources.sh disable=SC1091
source "$SCRIPT_DIR/cleanup-test-resources.sh"

SESSION_ID="$(generate_session_id)"
CREATED_TS="$(current_timestamp)"

# Export session context for downstream tests
export TEST_SESSION_ID="$SESSION_ID"
export TEST_CREATED_TS="$CREATED_TS"
export TEST_LABEL_PREFIX="${TEST_LABEL_PREFIX:-containai.test}"
export TEST_LABEL_SESSION="${TEST_LABEL_PREFIX}.session=${SESSION_ID}"
export TEST_LABEL_CREATED="${TEST_LABEL_PREFIX}.created=${CREATED_TS}"
export TEST_LABEL_TEST="${TEST_LABEL_TEST:-${TEST_LABEL_PREFIX}.test=true}"

require_docker() {
    if ! command -v docker >/dev/null 2>&1; then
        echo "❌ Docker CLI not found; install and start Docker before running integration tests." >&2
        exit 1
    fi
    if ! docker info >/dev/null 2>&1; then
        echo "❌ Docker daemon is not reachable; start Docker and retry." >&2
        exit 1
    fi
}

cleanup_session() {
    if [[ "${TEST_PRESERVE_RESOURCES:-false}" == "true" ]]; then
        echo "Preserving test resources (TEST_PRESERVE_RESOURCES=true)"
        return
    fi
    cleanup_by_session "$SESSION_ID"
}

require_docker

# Pre-run cleanup and scoped trap
cleanup_orphans 24
trap cleanup_session EXIT

# Forward all arguments to the implementation script on host Docker
exec "$INTEGRATION_SCRIPT" "$@"
