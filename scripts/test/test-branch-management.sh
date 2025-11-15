#!/usr/bin/env bash
# Comprehensive test suite for branch management features
# Tests branch conflict detection, archiving, unmerged commits, and cleanup

set -euo pipefail

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Test session ID for complete isolation
TEST_SESSION_ID="$$"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEST_REPO_DIR="/tmp/test-branch-mgmt-${TEST_SESSION_ID}"
FAILED_TESTS=0
PASSED_TESTS=0

# Source common functions to test
source "$SCRIPT_DIR/../utils/common-functions.sh"

# ============================================================================
# Docker Detection and Setup
# ============================================================================

check_docker_available() {
    docker version >/dev/null 2>&1
    return $?
}

start_docker_if_needed() {
    if check_docker_available; then
        return 0
    fi
    
    echo -e "${YELLOW}Docker is not running. Checking if Docker is installed...${NC}"
    
    # Check if docker command exists
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}❌ Docker is not installed. Please install Docker from:${NC}"
        echo -e "${GREEN}   https://www.docker.com/products/docker-desktop${NC}"
        return 1
    fi
    
    echo -e "${YELLOW}Docker is installed but not running.${NC}"
    echo -e "${YELLOW}Please start Docker Desktop and try again.${NC}"
    return 1
}

# ============================================================================
# Cleanup and Setup Functions
# ============================================================================

cleanup() {
    echo ""
    echo "🧹 Cleaning up test resources..."
    
    # Remove test containers
    docker ps -aq --filter "label=coding-agents.test-session=${TEST_SESSION_ID}" | xargs -r docker rm -f 2>/dev/null || true
    
    # Remove test networks
    docker network ls --filter "name=test-branch-mgmt-${TEST_SESSION_ID}" --format "{{.Name}}" | xargs -r docker network rm 2>/dev/null || true
    
    # Remove test repository
    rm -rf "$TEST_REPO_DIR"
    
    print_test_summary
    
    [ $FAILED_TESTS -gt 0 ] && exit 1 || exit 0
}

trap cleanup EXIT

print_test_summary() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Branch Management Test Results:"
    echo "  ✅ Passed: $PASSED_TESTS"
    echo "  ❌ Failed: $FAILED_TESTS"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

setup_test_repo() {
    echo ""
    echo "Setting up isolated test repository..."
    
    rm -rf "$TEST_REPO_DIR"
    mkdir -p "$TEST_REPO_DIR"
    cd "$TEST_REPO_DIR"
    
    # Initialize git with test configuration
    git init -q
    git config user.name "Test User"
    git config user.email "test@example.com"
    
    # Create initial commit
    echo "# Test Repository $TEST_SESSION_ID" > README.md
    git add README.md
    git commit -q -m "Initial commit"
    git branch -M main
    
    echo "✅ Test repository created at $TEST_REPO_DIR"
}

# ============================================================================
# Assertion Helper Functions
# ============================================================================

pass() {
    echo -e "${GREEN}✓${NC} $1"
    ((PASSED_TESTS++)) || true
}

fail() {
    echo -e "${RED}✗${NC} $1"
    ((FAILED_TESTS++)) || true
}

test_section() {
    echo ""
    echo -e "${YELLOW}━━━ $1 ━━━${NC}"
}

assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="$3"
    
    if [ "$expected" = "$actual" ]; then
        pass "$message"
    else
        fail "$message (expected: '$expected', got: '$actual')"
    fi
}

assert_branch_exists() {
    local repo_path="$1"
    local branch_name="$2"
    
    if branch_exists "$repo_path" "$branch_name"; then
        pass "Branch exists: $branch_name"
    else
        fail "Branch does not exist: $branch_name"
    fi
}

assert_branch_not_exists() {
    local repo_path="$1"
    local branch_name="$2"
    
    if ! branch_exists "$repo_path" "$branch_name"; then
        pass "Branch does not exist: $branch_name"
    else
        fail "Branch exists when it shouldn't: $branch_name"
    fi
}

# ============================================================================
# Branch Management Function Tests
# ============================================================================

test_branch_exists_function() {
    test_section "Testing branch_exists function"
    
    cd "$TEST_REPO_DIR"
    
    # Test existing branch
    if branch_exists "$TEST_REPO_DIR" "main"; then
        pass "branch_exists correctly identifies existing branch"
    else
        fail "branch_exists failed to identify existing branch"
    fi
    
    # Test non-existing branch
    if ! branch_exists "$TEST_REPO_DIR" "nonexistent"; then
        pass "branch_exists correctly identifies non-existing branch"
    else
        fail "branch_exists incorrectly identified non-existing branch"
    fi
}

test_create_git_branch() {
    test_section "Testing create_git_branch function"
    
    cd "$TEST_REPO_DIR"
    
    # Create new branch
    if create_git_branch "$TEST_REPO_DIR" "test-branch"; then
        pass "create_git_branch successfully created branch"
        assert_branch_exists "$TEST_REPO_DIR" "test-branch"
    else
        fail "create_git_branch failed to create branch"
    fi
    
    # Create branch from specific commit
    local commit_sha=$(git rev-parse HEAD)
    if create_git_branch "$TEST_REPO_DIR" "test-branch-2" "$commit_sha"; then
        pass "create_git_branch created branch from specific commit"
        assert_branch_exists "$TEST_REPO_DIR" "test-branch-2"
    else
        fail "create_git_branch failed to create branch from commit"
    fi
}

test_rename_git_branch() {
    test_section "Testing rename_git_branch function"
    
    cd "$TEST_REPO_DIR"
    
    # Create a branch to rename
    create_git_branch "$TEST_REPO_DIR" "branch-to-rename"
    
    # Rename it
    if rename_git_branch "$TEST_REPO_DIR" "branch-to-rename" "renamed-branch"; then
        pass "rename_git_branch successfully renamed branch"
        assert_branch_not_exists "$TEST_REPO_DIR" "branch-to-rename"
        assert_branch_exists "$TEST_REPO_DIR" "renamed-branch"
    else
        fail "rename_git_branch failed to rename branch"
    fi
}

test_remove_git_branch() {
    test_section "Testing remove_git_branch function"
    
    cd "$TEST_REPO_DIR"
    
    # Create a branch to remove
    create_git_branch "$TEST_REPO_DIR" "branch-to-remove"
    assert_branch_exists "$TEST_REPO_DIR" "branch-to-remove"
    
    # Remove it
    if remove_git_branch "$TEST_REPO_DIR" "branch-to-remove" "true"; then
        pass "remove_git_branch successfully removed branch"
        assert_branch_not_exists "$TEST_REPO_DIR" "branch-to-remove"
    else
        fail "remove_git_branch failed to remove branch"
    fi
}

test_get_unmerged_commits() {
    test_section "Testing get_unmerged_commits function"
    
    cd "$TEST_REPO_DIR"
    
    # Create feature branch with unmerged commits
    git checkout -q main
    create_git_branch "$TEST_REPO_DIR" "feature-branch"
    git checkout -q feature-branch
    
    echo "Feature work" > feature.txt
    git add feature.txt
    git commit -q -m "Feature commit 1"
    
    echo "More feature work" >> feature.txt
    git add feature.txt
    git commit -q -m "Feature commit 2"
    
    git checkout -q main
    
    # Check for unmerged commits
    local unmerged=$(get_unmerged_commits "$TEST_REPO_DIR" "main" "feature-branch")
    
    if [ -n "$unmerged" ]; then
        pass "get_unmerged_commits detected unmerged commits"
        
        # Verify it found 2 commits
        local commit_count=$(echo "$unmerged" | wc -l)
        if [ "$commit_count" -eq 2 ]; then
            pass "get_unmerged_commits found correct number of commits (2)"
        else
            fail "get_unmerged_commits found $commit_count commits, expected 2"
        fi
    else
        fail "get_unmerged_commits failed to detect unmerged commits"
    fi
    
    # Test with merged branch
    git merge -q --no-edit feature-branch
    create_git_branch "$TEST_REPO_DIR" "merged-branch"
    
    local merged=$(get_unmerged_commits "$TEST_REPO_DIR" "main" "merged-branch")
    if [ -z "$merged" ]; then
        pass "get_unmerged_commits correctly reports no unmerged commits"
    else
        fail "get_unmerged_commits incorrectly reported unmerged commits on merged branch"
    fi
}

test_agent_branch_isolation() {
    test_section "Testing agent branch isolation"
    
    cd "$TEST_REPO_DIR"
    git checkout -q main
    
    # Create agent-specific branches
    create_git_branch "$TEST_REPO_DIR" "copilot/main"
    create_git_branch "$TEST_REPO_DIR" "codex/main"
    create_git_branch "$TEST_REPO_DIR" "claude/main"
    
    assert_branch_exists "$TEST_REPO_DIR" "copilot/main"
    assert_branch_exists "$TEST_REPO_DIR" "codex/main"
    assert_branch_exists "$TEST_REPO_DIR" "claude/main"
    
    pass "Multiple agent branches coexist successfully"
}

test_branch_archiving_with_timestamp() {
    test_section "Testing branch archiving with timestamp"
    
    cd "$TEST_REPO_DIR"
    git checkout -q main
    
    # Create branch with work
    create_git_branch "$TEST_REPO_DIR" "copilot/feature"
    git checkout -q copilot/feature
    echo "Work" > work.txt
    git add work.txt
    git commit -q -m "Some work"
    git checkout -q main
    
    # Archive it with timestamp
    local timestamp=$(date +%Y%m%d-%H%M%S)
    local archive_name="copilot/feature-archived-${timestamp}"
    
    if rename_git_branch "$TEST_REPO_DIR" "copilot/feature" "$archive_name"; then
        pass "Branch archived with timestamp"
        assert_branch_not_exists "$TEST_REPO_DIR" "copilot/feature"
        assert_branch_exists "$TEST_REPO_DIR" "$archive_name"
    else
        fail "Failed to archive branch with timestamp"
    fi
}

test_container_branch_cleanup() {
    test_section "Testing container branch cleanup integration"
    
    cd "$TEST_REPO_DIR"
    git checkout -q main
    
    # Create agent branch
    create_git_branch "$TEST_REPO_DIR" "copilot/cleanup-test"
    
    # Create test container with labels
    local container_name="copilot-test-cleanup-${TEST_SESSION_ID}"
    docker run -d \
        --name "$container_name" \
        --label "coding-agents.test-session=${TEST_SESSION_ID}" \
        --label "coding-agents.type=agent" \
        --label "coding-agents.branch=copilot/cleanup-test" \
        --label "coding-agents.repo-path=$TEST_REPO_DIR" \
        alpine:latest sleep 60 >/dev/null
    
    # Simulate removal with branch cleanup
    remove_container_with_sidecars "$container_name" "true" "false"
    
    # Verify branch was cleaned up
    assert_branch_not_exists "$TEST_REPO_DIR" "copilot/cleanup-test"
}

test_preserve_branch_with_unmerged_commits() {
    test_section "Testing preservation of branches with unmerged commits"
    
    cd "$TEST_REPO_DIR"
    git checkout -q main
    
    # Create branch with unmerged work
    create_git_branch "$TEST_REPO_DIR" "copilot/preserve-test"
    git checkout -q copilot/preserve-test
    echo "Important work" > important.txt
    git add important.txt
    git commit -q -m "Important commit"
    git checkout -q main
    
    # Create container
    local container_name="copilot-test-preserve-${TEST_SESSION_ID}"
    docker run -d \
        --name "$container_name" \
        --label "coding-agents.test-session=${TEST_SESSION_ID}" \
        --label "coding-agents.type=agent" \
        --label "coding-agents.branch=copilot/preserve-test" \
        --label "coding-agents.repo-path=$TEST_REPO_DIR" \
        alpine:latest sleep 60 >/dev/null
    
    # Remove container (should preserve branch due to unmerged commits)
    remove_container_with_sidecars "$container_name" "true" "false" 2>/dev/null || true
    
    # Verify branch still exists
    assert_branch_exists "$TEST_REPO_DIR" "copilot/preserve-test"
}

# ============================================================================
# Run All Tests
# ============================================================================

main() {
    echo "🧪 Starting Branch Management Test Suite"
    echo "Session ID: $TEST_SESSION_ID"
    
    # Check Docker availability
    if ! start_docker_if_needed; then
        echo -e "${RED}❌ Cannot run tests without Docker${NC}"
        exit 1
    fi
    
    # Setup
    setup_test_repo
    
    # Run all tests
    test_branch_exists_function
    test_create_git_branch
    test_rename_git_branch
    test_remove_git_branch
    test_get_unmerged_commits
    test_agent_branch_isolation
    test_branch_archiving_with_timestamp
    test_container_branch_cleanup
    test_preserve_branch_with_unmerged_commits
    
    echo ""
    echo "✅ All branch management tests completed"
}

main
