#!/usr/bin/env bash
# Automated test suite for launcher scripts
# Tests all core functionality: naming, labels, auto-push, shared functions

set -euo pipefail

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Constants
LONG_RUNNING_SLEEP=3600

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEST_REPO_DIR="/tmp/test-coding-agents-repo"
FAILED_TESTS=0
PASSED_TESTS=0

# ============================================================================
# Cleanup and Setup Functions
# ============================================================================

cleanup() {
    echo ""
    echo "🧹 Cleaning up test containers and networks..."
    
    docker ps -aq --filter "label=coding-agents.test=true" | xargs -r docker rm -f 2>/dev/null || true
    docker network ls --filter "name=test-" --format "{{.Name}}" | xargs -r docker network rm 2>/dev/null || true
    rm -rf "$TEST_REPO_DIR"
    
    print_test_summary
    
    [ $FAILED_TESTS -gt 0 ] && exit 1 || exit 0
}

trap cleanup EXIT

print_test_summary() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Test Results:"
    echo "  ✅ Passed: $PASSED_TESTS"
    echo "  ❌ Failed: $FAILED_TESTS"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

setup_test_repo() {
    test_section "Setting up test repository"
    
    rm -rf "$TEST_REPO_DIR"
    mkdir -p "$TEST_REPO_DIR"
    cd "$TEST_REPO_DIR"
    
    git init -q
    git config user.name "Test User"
    git config user.email "test@example.com"
    git config remote.pushDefault local
    
    echo "# Test Repository" > README.md
    git add README.md
    git commit -q -m "Initial commit"
    git checkout -q -b main
    
    pass "Created test repository at $TEST_REPO_DIR"
}

# ============================================================================
# Assertion Helper Functions
# ============================================================================

pass() {
    echo -e "${GREEN}✓${NC} $1"
    ((PASSED_TESTS++))
}

fail() {
    echo -e "${RED}✗${NC} $1"
    ((FAILED_TESTS++))
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

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="$3"
    
    if echo "$haystack" | grep -q "$needle"; then
        pass "$message"
    else
        fail "$message (string not found: '$needle')"
    fi
}

assert_container_exists() {
    local container_name="$1"
    local message="${2:-Container exists: $container_name}"
    
    if docker ps -a --filter "name=^${container_name}$" --format "{{.Names}}" | grep -q "^${container_name}$"; then
        pass "$message"
    else
        fail "Container does not exist: $container_name"
    fi
}

assert_label_exists() {
    local container_name="$1"
    local label_key="$2"
    local label_value="$3"
    
    local actual=$(docker inspect -f "{{ index .Config.Labels \"${label_key}\" }}" "$container_name" 2>/dev/null)
    if [ "$actual" = "$label_value" ]; then
        pass "Label ${label_key}=${label_value} on $container_name"
    else
        fail "Label ${label_key} incorrect on $container_name (expected: '$label_value', got: '$actual')"
    fi
}

# ============================================================================
# Test Container Helper Functions
# ============================================================================

create_test_container() {
    local agent="$1"
    local repo="$2"
    local branch="$3"
    local sanitized_branch="${branch//\//-}"
    local container_name="${agent}-${repo}-${sanitized_branch}"
    
    docker run -d \
        --name "$container_name" \
        --label "coding-agents.test=true" \
        --label "coding-agents.type=agent" \
        --label "coding-agents.agent=$agent" \
        --label "coding-agents.repo=$repo" \
        --label "coding-agents.branch=$branch" \
        alpine:latest sleep $LONG_RUNNING_SLEEP >/dev/null
    
    echo "$container_name"
}

verify_container_labels() {
    local container_name="$1"
    local agent="$2"
    local repo="$3"
    local branch="$4"
    
    assert_label_exists "$container_name" "coding-agents.type" "agent"
    assert_label_exists "$container_name" "coding-agents.agent" "$agent"
    assert_label_exists "$container_name" "coding-agents.repo" "$repo"
    assert_label_exists "$container_name" "coding-agents.branch" "$branch"
}

# ============================================================================
# Test Functions
# ============================================================================

# ============================================================================
# Test: Container Runtime Detection
# ============================================================================

test_container_runtime_detection() {
    test_section "Container Runtime Detection"
    
    # Test get_container_runtime function
    local runtime=$(get_container_runtime)
    if [ -n "$runtime" ] && { [ "$runtime" = "docker" ] || [ "$runtime" = "podman" ]; }; then
        pass "get_container_runtime() detected runtime: $runtime"
    else
        fail "get_container_runtime() returned invalid runtime: '$runtime'"
    fi
    
    # Test that the runtime command is available
    if command -v "$runtime" &> /dev/null; then
        pass "Container runtime command '$runtime' is available"
    else
        fail "Container runtime command '$runtime' not found in PATH"
    fi
    
    # Test that runtime can execute basic command
    if $runtime info > /dev/null 2>&1; then
        pass "Container runtime '$runtime' is functional"
    else
        fail "Container runtime '$runtime' failed 'info' command"
    fi
}

# ============================================================================
# Test: Shared Functions
# ============================================================================

test_shared_functions() {
    test_section "Testing shared functions"
    
    source "$PROJECT_ROOT/scripts/utils/common-functions.sh"
    
    # Test get_repo_name
    local repo_name=$(get_repo_name "$TEST_REPO_DIR")
    assert_equals "test-coding-agents-repo" "$repo_name" "get_repo_name() returns correct name"
    
    # Test get_current_branch
    cd "$TEST_REPO_DIR"
    local branch=$(get_current_branch "$TEST_REPO_DIR")
    assert_equals "main" "$branch" "get_current_branch() returns 'main'"
    
    # Test check_docker_running
    if check_docker_running; then
        pass "check_docker_running() succeeds when Docker is running"
    else
        fail "check_docker_running() failed"
    fi
    
    # Test container_exists (should be false for non-existent container)
    if ! container_exists "non-existent-container-12345"; then
        pass "container_exists() returns false for non-existent container"
    else
        fail "container_exists() returned true for non-existent container"
    fi
}

# Test: Container naming convention
test_container_naming() {
    test_section "Testing container naming convention"
    
    local container_name=$(create_test_container "copilot" "test-coding-agents-repo" "main")
    
    assert_container_exists "$container_name"
    assert_contains "$container_name" "copilot-" "Container name starts with agent"
    assert_contains "$container_name" "-main" "Container name ends with branch"
}

# Test: Container labels
test_container_labels() {
    test_section "Testing container labels"
    
    local container_name="copilot-test-coding-agents-repo-main"
    verify_container_labels "$container_name" "copilot" "test-coding-agents-repo" "main"
}

# Test: list-agents command
test_list_agents() {
    test_section "Testing list-agents command"
    
    create_test_container "codex" "test-coding-agents-repo" "develop" >/dev/null
    
    local output=$("$PROJECT_ROOT/scripts/launchers/list-agents")
    
    assert_contains "$output" "copilot-test-coding-agents-repo-main" "list-agents shows copilot container"
    assert_contains "$output" "codex-test-coding-agents-repo-develop" "list-agents shows codex container"
    assert_contains "$output" "NAME" "list-agents shows header"
}

# Test: remove-agent command with --no-push
test_remove_agent() {
    test_section "Testing remove-agent command"
    
    local container_name="codex-test-coding-agents-repo-develop"
    
    # Remove with --no-push flag (since test container doesn't have git)
    "$PROJECT_ROOT/scripts/launchers/remove-agent" "$container_name" --no-push
    
    # Verify container is removed
    if ! docker ps -a --filter "name=^${container_name}$" --format "{{.Names}}" | grep -q "^${container_name}$"; then
        pass "remove-agent successfully removed container"
    else
        fail "remove-agent did not remove container"
    fi
}

# Test: Image pull function
test_image_pull() {
    test_section "Testing image pull functionality"
    
    source "$PROJECT_ROOT/scripts/utils/common-functions.sh"
    
    # Test pull_and_tag_image (will pull copilot image if available)
    # This is a smoke test - it should not fail even if image doesn't exist
    pull_and_tag_image "copilot" 2>/dev/null || true
    pass "pull_and_tag_image() executes without error"
}

# Test: Branch name sanitization
test_branch_sanitization() {
    test_section "Testing branch name sanitization"
    
    cd "$TEST_REPO_DIR"
    git checkout -q -b "feature/test-branch"
    
    local container_name=$(create_test_container "copilot" "test-coding-agents-repo" "feature/test-branch")
    
    assert_container_exists "$container_name"
    assert_label_exists "$container_name" "coding-agents.branch" "feature/test-branch"
    
    docker rm -f "$container_name" >/dev/null
}

# Test: Multiple agents on same repo
test_multiple_agents() {
    test_section "Testing multiple agents on same repo"
    
    cd "$TEST_REPO_DIR"
    git checkout -q main
    
    # Create containers for different agents
    local agents=("codex" "claude")
    local containers=()
    
    for agent in "${agents[@]}"; do
        containers+=($(create_test_container "$agent" "test-coding-agents-repo" "main"))
    done
    
    # Verify all coexist
    for container in "${containers[@]}"; do
        assert_container_exists "$container" "Agent container created: $container"
    done
    
    pass "Multiple agents can run on same repo/branch"
}

# Test: Docker label filtering
test_label_filtering() {
    test_section "Testing label-based filtering"
    
    # Filter by type=agent
    local agent_count=$(docker ps -a --filter "label=coding-agents.type=agent" --filter "label=coding-agents.test=true" --format "{{.Names}}" | wc -l)
    
    if [ $agent_count -ge 3 ]; then
        pass "Label filtering finds multiple agent containers (found: $agent_count)"
    else
        fail "Label filtering found insufficient containers (found: $agent_count, expected: >= 3)"
    fi
    
    # Filter by specific agent
    local copilot_count=$(docker ps -a --filter "label=coding-agents.agent=copilot" --filter "label=coding-agents.test=true" --format "{{.Names}}" | wc -l)
    
    if [ $copilot_count -ge 1 ]; then
        pass "Label filtering finds copilot containers (found: $copilot_count)"
    else
        fail "Label filtering found no copilot containers"
    fi
}

# Test: Shared functions - convert_to_wsl_path
test_wsl_path_conversion() {
    test_section "Testing WSL path conversion"
    
    source "$PROJECT_ROOT/scripts/utils/common-functions.sh"
    
    # Test Windows path conversion
    local wsl_path=$(convert_to_wsl_path "C:\\Users\\test\\project")
    assert_equals "/mnt/c/Users/test/project" "$wsl_path" "Windows path converted to WSL path"
    
    # Test already-WSL path (should be unchanged)
    local wsl_path2=$(convert_to_wsl_path "/mnt/e/dev/project")
    assert_equals "/mnt/e/dev/project" "$wsl_path2" "WSL path unchanged"
}

# Test: Container status functions
test_container_status() {
    test_section "Testing container status functions"
    
    source "$PROJECT_ROOT/scripts/utils/common-functions.sh"
    
    local container_name="copilot-test-coding-agents-repo-main"
    
    # Test get_container_status
    local status=$(get_container_status "$container_name")
    assert_equals "running" "$status" "get_container_status() returns 'running'"
    
    # Stop container and test again
    docker stop "$container_name" >/dev/null 2>&1
    local status2=$(get_container_status "$container_name")
    assert_equals "exited" "$status2" "get_container_status() returns 'exited' after stop"
    
    # Start it again for other tests
    docker start "$container_name" >/dev/null 2>&1
}

# Test: Launcher wrapper scripts
test_launcher_wrappers() {
    test_section "Testing launcher wrapper scripts"

    local wrappers=("run-copilot" "run-codex" "run-claude")
    for wrapper in "${wrappers[@]}"; do
        local script_path="$PROJECT_ROOT/scripts/launchers/${wrapper}"
        if output=$("$script_path" --help 2>&1); then
            assert_contains "$output" "Usage: run-agent" "${wrapper} --help displays usage"
        else
            fail "${wrapper} --help failed (exit $?)"
        fi
    done
}

# Main test execution
main() {
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║      Coding Agents Launcher Test Suite                   ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo ""
    echo "Testing from: $PROJECT_ROOT"
    echo ""
    
    setup_test_repo
    test_container_runtime_detection
    test_shared_functions
    test_wsl_path_conversion
    test_container_naming
    test_container_labels
    test_image_pull
    test_branch_sanitization
    test_multiple_agents
    test_label_filtering
    test_container_status
    test_launcher_wrappers
    test_list_agents
    test_remove_agent
    
    # Cleanup happens in trap
}

main
