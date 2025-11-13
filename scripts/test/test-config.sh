#!/usr/bin/env bash
# Test configuration - no real secrets required
# This file is sourced by test scripts to provide isolated test environment

# Test registry (local, no push to real registry)
export TEST_REGISTRY="localhost:5555"
export TEST_IMAGE_PREFIX="test-coding-agents"

# Test images (will be built or pulled)
export TEST_BASE_IMAGE="${TEST_REGISTRY}/${TEST_IMAGE_PREFIX}/base:test"
export TEST_COPILOT_IMAGE="${TEST_REGISTRY}/${TEST_IMAGE_PREFIX}/copilot:test"
export TEST_CODEX_IMAGE="${TEST_REGISTRY}/${TEST_IMAGE_PREFIX}/codex:test"
export TEST_CLAUDE_IMAGE="${TEST_REGISTRY}/${TEST_IMAGE_PREFIX}/claude:test"

# Test repository location
export TEST_REPO_DIR="/tmp/test-coding-agents-repo-$$"
export TEST_WORKSPACE_DIR="/tmp/test-coding-agents-workspace-$$"

# Test Docker network (isolated)
export TEST_NETWORK="test-coding-agents-net-$$"

# Test container prefix
export TEST_CONTAINER_PREFIX="test-agent-$$"

# Mock credentials (no real secrets)
export TEST_GH_TOKEN="ghp_test_token_not_real_1234567890abcdef"
export TEST_GH_USER="test-user"
export TEST_GH_EMAIL="test@example.com"

# Test labels
export TEST_LABEL_TEST="coding-agents.test=true"
export TEST_LABEL_SESSION="coding-agents.test-session=$$"

# Cleanup preference (override with --preserve flag)
export TEST_PRESERVE_RESOURCES="${TEST_PRESERVE_RESOURCES:-false}"

# Test mode (full or launchers)
export TEST_MODE="${TEST_MODE:-launchers}"

# Local registry container name
export TEST_REGISTRY_CONTAINER="test-registry-$$"

echo "Test configuration loaded:"
echo "  Mode: $TEST_MODE"
echo "  Registry: $TEST_REGISTRY"
echo "  Network: $TEST_NETWORK"
echo "  Preserve resources: $TEST_PRESERVE_RESOURCES"
echo "  Session ID: $$"
