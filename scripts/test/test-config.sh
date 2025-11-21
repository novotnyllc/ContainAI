#!/usr/bin/env bash
# Test configuration - no real secrets required
# This file is sourced by test scripts to provide isolated test environment

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Fixture locations (copied into isolated workspace)
export TEST_FIXTURES_DIR="$SCRIPT_DIR/fixtures"
export TEST_MOCK_SECRETS_DIR="$TEST_FIXTURES_DIR/mock-secrets"

# Test registry (local, no push to real registry)
export TEST_REGISTRY="localhost:5555"
export TEST_IMAGE_PREFIX="test-containai"

# Test images (will be built or pulled)
export TEST_BASE_IMAGE="${TEST_REGISTRY}/${TEST_IMAGE_PREFIX}/base:test"
export TEST_COPILOT_IMAGE="${TEST_REGISTRY}/${TEST_IMAGE_PREFIX}/copilot:test"
export TEST_CODEX_IMAGE="${TEST_REGISTRY}/${TEST_IMAGE_PREFIX}/codex:test"
export TEST_CLAUDE_IMAGE="${TEST_REGISTRY}/${TEST_IMAGE_PREFIX}/claude:test"

# Test repository location
export TEST_REPO_DIR="/tmp/test-containai-repo-$$"
export TEST_WORKSPACE_DIR="/tmp/test-containai-workspace-$$"

# Test Docker network (isolated)
export TEST_NETWORK="test-containai-net-$$"
export TEST_PROXY_NETWORK="test-containai-proxy-net-$$"
export TEST_PROXY_CONTAINER="test-containai-proxy-$$"

# Test container prefix
export TEST_CONTAINER_PREFIX="test-agent-$$"

# Mock credentials (no real secrets)
export TEST_GH_TOKEN="ghp_test_token_not_real_1234567890abcdef"
export TEST_GH_USER="test-user"
export TEST_GH_EMAIL="test@example.com"

# Test labels
export TEST_LABEL_TEST="containai.test=true"
export TEST_LABEL_SESSION="containai.test-session=$$"

# Cleanup preference (override with --preserve flag)
export TEST_PRESERVE_RESOURCES="${TEST_PRESERVE_RESOURCES:-false}"

# Test mode (full or launchers)
export TEST_MODE="${TEST_MODE:-launchers}"

# Local registry container name
export TEST_REGISTRY_CONTAINER="test-registry-$$"

# Source registry for pulling images (if available)
export TEST_SOURCE_REGISTRY="${TEST_SOURCE_REGISTRY:-ghcr.io/yourusername}"

# Whether to use registry pulls (set to false to skip pushes in offline mode)
export TEST_USE_REGISTRY_PULLS="${TEST_USE_REGISTRY_PULLS:-true}"

# Disable launcher update checks during automated tests
export CONTAINAI_SKIP_UPDATE_CHECK=1

echo "Test configuration loaded:"
echo "  Mode: $TEST_MODE"
echo "  Registry: $TEST_REGISTRY"
echo "  Network: $TEST_NETWORK"
echo "  Proxy network: $TEST_PROXY_NETWORK"
echo "  Preserve resources: $TEST_PRESERVE_RESOURCES"
echo "  Session ID: $$"
