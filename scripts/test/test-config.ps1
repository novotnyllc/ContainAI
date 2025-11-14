# Test configuration - no real secrets required
# This file is sourced by test scripts to provide isolated test environment

# Test registry (local, no push to real registry)
$env:TEST_REGISTRY = "localhost:5555"
$env:TEST_IMAGE_PREFIX = "test-coding-agents"

# Test images (will be built or pulled)
$env:TEST_BASE_IMAGE = "$env:TEST_REGISTRY/$env:TEST_IMAGE_PREFIX/base:test"
$env:TEST_COPILOT_IMAGE = "$env:TEST_REGISTRY/$env:TEST_IMAGE_PREFIX/copilot:test"
$env:TEST_CODEX_IMAGE = "$env:TEST_REGISTRY/$env:TEST_IMAGE_PREFIX/codex:test"
$env:TEST_CLAUDE_IMAGE = "$env:TEST_REGISTRY/$env:TEST_IMAGE_PREFIX/claude:test"

# Test repository location
$env:TEST_REPO_DIR = Join-Path $env:TEMP "test-coding-agents-repo-$PID"
$env:TEST_WORKSPACE_DIR = Join-Path $env:TEMP "test-coding-agents-workspace-$PID"

# Test Docker network (isolated)
$env:TEST_NETWORK = "test-coding-agents-net-$PID"

# Test container prefix
$env:TEST_CONTAINER_PREFIX = "test-agent-$PID"

# Mock credentials (no real secrets)
$env:TEST_GH_TOKEN = "ghp_test_token_not_real_1234567890abcdef"
$env:TEST_GH_USER = "test-user"
$env:TEST_GH_EMAIL = "test@example.com"

# Test labels
$env:TEST_LABEL_TEST = "coding-agents.test=true"
$env:TEST_LABEL_SESSION = "coding-agents.test-session=$PID"

# Cleanup preference (override with -Preserve flag)
if (-not $env:TEST_PRESERVE_RESOURCES) {
    $env:TEST_PRESERVE_RESOURCES = "false"
}

# Test mode (full or launchers)
if (-not $env:TEST_MODE) {
    $env:TEST_MODE = "launchers"
}

# Local registry container name
$env:TEST_REGISTRY_CONTAINER = "test-registry-$PID"

# Disable launcher update checks during automated tests
$env:CODING_AGENTS_SKIP_UPDATE_CHECK = "1"

Write-Host "Test configuration loaded:" -ForegroundColor Cyan
Write-Host "  Mode: $env:TEST_MODE" -ForegroundColor White
Write-Host "  Registry: $env:TEST_REGISTRY" -ForegroundColor White
Write-Host "  Network: $env:TEST_NETWORK" -ForegroundColor White
Write-Host "  Preserve resources: $env:TEST_PRESERVE_RESOURCES" -ForegroundColor White
Write-Host "  Session ID: $PID" -ForegroundColor White
