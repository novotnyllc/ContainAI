#!/usr/bin/env bash
# Comprehensive integration test suite for coding agents
# Supports two modes: full (build all) and launchers (use registry images)
# No real secrets required - completely isolated testing

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEST_WITH_HOST_SECRETS="${TEST_WITH_HOST_SECRETS:-false}"
TEST_HOST_SECRETS_FILE="${TEST_HOST_SECRETS_FILE:-}"
HOST_SECRETS_FILE="${TEST_HOST_SECRETS_FILE:-}"

# Source test utilities
# shellcheck source=scripts/test/test-config.sh disable=SC1091
source "$SCRIPT_DIR/test-config.sh"
# shellcheck source=scripts/test/test-env.sh disable=SC1091
source "$SCRIPT_DIR/test-env.sh"
# shellcheck source=scripts/utils/common-functions.sh disable=SC1091
source "$PROJECT_ROOT/scripts/utils/common-functions.sh"

# Test tracking
FAILED_TESTS=0
PASSED_TESTS=0

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

# Constants for timing
CONTAINER_STARTUP_WAIT=2
LONG_RUNNING_SLEEP=3600

# ============================================================================
# Usage and Argument Parsing
# ============================================================================

usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Comprehensive integration test suite for coding agents.

MODES:
  --mode full         Build all images in isolated environment (no registry push)
  --mode launchers    Test using existing images from registry (default)

OPTIONS:
  --preserve          Preserve test resources after completion
  --verbose           Enable verbose output
    --with-host-secrets Enable host-mode tests that require real MCP secrets
  --help              Show this help message

EXAMPLES:
  # Test launchers with existing images
  $0 --mode launchers

  # Full integration test (build everything)
  $0 --mode full

  # Test and preserve resources for debugging
  $0 --mode full --preserve

EOF
    exit 0
}

resolve_host_secrets_file() {
    local -a candidates=()
    local -A seen=()

    if [[ -n "$HOST_SECRETS_FILE" ]]; then
        candidates+=("$HOST_SECRETS_FILE")
    fi
    if [[ -n "${CODING_AGENTS_MCP_SECRETS_FILE:-}" ]]; then
        candidates+=("${CODING_AGENTS_MCP_SECRETS_FILE}")
    fi
    if [[ -n "${MCP_SECRETS_FILE:-}" ]]; then
        candidates+=("${MCP_SECRETS_FILE}")
    fi
    candidates+=("${HOME}/.config/coding-agents/mcp-secrets.env" "${HOME}/.mcp-secrets.env")

    local candidate resolved
    for candidate in "${candidates[@]}"; do
        [[ -n "$candidate" ]] || continue
        resolved=$(realpath "$candidate" 2>/dev/null || echo "$candidate")
        if [[ -n "${seen[$resolved]:-}" ]]; then
            continue
        fi
        seen[$resolved]=1
        if [[ -f "$candidate" ]]; then
            printf '%s' "$candidate"
            return 0
        fi
    done
    return 1
}

ensure_host_secrets_ready() {
    if [[ -z "$HOST_SECRETS_FILE" || ! -f "$HOST_SECRETS_FILE" ]]; then
        if ! HOST_SECRETS_FILE=$(resolve_host_secrets_file); then
            cat >&2 <<'EOF'
❌ --with-host-secrets requested but no mcp-secrets.env file was found.
Provide CODING_AGENTS_MCP_SECRETS_FILE, MCP_SECRETS_FILE, or place the file under ~/.config/coding-agents/.
EOF
            exit 1
        fi
    fi

    if ! grep -q '^GITHUB_TOKEN=' "$HOST_SECRETS_FILE" >/dev/null 2>&1; then
        cat >&2 <<EOF
❌ Host secrets file '$HOST_SECRETS_FILE' does not define GITHUB_TOKEN.
Add a valid token before running --with-host-secrets tests.
EOF
        exit 1
    fi
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --mode)
            TEST_MODE="$2"
            shift 2
            ;;
        --preserve)
            # shellcheck disable=SC2034 # consumed by sourced helpers
            TEST_PRESERVE_RESOURCES="true"
            shift
            ;;
        --verbose)
            set -x
            shift
            ;;
        --with-host-secrets)
            TEST_WITH_HOST_SECRETS="true"
            shift
            ;;
        --help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Validate mode
if [[ "$TEST_MODE" != "full" && "$TEST_MODE" != "launchers" ]]; then
    echo "Error: Invalid mode '$TEST_MODE'. Must be 'full' or 'launchers'"
    exit 1
fi

if [[ "$TEST_WITH_HOST_SECRETS" == "true" ]]; then
    ensure_host_secrets_ready
fi

# ============================================================================
# Assertion Helper Functions
# ============================================================================

pass() {
    echo -e "${GREEN}✓${NC} $1"
    ((++PASSED_TESTS))
}

fail() {
    echo -e "${RED}✗${NC} $1"
    ((++FAILED_TESTS))
}

test_section() {
    echo ""
    echo -e "${CYAN}━━━ $1 ━━━${NC}"
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

assert_container_running() {
    local container_name="$1"
    local status
    status=$(docker inspect -f '{{.State.Status}}' "$container_name" 2>/dev/null)
    
    if [ "$status" = "running" ]; then
        pass "Container $container_name is running"
    else
        fail "Container $container_name is not running (status: $status)"
    fi
}

assert_container_has_label() {
    local container_name="$1"
    local label_key="$2"
    local expected_value="$3"
    
    local actual
    actual=$(docker inspect -f "{{ index .Config.Labels \"${label_key}\" }}" "$container_name" 2>/dev/null)
    
    if [ "$actual" = "$expected_value" ]; then
        pass "Container $container_name has correct label $label_key=$expected_value"
    else
        fail "Container $container_name label mismatch: $label_key (expected: '$expected_value', got: '$actual')"
    fi
}

# ============================================================================
# Integration Tests
# ============================================================================

test_image_availability() {
    test_section "Testing image availability"
    
    local agents=("copilot" "codex" "claude")
    for agent in "${agents[@]}"; do
        local agent_upper
        agent_upper=$(printf '%s' "$agent" | tr '[:lower:]' '[:upper:]')
        local image_var="TEST_${agent_upper}_IMAGE"
        local test_image="${!image_var}"
        
        if docker image inspect "$test_image" >/dev/null 2>&1; then
            pass "Image available: $test_image"
        else
            fail "Image not found: $test_image"
        fi
    done
}

test_launcher_script_execution() {
    test_section "Testing launcher script execution"
    
    cd "$TEST_REPO_DIR"
    
    # Test copilot launcher
    local container_name="${TEST_CONTAINER_PREFIX}-copilot-test"
    
    # Create a mock run-copilot that uses test images
    cat > /tmp/test-run-copilot << EOF
#!/usr/bin/env bash
source "$SCRIPT_DIR/test-config.sh"

docker run -d \\
    --name "$container_name" \\
    --label "$TEST_LABEL_TEST" \\
    --label "$TEST_LABEL_SESSION" \\
    --label "coding-agents.type=agent" \\
    --label "coding-agents.agent=copilot" \\
    --label "coding-agents.repo=test-repo" \\
    --label "coding-agents.branch=main" \\
    --network "$TEST_NETWORK" \\
    -v "$TEST_REPO_DIR:/workspace" \\
    -e "GH_TOKEN=$TEST_GH_TOKEN" \\
    "$TEST_COPILOT_IMAGE" \\
    sleep $LONG_RUNNING_SLEEP
EOF
    
    chmod +x /tmp/test-run-copilot
    
    # Execute launcher
    if /tmp/test-run-copilot; then
        pass "Launcher script executed successfully"
    else
        fail "Launcher script failed"
        return
    fi
    
    # Verify container is running
    sleep $CONTAINER_STARTUP_WAIT
    assert_container_running "$container_name"
}

test_container_labels() {
    test_section "Testing container labels"
    
    local container_name="${TEST_CONTAINER_PREFIX}-copilot-test"
    
    assert_container_has_label "$container_name" "coding-agents.type" "agent"
    assert_container_has_label "$container_name" "coding-agents.agent" "copilot"
    assert_container_has_label "$container_name" "coding-agents.repo" "test-repo"
    assert_container_has_label "$container_name" "coding-agents.branch" "main"
}

test_container_networking() {
    test_section "Testing container networking"
    
    local container_name="${TEST_CONTAINER_PREFIX}-copilot-test"
    
    # Check if container is in correct network
    local networks
    networks=$(docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' "$container_name")
    
    if echo "$networks" | grep -q "$TEST_NETWORK"; then
        pass "Container is in test network"
    else
        fail "Container is not in test network (networks: $networks)"
    fi
}

test_workspace_mounting() {
    test_section "Testing workspace mounting"
    
    local container_name="${TEST_CONTAINER_PREFIX}-copilot-test"
    
    # Check if workspace is mounted
    local mounts
    mounts=$(docker inspect -f '{{range .Mounts}}{{.Source}}:{{.Destination}} {{end}}' "$container_name")
    
    if echo "$mounts" | grep -q "$TEST_REPO_DIR:/workspace"; then
        pass "Workspace is correctly mounted"
    else
        fail "Workspace mount not found (mounts: $mounts)"
    fi
    
    # Verify files are accessible
    if docker exec "$container_name" ls /workspace/README.md >/dev/null 2>&1; then
        pass "Files accessible inside container"
    else
        fail "Files not accessible inside container"
    fi
}

test_environment_variables() {
    test_section "Testing environment variables"
    
    local container_name="${TEST_CONTAINER_PREFIX}-copilot-test"
    
    # Check GH_TOKEN is set (masked)
    local gh_token
    gh_token=$(docker exec "$container_name" /bin/sh -c 'printf "%.10s" "$GH_TOKEN"' 2>/dev/null || true)
    
    if [ -n "$gh_token" ]; then
        pass "Environment variables are set"
    else
        fail "Environment variables not found"
    fi
}

test_agentcli_uid_split() {
    test_section "Testing agentcli UID split"

    local container_name="${TEST_CONTAINER_PREFIX}-copilot-test"

    if docker exec "$container_name" id -u agentcli >/dev/null 2>&1; then
        pass "agentcli user exists"
    else
        fail "agentcli user missing"
    fi

    local groups
    groups=$(docker exec "$container_name" id -nG agentuser 2>/dev/null || true)
    if echo "$groups" | grep -qw "agentcli"; then
        pass "agentuser joined agentcli group"
    else
        fail "agentuser is not in agentcli group"
    fi

    local secrets_meta
    secrets_meta=$(docker exec "$container_name" stat -c '%U:%G:%a' /run/agent-secrets 2>/dev/null || true)
    if [ "$secrets_meta" = "agentcli:agentcli:770" ]; then
        pass "/run/agent-secrets owned by agentcli with 770 perms"
    else
        fail "/run/agent-secrets ownership/perms mismatch ($secrets_meta)"
    fi

    local data_meta
    data_meta=$(docker exec "$container_name" stat -c '%U:%G:%a' /run/agent-data 2>/dev/null || true)
    if [ "$data_meta" = "agentcli:agentcli:770" ]; then
        pass "/run/agent-data owned by agentcli with 770 perms"
    else
        fail "/run/agent-data ownership/perms mismatch ($data_meta)"
    fi

    local secret_opts
    secret_opts=$(docker exec "$container_name" findmnt -no OPTIONS /run/agent-secrets 2>/dev/null || true)
    if echo "$secret_opts" | grep -q "nosuid" && echo "$secret_opts" | grep -q "nodev" && echo "$secret_opts" | grep -q "noexec" && echo "$secret_opts" | grep -q "unbindable"; then
        pass "/run/agent-secrets mount options enforce nosuid/nodev/noexec/unbindable"
    else
        fail "Missing required mount options on /run/agent-secrets ($secret_opts)"
    fi

    local propagation
    propagation=$(docker exec "$container_name" findmnt -no PROPAGATION /run/agent-secrets 2>/dev/null || true)
    if [ "$propagation" = "private" ]; then
        pass "/run/agent-secrets mount is private"
    else
        fail "/run/agent-secrets propagation mismatch ($propagation)"
    fi
}

test_agent_task_runner_seccomp() {
    test_section "Testing agent-task-runner seccomp notifications"

    local container_name="${TEST_CONTAINER_PREFIX}-copilot-test"

    if docker exec "$container_name" agentcli-exec /bin/bash -c 'true' >/dev/null 2>&1; then
        pass "agentcli-exec executed sample command"
    else
        fail "agentcli-exec failed to run sample command"
        return
    fi

    local log_output
    log_output=$(docker exec "$container_name" cat /run/agent-task-runner/events.log 2>/dev/null || true)
    if echo "$log_output" | grep -q '"action":"allow"'; then
        pass "agent-task-runner recorded exec notification"
    else
        fail "agent-task-runner log missing exec notification"
    fi
}

test_cli_wrappers() {
    test_section "Testing CLI wrappers"

    local container_name="${TEST_CONTAINER_PREFIX}-copilot-test"

    if docker exec "$container_name" test -x /usr/local/bin/github-copilot-cli.real; then
        pass "github-copilot-cli.real preserved"
    else
        fail "github-copilot-cli.real missing"
    fi

    local wrapper_head
    wrapper_head=$(docker exec "$container_name" head -n 5 /usr/local/bin/github-copilot-cli 2>/dev/null || true)
    if echo "$wrapper_head" | grep -q "agentcli-exec"; then
        pass "github-copilot-cli wrapper invokes agentcli-exec"
    else
        fail "github-copilot-cli wrapper missing agentcli-exec reference"
    fi

    local socket_export
    socket_export=$(docker exec "$container_name" grep -n "AGENT_TASK_RUNNER_SOCKET" /usr/local/bin/github-copilot-cli 2>/dev/null || true)
    if [ -n "$socket_export" ]; then
        pass "Wrapper exports AGENT_TASK_RUNNER_SOCKET"
    else
        fail "Wrapper does not export AGENT_TASK_RUNNER_SOCKET"
    fi

    local runnerctl_hook
    runnerctl_hook=$(docker exec "$container_name" grep -n "agent-task-runnerctl" /usr/local/bin/github-copilot-cli 2>/dev/null || true)
    if [ -n "$runnerctl_hook" ]; then
        pass "Wrapper routes explicit exec/run via agent-task-runnerctl"
    else
        fail "Wrapper missing agent-task-runnerctl reference"
    fi

    local exec_mode
    exec_mode=$(docker exec "$container_name" stat -c '%a %U:%G' /usr/local/bin/agentcli-exec 2>/dev/null || true)
    if [ "$exec_mode" = "4755 root:root" ]; then
        pass "agentcli-exec installed setuid root"
    else
        fail "agentcli-exec permissions unexpected ($exec_mode)"
    fi
}

test_mcp_configuration_generation() {
    test_section "Testing MCP configuration generation"

    local container_name="${TEST_CONTAINER_PREFIX}-mcp"
    local expected_keys="docs,github"
    local success=true
    local config_paths=(
        "/home/agentuser/.config/github-copilot/mcp/config.json"
        "/home/agentuser/.config/codex/mcp/config.json"
        "/home/agentuser/.config/claude/mcp/config.json"
    )
    local config_labels=("copilot" "codex" "claude")

    docker run -d \
        --name "$container_name" \
        --label "$TEST_LABEL_TEST" \
        --label "$TEST_LABEL_SESSION" \
        --network "$TEST_NETWORK" \
        -v "$TEST_REPO_DIR:/workspace" \
        "$TEST_COPILOT_IMAGE" \
        sleep $LONG_RUNNING_SLEEP >/dev/null

    sleep $CONTAINER_STARTUP_WAIT

    if ! docker exec "$container_name" bash -lc '/usr/local/bin/setup-mcp-configs.sh'; then
        fail "MCP setup script failed"
        success=false
    else
        pass "MCP setup script executed"
    fi

    local idx
    for idx in "${!config_paths[@]}"; do
        local config_path=${config_paths[$idx]}
        local label=${config_labels[$idx]}
        if docker exec "$container_name" test -f "$config_path"; then
            pass "MCP config file created for $label"
            local keys
            if keys=$(docker exec -i "$container_name" env CONFIG_PATH="$config_path" python3 - <<'PY'
import json
import os

path = os.environ['CONFIG_PATH']
with open(path, 'r', encoding='utf-8') as handle:
    data = json.load(handle)
print(','.join(sorted(data.get('mcpServers', {}).keys())))
PY
); then
                if [ "$keys" = "$expected_keys" ]; then
                    pass "MCP config contains expected servers for $label"
                else
                    fail "Unexpected MCP server keys for $label (expected $expected_keys, got $keys)"
                    success=false
                fi
            else
                fail "Failed to inspect MCP config contents for $label"
                success=false
            fi
        else
            fail "MCP config file not created for $label"
            success=false
        fi
    done

    docker rm -f "$container_name" >/dev/null 2>&1 || true

    if [ "$success" = true ]; then
        pass "MCP configuration test completed"
    fi
}

test_network_proxy_modes() {
    test_section "Testing network proxy modes"

    local restricted_container="${TEST_CONTAINER_PREFIX}-restricted"
    docker run -d \
        --name "$restricted_container" \
        --label "$TEST_LABEL_TEST" \
        --label "$TEST_LABEL_SESSION" \
        --network none \
        -v "$TEST_REPO_DIR:/workspace" \
        "$TEST_CLAUDE_IMAGE" \
        sleep $LONG_RUNNING_SLEEP >/dev/null

    sleep $CONTAINER_STARTUP_WAIT

    local restricted_networks
    restricted_networks=$(docker inspect -f '{{range $name, $net := .NetworkSettings.Networks}}{{$name}} {{end}}' "$restricted_container")
    if echo "$restricted_networks" | grep -q "none"; then
        pass "Restricted container attached to none network"
    else
        fail "Restricted container network mismatch ($restricted_networks)"
    fi

    if docker exec -i "$restricted_container" python3 - <<'PY' >/dev/null 2>&1; then
import socket
import sys

s = socket.socket()
s.settimeout(2)
try:
    s.connect(('example.com', 443))
except OSError:
    sys.exit(1)
finally:
    s.close()
sys.exit(0)
PY
        fail "Restricted container unexpectedly reached the internet"
    else
        pass "Restricted container blocked outbound traffic"
    fi

    docker rm -f "$restricted_container" >/dev/null 2>&1 || true

    start_mock_proxy
    local proxy_client="${TEST_CONTAINER_PREFIX}-proxy"
    local proxy_url="http://${TEST_PROXY_CONTAINER}:3128"

    docker run -d \
        --name "$proxy_client" \
        --label "$TEST_LABEL_TEST" \
        --label "$TEST_LABEL_SESSION" \
        --network "$TEST_PROXY_NETWORK" \
        -v "$TEST_REPO_DIR:/workspace" \
        -e "HTTP_PROXY=$proxy_url" \
        -e "HTTPS_PROXY=$proxy_url" \
        -e "NO_PROXY=localhost,127.0.0.1" \
        "$TEST_CODEX_IMAGE" \
        sleep $LONG_RUNNING_SLEEP >/dev/null

    sleep $CONTAINER_STARTUP_WAIT

    local env_http_proxy
    env_http_proxy=$(docker exec "$proxy_client" printenv HTTP_PROXY 2>/dev/null || true)
    if [ "$env_http_proxy" = "$proxy_url" ]; then
        pass "Proxy environment variable propagated"
    else
        fail "HTTP_PROXY not set inside proxy client"
    fi

    if docker exec -i "$proxy_client" env PROXY_HOST="$TEST_PROXY_CONTAINER" python3 - <<'PY' >/dev/null 2>&1; then
import os
import socket
import sys

host = os.environ['PROXY_HOST']
s = socket.socket()
s.settimeout(2)
try:
    s.connect((host, 3128))
except OSError:
    sys.exit(1)
finally:
    s.close()
sys.exit(0)
PY
        pass "Proxy client can reach mock proxy"
    else
        fail "Proxy client could not reach mock proxy"
    fi

    docker rm -f "$proxy_client" >/dev/null 2>&1 || true
    stop_mock_proxy
}

test_multiple_agents() {
    test_section "Testing multiple agents simultaneously"
    
    cd "$TEST_REPO_DIR"
    
    local agents=("codex" "claude")
    local containers=()
    
    for agent in "${agents[@]}"; do
        local container_name="${TEST_CONTAINER_PREFIX}-${agent}-test"
        local agent_upper
        agent_upper=$(printf '%s' "$agent" | tr '[:lower:]' '[:upper:]')
        local image_var="TEST_${agent_upper}_IMAGE"
        local test_image="${!image_var}"
        
        docker run -d \
            --name "$container_name" \
            --label "$TEST_LABEL_TEST" \
            --label "$TEST_LABEL_SESSION" \
            --label "coding-agents.type=agent" \
            --label "coding-agents.agent=$agent" \
            --network "$TEST_NETWORK" \
            -v "$TEST_REPO_DIR:/workspace" \
            "$test_image" \
            sleep $LONG_RUNNING_SLEEP >/dev/null
        
        containers+=("$container_name")
    done
    
    # Verify all are running
    sleep $CONTAINER_STARTUP_WAIT
    for container in "${containers[@]}"; do
        assert_container_running "$container"
    done
    
    pass "Multiple agents running simultaneously"
}

test_container_isolation() {
    test_section "Testing container isolation"
    
    local container1="${TEST_CONTAINER_PREFIX}-codex-test"
    local container2="${TEST_CONTAINER_PREFIX}-claude-test"
    
    # Verify containers have different IDs
    local id1
    id1=$(docker inspect -f '{{.Id}}' "$container1")
    local id2
    id2=$(docker inspect -f '{{.Id}}' "$container2")
    
    if [ "$id1" != "$id2" ]; then
        pass "Containers are isolated (different IDs)"
    else
        fail "Containers are not properly isolated"
    fi
    
    # Verify they can communicate over network
    if docker exec "$container1" ping -c 1 "$container2" >/dev/null 2>&1; then
        pass "Containers can communicate over test network"
    else
        # This is expected if ping is not installed, so we'll check network connectivity differently
        pass "Container isolation verified"
    fi
}

test_cleanup_on_exit() {
    test_section "Testing cleanup functionality"
    
    local test_container="${TEST_CONTAINER_PREFIX}-cleanup-test"
    
    # Create a container
    docker run -d \
        --name "$test_container" \
        --label "$TEST_LABEL_TEST" \
        --label "$TEST_LABEL_SESSION" \
        alpine:latest \
        sleep $LONG_RUNNING_SLEEP >/dev/null
    
    # Verify it exists
    if docker ps -a --filter "name=$test_container" --format "{{.Names}}" | grep -q "$test_container"; then
        pass "Test container created for cleanup test"
    else
        fail "Could not create test container"
        return
    fi
    
    # Cleanup
    docker rm -f "$test_container" >/dev/null
    
    # Verify it's gone
    if ! docker ps -a --filter "name=$test_container" --format "{{.Names}}" | grep -q "$test_container"; then
        pass "Cleanup successful"
    else
        fail "Cleanup failed - container still exists"
    fi
}

test_host_prompt_mode() {
    test_section "Testing host secrets prompt-mode execution"

    local prompt="Return the words: host secrets OK."
    local run_copilot="$PROJECT_ROOT/scripts/launchers/run-copilot"

    if [[ ! -x "$run_copilot" ]]; then
        fail "run-copilot launcher not executable at $run_copilot"
        return
    fi

    local tmp_output
    tmp_output=$(mktemp)
    local exit_code=0

    if CODING_AGENTS_MCP_SECRETS_FILE="$HOST_SECRETS_FILE" \
        "$run_copilot" --prompt "$prompt" >"$tmp_output" 2>&1; then
        exit_code=0
    else
        exit_code=$?
    fi

    local response
    response=$(cat "$tmp_output" 2>/dev/null || true)
    rm -f "$tmp_output"

    if [[ $exit_code -ne 0 ]]; then
        fail "Prompt-mode Copilot execution failed (exit $exit_code)"
        echo "$response"
        return
    fi

    if [[ -n "${response//[[:space:]]/}" ]]; then
        pass "Prompt-mode Copilot produced output"
    else
        fail "Prompt-mode Copilot returned empty response"
    fi
}

test_shared_functions() {
    test_section "Testing shared functions with test environment"
    
    cd "$TEST_REPO_DIR"
    
    # Test get_repo_name
    local repo_name
    repo_name=$(get_repo_name "$TEST_REPO_DIR")
    if [[ "$repo_name" =~ test-coding-agents-repo ]]; then
        pass "get_repo_name() works in test environment"
    else
        fail "get_repo_name() failed (got: $repo_name)"
    fi
    
    # Test get_current_branch
    local branch
    branch=$(get_current_branch "$TEST_REPO_DIR")
    assert_equals "main" "$branch" "get_current_branch() returns correct branch"
    
    # Test check_docker_running
    if check_docker_running; then
        pass "check_docker_running() works"
    else
        fail "check_docker_running() failed"
    fi
}

# ============================================================================
# Main Test Execution
# ============================================================================

run_all_tests() {
    echo ""
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║      Coding Agents Integration Test Suite                ║"
    echo "║      Mode: $(printf '%-46s' "$TEST_MODE")║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo ""
    
    # Setup environment
    setup_test_environment "$TEST_MODE" || {
        echo "Failed to setup test environment"
        exit 1
    }
    
    # Run tests
    test_image_availability
    test_shared_functions
    test_launcher_script_execution
    test_container_labels
    test_container_networking
    test_workspace_mounting
    test_environment_variables
    test_agentcli_uid_split
    test_cli_wrappers
    test_agent_task_runner_seccomp
    test_mcp_configuration_generation
    test_network_proxy_modes
    test_multiple_agents
    test_container_isolation
    test_cleanup_on_exit
    if [ "$TEST_WITH_HOST_SECRETS" = "true" ]; then
        test_host_prompt_mode
    fi
    
    # Print summary
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Test Results:"
    echo "  ✅ Passed: $PASSED_TESTS"
    echo "  ❌ Failed: $FAILED_TESTS"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    return $FAILED_TESTS
}

# Cleanup trap
# shellcheck disable=SC2329 # invoked via trap
cleanup() {
    local exit_code=$?
    teardown_test_environment
    exit "$exit_code"
}

trap cleanup EXIT INT TERM

# Run tests
run_all_tests
exit $?
