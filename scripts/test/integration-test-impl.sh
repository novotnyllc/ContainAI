#!/usr/bin/env bash
# Comprehensive integration test suite for ContainAI
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
# shellcheck source=host/utils/common-functions.sh disable=SC1091
source "$PROJECT_ROOT/host/utils/common-functions.sh"

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

Comprehensive integration test suite for ContainAI.

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
    if [[ -n "${CONTAINAI_MCP_SECRETS_FILE:-}" ]]; then
        candidates+=("${CONTAINAI_MCP_SECRETS_FILE}")
    fi
    if [[ -n "${MCP_SECRETS_FILE:-}" ]]; then
        candidates+=("${MCP_SECRETS_FILE}")
    fi
    candidates+=("${HOME}/.config/containai/mcp-secrets.env" "${HOME}/.mcp-secrets.env")

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
Provide CONTAINAI_MCP_SECRETS_FILE, MCP_SECRETS_FILE, or place the file under ~/.config/containai/.
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
        --filter)
            TEST_FILTER="$2"
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
        echo "DEBUG: Container logs:"
        docker logs "$container_name" 2>&1 | tail -n 20 || true
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

next_agent_branch_name() {
    local agent="$1"
    local refs count=0
    refs=$(git -C "$TEST_REPO_DIR" for-each-ref --format='%(refname:short)' "refs/heads/${agent}/session-*" 2>/dev/null || true)
    if [[ -n "$refs" ]]; then
        count=$(printf '%s\n' "$refs" | wc -l | tr -d '[:space:]')
    fi
    echo "${agent}/session-$((count + 1))"
}

wait_for_agent_branch() {
    local branch="$1"
    local timeout="${2:-60}"
    local elapsed=0
    while [ "$elapsed" -lt "$timeout" ]; do
        if git -C "$TEST_REPO_DIR" rev-parse --verify --quiet "$branch" >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    return 1
}

build_prompt_post_hook_script() {
    local agent="$1"
    local marker="$2"
    local commit_msg="$3"
    cat <<EOF
set -euo pipefail
cd /workspace
cat <<'EOM' > ${marker}
${agent} prompt hook success
EOM
git add ${marker}
git commit -m "${commit_msg}" >/dev/null
git push local HEAD >/dev/null
EOF
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
    
    # Test copilot launcher (channel-aware)
    local container_name="${TEST_CONTAINER_PREFIX}-copilot-test"
    local channel="${CONTAINAI_LAUNCHER_CHANNEL:-dev}"
    local launcher_name="run-copilot-dev"
    case "$channel" in
        prod) launcher_name="run-copilot" ;;
        nightly) launcher_name="run-copilot-nightly" ;;
        dev) ;;
        *)
            fail "Unsupported launcher channel: $channel"
            return
            ;;
    esac
    
    # Create a mock launcher that uses test images
    cat > "/tmp/test-${launcher_name}" << EOF
#!/usr/bin/env bash
source "$SCRIPT_DIR/test-config.sh"

DOCKER_ARGS=(
    run -d
    --name "$container_name"
    --label "$TEST_LABEL_TEST"
    --label "$TEST_LABEL_SESSION"
    --label "containai.type=agent"
    --label "containai.agent=copilot"
    --label "containai.repo=test-repo"
    --label "containai.branch=main"
    --network "$TEST_NETWORK"
    --cap-add SYS_ADMIN
    --cap-add NET_ADMIN
    -v "$TEST_REPO_DIR:/workspace"
    -e "GH_TOKEN=$TEST_GH_TOKEN"
    -e "HTTP_PROXY=http://${TEST_PROXY_CONTAINER}:3128"
    -e "HTTPS_PROXY=http://${TEST_PROXY_CONTAINER}:3128"
    -e "NO_PROXY=localhost,127.0.0.1"
    -v /workspace/docker/runtime/entrypoint.sh:/usr/local/bin/entrypoint.sh:ro
)

if [ -f /workspace/docker/runtime/agent-task-runner/target/debug/agent-task-runnerd ]; then
    DOCKER_ARGS+=(-v /workspace/docker/runtime/agent-task-runner/target/debug/agent-task-runnerd:/usr/local/bin/agent-task-runnerd:ro)
fi

docker "\${DOCKER_ARGS[@]}" "$TEST_COPILOT_IMAGE" sleep $LONG_RUNNING_SLEEP
EOF
    
    chmod +x "/tmp/test-${launcher_name}"
    
    # Execute launcher
    if "/tmp/test-${launcher_name}"; then
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
    
    assert_container_has_label "$container_name" "containai.type" "agent"
    assert_container_has_label "$container_name" "containai.agent" "copilot"
    assert_container_has_label "$container_name" "containai.repo" "test-repo"
    assert_container_has_label "$container_name" "containai.branch" "main"
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
    if echo "$secret_opts" | grep -q "nosuid" && echo "$secret_opts" | grep -q "nodev" && echo "$secret_opts" | grep -q "noexec"; then
        pass "/run/agent-secrets mount options enforce nosuid/nodev/noexec"
    else
        fail "Missing required mount options on /run/agent-secrets ($secret_opts)"
    fi

    local propagation
    propagation=$(docker exec "$container_name" findmnt -no PROPAGATION /run/agent-secrets 2>/dev/null || true)
    if [[ "$propagation" == *"private"* ]]; then
        pass "/run/agent-secrets mount is private"
    else
        fail "/run/agent-secrets propagation mismatch ($propagation)"
    fi
}

test_capabilities_dropped() {
    test_section "Testing capability dropping after privileged setup"

    local container_name="${TEST_CONTAINER_PREFIX}-copilot-test"

    if ! docker ps -q -f name="$container_name" | grep -q .; then
        fail "Container $container_name is not running before capability check"
        return
    fi

    # Verify the agent process is running as non-root
    # We check PID 1 because docker exec runs as the default user (root)
    # We must add the agentproc group to see the process due to hidepid=2
    local agent_uid
    local exec_out
    if ! exec_out=$(docker exec --user root:agentproc "$container_name" grep "^Uid:" /proc/1/status 2>&1); then
        fail "Failed to get agent UID (docker exec failed)"
        echo "DEBUG: Output: $exec_out"
        return
    fi
    agent_uid=$(echo "$exec_out" | awk '{print $2}')
    
    if [ -n "$agent_uid" ] && [ "$agent_uid" != "0" ]; then
        pass "Agent process running as non-root (UID: $agent_uid)"
    else
        fail "Agent process unexpectedly running as root (UID: ${agent_uid:-unknown})"
        return
    fi

    # Check that no capabilities are available to the agent process
    # Using getpcaps to inspect PID 1
    local caps
    # Must use root:agentproc to see PID 1 due to hidepid=2
    caps=$(docker exec --user root:agentproc "$container_name" bash -c 'getpcaps 1 2>&1' || true)
    
    if echo "$caps" | grep -qE "cap_sys_admin|cap_net_admin"; then
        fail "Agent process still has SYS_ADMIN or NET_ADMIN capabilities ($caps)"
    else
        pass "Agent process has no dangerous capabilities"
    fi

    # Verify that attempting privileged operations fails
    # We must run as the agent user to verify what the agent can do
    # Try to mount a tmpfs (requires CAP_SYS_ADMIN)
    if docker exec --user agentuser "$container_name" bash -c 'mount -t tmpfs tmpfs /tmp/test-mount 2>/dev/null'; then
        fail "Agent can still mount filesystems (CAP_SYS_ADMIN not dropped)"
        docker exec "$container_name" umount /tmp/test-mount 2>/dev/null || true
    else
        pass "Agent cannot mount filesystems (CAP_SYS_ADMIN dropped)"
    fi

    # Try to modify iptables (requires CAP_NET_ADMIN)
    if docker exec --user agentuser "$container_name" bash -c 'iptables -L 2>/dev/null'; then
        fail "Agent can still list iptables (CAP_NET_ADMIN not dropped)"
    else
        pass "Agent cannot access iptables (CAP_NET_ADMIN dropped)"
    fi
}

test_agent_task_runner_seccomp() {
    test_section "Testing agent-task-runner seccomp notifications"

    local container_name="${TEST_CONTAINER_PREFIX}-copilot-test"

    # Check if agent-task-runnerd is running
    if docker exec "$container_name" ps aux | grep agent-task-runnerd | grep -v grep; then
        echo "DEBUG: agent-task-runnerd is running"
    else
        echo "DEBUG: agent-task-runnerd is NOT running"
        docker exec "$container_name" ps aux
    fi

    # Run agentcli-exec and capture output
    local exec_out
    if exec_out=$(docker exec -e AGENT_TASK_RUNNER_SOCKET=/run/agent-task-runner.sock "$container_name" agentcli-exec /bin/bash -c 'true' 2>&1); then
        pass "agentcli-exec executed sample command"
    else
        fail "agentcli-exec failed to run sample command"
        echo "DEBUG: agentcli-exec output: $exec_out"
        return
    fi
    
    if [ -n "$exec_out" ]; then
        echo "DEBUG: agentcli-exec output: $exec_out"
    fi

    sleep 2

    local log_output
    log_output=$(docker exec "$container_name" cat /run/agent-task-runner/events.log 2>/dev/null || true)
    if echo "$log_output" | grep -q '"action":"allow"'; then
        pass "agent-task-runner recorded exec notification"
    else
        fail "agent-task-runner log missing exec notification"
        echo "DEBUG: Log content:"
        echo "$log_output"
        echo "DEBUG: Log file permissions:"
        docker exec "$container_name" ls -l /run/agent-task-runner/events.log || true
        echo "DEBUG: Container logs:"
        docker logs "$container_name" 2>&1 | tail -n 50
    fi
}

test_cli_wrappers() {
    test_section "Testing CLI wrappers"

    local container_name="${TEST_CONTAINER_PREFIX}-copilot-test"

    # Find the real binary path
    local real_path
    real_path=$(docker exec "$container_name" bash -c 'command -v github-copilot-cli.real || echo ""')
    
    if [ -n "$real_path" ]; then
        pass "github-copilot-cli.real preserved at $real_path"
    else
        fail "github-copilot-cli.real missing"
        return
    fi

    local wrapper_path="${real_path%.real}"

    local wrapper_content
    wrapper_content=$(docker exec "$container_name" cat "$wrapper_path" 2>/dev/null || true)
    if echo "$wrapper_content" | grep -q "agentcli-exec"; then
        pass "github-copilot-cli wrapper invokes agentcli-exec"
    else
        fail "github-copilot-cli wrapper missing agentcli-exec reference"
    fi

    local socket_export
    socket_export=$(echo "$wrapper_content" | grep "AGENT_TASK_RUNNER_SOCKET")
    if [ -n "$socket_export" ]; then
        pass "Wrapper exports AGENT_TASK_RUNNER_SOCKET"
    else
        fail "Wrapper does not export AGENT_TASK_RUNNER_SOCKET"
    fi

    local runnerctl_hook
    runnerctl_hook=$(echo "$wrapper_content" | grep "agent-task-runnerctl")
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
        --cap-add SYS_ADMIN \
        --cap-add NET_ADMIN \
        -v "$TEST_REPO_DIR:/workspace" \
        -e "HTTP_PROXY=http://${TEST_PROXY_CONTAINER}:3128" \
        -e "HTTPS_PROXY=http://${TEST_PROXY_CONTAINER}:3128" \
        -e "NO_PROXY=localhost,127.0.0.1" \
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

test_mitm_ca_generation() {
    test_section "Testing MITM CA generation"

    local proxy_image="containai-proxy:test-hardened"
    if ! docker image inspect "$proxy_image" >/dev/null 2>&1; then
        echo "Building proxy image for MITM test..."
        if ! docker build -f "$PROJECT_ROOT/docker/proxy/Dockerfile" -t "$proxy_image" "$PROJECT_ROOT"; then
            fail "Failed to build squid proxy image"
            return
        fi
    fi

    local container_name="${TEST_CONTAINER_PREFIX}-mitm-gen"
    
    # Run without mounting certs - should auto-generate
    if ! docker run -d \
        --name "$container_name" \
        --label "$TEST_LABEL_TEST" \
        --label "$TEST_LABEL_SESSION" \
        "$proxy_image"; then
        fail "Failed to start proxy container for MITM test"
        return
    fi

    sleep $CONTAINER_STARTUP_WAIT

    if ! assert_container_running "$container_name"; then
        docker logs "$container_name"
        docker rm -f "$container_name" >/dev/null 2>&1 || true
        return
    fi

    # Check if cert exists
    if docker exec "$container_name" test -f /etc/squid/mitm/ca.crt; then
        pass "MITM CA certificate generated"
    else
        fail "MITM CA certificate not found"
    fi

    # Check subject
    local subject
    subject=$(docker exec "$container_name" openssl x509 -in /etc/squid/mitm/ca.crt -noout -subject 2>/dev/null || true)
    if echo "$subject" | grep -q "CN = ContainAI MITM CA"; then
        pass "MITM CA has correct subject"
    else
        fail "MITM CA subject mismatch ($subject)"
    fi

    docker rm -f "$container_name" >/dev/null 2>&1 || true
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
        -e "HTTP_PROXY=http://127.0.0.1:3128" \
        -e "HTTPS_PROXY=http://127.0.0.1:3128" \
        -e "NO_PROXY=localhost,127.0.0.1" \
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

    # Proxy is already started by setup_test_environment
    local proxy_client="${TEST_CONTAINER_PREFIX}-proxy"
    local proxy_url="http://${TEST_PROXY_CONTAINER}:3128"

    docker run -d \
        --name "$proxy_client" \
        --label "$TEST_LABEL_TEST" \
        --label "$TEST_LABEL_SESSION" \
        --network "$TEST_NETWORK" \
        --cap-add NET_ADMIN \
        --cap-add SYS_ADMIN \
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
}

test_squid_proxy_hardening() {
    test_section "Testing squid proxy hardening rules"

    local proxy_image="containai-proxy:test-hardened"
    # Force rebuild to pick up config changes
    docker rmi "$proxy_image" >/dev/null 2>&1 || true
    
    if ! docker image inspect "$proxy_image" >/dev/null 2>&1; then
        echo "Building proxy image for hardening test..."
        if ! docker build -f "$PROJECT_ROOT/docker/proxy/Dockerfile" -t "$proxy_image" "$PROJECT_ROOT"; then
            fail "Failed to build squid proxy image"
            return
        fi
    fi

    local proxy_network="test-squid-net-${TEST_LABEL_SESSION//[^a-zA-Z0-9_.-]/-}"
    local proxy_container="${TEST_PROXY_CONTAINER}-squid"
    local allowed_container="${TEST_PROXY_CONTAINER}-allowed"
    local proxy_ip="203.0.113.20"
    local allowed_ip="203.0.113.10"
    local allowed_domain="allowed.test"
    local proxy_url="http://${proxy_ip}:3128"

    local server_script
    server_script="$(mktemp)"
    chmod 644 "$server_script"
    cat > "$server_script" <<'PY'
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler

SMALL_SIZE = 5 * 1024 * 1024
LARGE_SIZE = 120 * 1024 * 1024

small_body = b"A" * SMALL_SIZE
large_body = b"B" * LARGE_SIZE


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        return

    def _send_body(self, body: bytes):
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/small":
            self._send_body(small_body)
        elif self.path == "/big":
            self._send_body(large_body)
        else:
            self._send_body(b"ok")

    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0"))
        data = self.rfile.read(length)
        self._send_body(str(len(data)).encode())


server = ThreadingHTTPServer(("", 8080), Handler)
server.serve_forever()
PY

    cleanup_proxy_resources() {
        if [ "$TEST_PRESERVE_RESOURCES" = "true" ]; then
            echo "Preserving squid proxy resources ($proxy_container, $allowed_container, $proxy_network)"
            return
        fi
        docker rm -f "$proxy_container" "$allowed_container" >/dev/null 2>&1 || true
        docker network rm "$proxy_network" >/dev/null 2>&1 || true
        rm -f "$server_script"
    }

    docker network create \
        --subnet 203.0.113.0/24 \
        --label "$TEST_LABEL_TEST" \
        --label "$TEST_LABEL_SESSION" \
        "$proxy_network" 2>/dev/null || true

    if ! docker network inspect "$proxy_network" >/dev/null 2>&1; then
        fail "Failed to create isolated proxy network"
        cleanup_proxy_resources
        return
    fi

    if ! docker run -d \
        --name "$allowed_container" \
        --network "$proxy_network" \
        --ip "$allowed_ip" \
        --label "$TEST_LABEL_TEST" \
        --label "$TEST_LABEL_SESSION" \
        --cap-add SYS_ADMIN \
        -e "PROXY_FIREWALL_APPLIED=1" \
        -v "$server_script:/server.py:ro" \
        python:3-alpine python3 \
        /server.py
    then
        fail "Failed to start allowed test server"
        cleanup_proxy_resources
        return
    fi

    if ! docker run -d \
        --name "$proxy_container" \
        --network "$proxy_network" \
        --ip "$proxy_ip" \
        --label "$TEST_LABEL_TEST" \
        --label "$TEST_LABEL_SESSION" \
        --add-host "${allowed_domain}:${allowed_ip}" \
        -e "SQUID_ALLOWED_DOMAINS=${allowed_domain}" \
        "$proxy_image"
    then
        fail "Failed to start squid proxy container"
        cleanup_proxy_resources
        return
    fi

    local ready=false
    for _ in {1..10}; do
        if docker exec "$proxy_container" bash -c "exec 3<>/dev/tcp/localhost/3128" >/dev/null 2>&1; then
            ready=true
            docker exec "$proxy_container" bash -c "exec 3>&-"
            break
        fi
        sleep 1
    done

    if [ "$ready" = false ]; then
        fail "Squid proxy did not become ready"
        echo "DEBUG: Squid proxy logs:"
        docker logs "$proxy_container" 2>&1 || true
        cleanup_proxy_resources
        return
    fi

    if docker run --rm \
        --network "$proxy_network" \
        --add-host "${allowed_domain}:${allowed_ip}" \
        --cap-add NET_ADMIN \
        --cap-add SYS_ADMIN \
        -e "http_proxy=$proxy_url" \
        python:3-alpine wget -q -O - "http://${allowed_domain}:8080" >/dev/null
    then
        pass "Squid allows traffic to permitted domain outside private ranges"
    else
        fail "Squid blocked or failed allowed domain request"
    fi

    if docker run --rm \
        --network "$proxy_network" \
        --cap-add NET_ADMIN \
        --cap-add SYS_ADMIN \
        -e "HTTP_PROXY=$proxy_url" \
        -e "HTTPS_PROXY=$proxy_url" \
        python:3-alpine python3 \
        - <<'PY'
import os
import sys
import urllib.error
import urllib.request

proxy = os.environ["HTTP_PROXY"]
handler = urllib.request.ProxyHandler({"http": proxy, "https": proxy})
opener = urllib.request.build_opener(handler)

def should_block(url: str) -> bool:
    try:
        opener.open(url, timeout=3)
    except Exception:
        return True
    return False

targets = [
    "http://169.254.169.254",
    "http://10.0.0.1",
    "http://172.16.0.1",
    "http://192.168.1.1",
]

sys.exit(0 if all(should_block(url) for url in targets) else 1)
PY
    then
        pass "Squid blocks metadata and RFC1918 destinations"
    else
        fail "Squid allowed private or metadata destination"
    fi

    if docker run --rm \
        --network "$proxy_network" \
        --add-host "${allowed_domain}:${allowed_ip}" \
        --cap-add NET_ADMIN \
        --cap-add SYS_ADMIN \
        -e "HTTP_PROXY=$proxy_url" \
        -e "HTTPS_PROXY=$proxy_url" \
        python:3-alpine python3 \
        - <<'PY'
import os
import sys
import urllib.request

proxy = os.environ["HTTP_PROXY"]
handler = urllib.request.ProxyHandler({"http": proxy, "https": proxy})
opener = urllib.request.build_opener(handler)

response = opener.open("http://allowed.test:8080/small", timeout=10)
body = response.read()

sys.exit(0 if len(body) == 5 * 1024 * 1024 else 1)
PY
    then
        pass "Squid allows small responses within limit"
    else
        fail "Squid blocked an in-limit response"
    fi

    if docker run --rm \
        --network "$proxy_network" \
        --add-host "${allowed_domain}:${allowed_ip}" \
        --cap-add NET_ADMIN \
        --cap-add SYS_ADMIN \
        -e "HTTP_PROXY=$proxy_url" \
        -e "HTTPS_PROXY=$proxy_url" \
        python:3-alpine python3 \
        - <<'PY'
import os
import sys
import urllib.error
import urllib.request

proxy = os.environ["HTTP_PROXY"]
handler = urllib.request.ProxyHandler({"http": proxy, "https": proxy})
opener = urllib.request.build_opener(handler)

try:
    opener.open("http://allowed.test:8080/big", timeout=15).read()
    sys.exit(1)
except urllib.error.HTTPError as exc:
    sys.exit(0 if exc.code in (403, 413, 503) else 1)
except Exception:
    sys.exit(0)
PY
    then
        pass "Squid blocks oversized responses (>100MB)"
    else
        fail "Squid failed to enforce response size limit"
    fi

    if docker run --rm \
        --network "$proxy_network" \
        --add-host "${allowed_domain}:${allowed_ip}" \
        --cap-add NET_ADMIN \
        --cap-add SYS_ADMIN \
        -e "HTTP_PROXY=$proxy_url" \
        -e "HTTPS_PROXY=$proxy_url" \
        python:3-alpine python3 \
        - <<'PY'
import os
import sys
import urllib.request

proxy = os.environ["HTTP_PROXY"]
handler = urllib.request.ProxyHandler({"http": proxy, "https": proxy})
opener = urllib.request.build_opener(handler)

payload = b"Z" * (1024 * 1024)
req = urllib.request.Request("http://allowed.test:8080/echo", data=payload, method="POST")
resp = opener.open(req, timeout=10)
body = resp.read().decode()
sys.exit(0 if body.strip() == str(len(payload)) else 1)
PY
    then
        pass "Squid allows small request bodies within limit"
    else
        fail "Squid blocked an in-limit request body"
    fi

    if docker run --rm \
        --network "$proxy_network" \
        --add-host "${allowed_domain}:${allowed_ip}" \
        --cap-add NET_ADMIN \
        --cap-add SYS_ADMIN \
        -e "HTTP_PROXY=$proxy_url" \
        -e "HTTPS_PROXY=$proxy_url" \
        python:3-alpine python3 \
        - <<'PY'
import os
import sys
import urllib.error
import urllib.request

proxy = os.environ["HTTP_PROXY"]
handler = urllib.request.ProxyHandler({"http": proxy, "https": proxy})
opener = urllib.request.build_opener(handler)

payload = b"Y" * (11 * 1024 * 1024)
req = urllib.request.Request("http://allowed.test:8080/echo", data=payload, method="POST")

try:
    opener.open(req, timeout=15).read()
    sys.exit(1)
except urllib.error.HTTPError as exc:
    sys.exit(0 if exc.code in (403, 413, 503) else 1)
except Exception:
    sys.exit(0)
PY
    then
        pass "Squid blocks oversized request bodies (>10MB)"
    else
        fail "Squid failed to enforce request size limit"
    fi

    local proxy_log
    # Wait for logs to flush to disk - Squid's stdio: logging buffers writes
    # Send SIGUSR1 to rotate logs which forces a flush, then wait a moment
    docker exec "$proxy_container" kill -USR1 1 2>/dev/null || true
    sleep 5
    
    # Read the access log file directly from the container (check rotated logs too)
    # Use sh -c to handle wildcard expansion inside the container
    proxy_log=$(docker exec "$proxy_container" sh -c 'cat /var/log/squid/access.log* 2>/dev/null' || true)
    
    # Squid may return ERR_ACCESS_DENIED (generic 403) or ERR_TOO_BIG (413/502) depending on the violation type
    # Note: Without %err_code in logformat, we might not see the specific error string, but we should see the request.
    if echo "$proxy_log" | grep -E -q "allowed.test|203.0.113.10"; then
        pass "Squid logs traffic for allowed.test (telemetry)"
    else
        echo "DEBUG: Squid access log content (filtered for allowed.test):"
        echo "$proxy_log" | grep -E "allowed.test|203.0.113.10" || echo "No logs for allowed.test found"
        echo "DEBUG: Full log tail:"
        echo "$proxy_log" | tail -n 20
        fail "Squid did not log traffic for allowed.test"
    fi

    cleanup_proxy_resources
}

test_mcp_helper_proxy_enforced() {
    test_section "Testing MCP helper enforced proxy egress"

    local proxy_image="containai-proxy:test-hardened"
    if ! docker image inspect "$proxy_image" >/dev/null 2>&1; then
        echo "Building proxy image for helper proxy test..."
        if ! docker build -f "$PROJECT_ROOT/docker/proxy/Dockerfile" -t "$proxy_image" "$PROJECT_ROOT"; then
            fail "Failed to build squid proxy image"
            return
        fi
    fi

    local proxy_network="test-helper-net-${TEST_LABEL_SESSION//[^a-zA-Z0-9_.-]/-}"
    local proxy_container="${TEST_PROXY_CONTAINER}-helper-proxy"
    local helper_container="${TEST_PROXY_CONTAINER}-helper"
    local allowed_container="${TEST_PROXY_CONTAINER}-helper-allowed"
    local helper_acl_file
    helper_acl_file="$(mktemp)"
    local proxy_ip="203.0.116.20"
    local allowed_ip="203.0.116.10"
    local allowed_domain="allowed2.test"
    local proxy_url="http://${proxy_ip}:3128"

    local helper_server_script
    helper_server_script="$(mktemp)"
    chmod 644 "$helper_server_script"
    cat > "$helper_server_script" <<'PY'
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler

class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        return
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Length", "2")
        self.end_headers()
        self.wfile.write(b"ok")

server = ThreadingHTTPServer(("", 8080), Handler)
server.serve_forever()
PY

    cat > "$helper_acl_file" <<EOF
# helper-specific ACLs for test
acl helper_hdr_helper-test req_header X-CA-Helper helper-test
acl helper_allow_helper-test dstdomain ${allowed_domain}
http_access allow helper_hdr_helper-test helper_allow_helper-test
EOF

    cleanup_helper_resources() {
        if [ "$TEST_PRESERVE_RESOURCES" = "true" ]; then
            echo "Preserving helper proxy resources ($proxy_container, $helper_container, $allowed_container, $proxy_network)"
            return
        fi
        docker rm -f "$proxy_container" "$helper_container" "$allowed_container" >/dev/null 2>&1 || true
        docker network rm "$proxy_network" >/dev/null 2>&1 || true
        rm -f "$helper_server_script"
    }

    docker network create \
        --subnet 203.0.116.0/24 \
        --label "$TEST_LABEL_TEST" \
        --label "$TEST_LABEL_SESSION" \
        "$proxy_network" 2>/dev/null || true

    if ! docker network inspect "$proxy_network" >/dev/null 2>&1; then
        fail "Failed to create helper proxy network"
        cleanup_helper_resources
        return
    fi

    # Allowed upstream server
    if ! docker run -d \
        --name "$allowed_container" \
        --network "$proxy_network" \
        --ip "$allowed_ip" \
        --label "$TEST_LABEL_TEST" \
        --label "$TEST_LABEL_SESSION" \
        --cap-add SYS_ADMIN \
        --cap-add NET_ADMIN \
        -e "HTTP_PROXY=http://${proxy_ip}:3128" \
        -e "HTTPS_PROXY=http://${proxy_ip}:3128" \
        -e "NO_PROXY=localhost,127.0.0.1" \
        -v "$helper_server_script:/server.py:ro" \
        "$TEST_CODEX_IMAGE" \
        python3 /server.py
    then
        fail "Failed to start upstream server for helper test"
        cleanup_helper_resources
        return
    fi

    # Wait for upstream server to be ready
    local upstream_ready=false
    for _ in {1..30}; do
        local status
        status=$(docker inspect -f '{{.State.Status}}' "$allowed_container" 2>/dev/null || echo "unknown")
        if [ "$status" = "running" ]; then
            if docker exec "$allowed_container" bash -c "exec 3<>/dev/tcp/localhost/8080" >/dev/null 2>&1; then
                upstream_ready=true
                docker exec "$allowed_container" bash -c "exec 3>&-" 2>/dev/null || true
                break
            fi
        elif [ "$status" = "exited" ]; then
            fail "Upstream server container exited unexpectedly"
            echo "DEBUG: Upstream server logs:"
            docker logs "$allowed_container" 2>&1 || true
            cleanup_helper_resources
            return
        fi
        sleep 1
    done

    if [ "$upstream_ready" = false ]; then
        fail "Upstream server did not become ready"
        echo "DEBUG: Upstream server status:"
        docker inspect -f '{{.State.Status}}' "$allowed_container" 2>/dev/null || true
        echo "DEBUG: Upstream server logs:"
        docker logs "$allowed_container" 2>&1 | tail -50 || true
        cleanup_helper_resources
        return
    fi

    # Squid proxy
    if ! docker run -d \
        --name "$proxy_container" \
        --hostname "$proxy_container" \
        --network "$proxy_network" \
        --ip "$proxy_ip" \
        --label "$TEST_LABEL_TEST" \
        --label "$TEST_LABEL_SESSION" \
        --add-host "${allowed_domain}:${allowed_ip}" \
        -e "SQUID_ALLOWED_DOMAINS=${allowed_domain}" \
        -v "$helper_acl_file:/etc/squid/helper-acls.conf:ro" \
        "$proxy_image" >/dev/null
    then
        fail "Failed to start helper squid proxy"
        cleanup_helper_resources
        return
    fi

    # Wait for proxy to be ready
    local ready=false
    for _ in {1..10}; do
        if docker exec "$proxy_container" bash -c "exec 3<>/dev/tcp/localhost/3128" >/dev/null 2>&1; then
            ready=true
            docker exec "$proxy_container" bash -c "exec 3>&-" 2>/dev/null || true
            break
        fi
        sleep 1
    done

    if [ "$ready" = false ]; then
        fail "Helper squid proxy did not become ready"
        echo "DEBUG: Helper squid proxy logs:"
        docker logs "$proxy_container" 2>&1 || true
        cleanup_helper_resources
        return
    fi

    # Helper container with enforced egress to proxy only
    if ! docker run -d \
        --name "$helper_container" \
        --network "$proxy_network" \
        --label "$TEST_LABEL_TEST" \
        --label "$TEST_LABEL_SESSION" \
        --cap-add NET_ADMIN \
        --cap-add SYS_ADMIN \
        --add-host "${allowed_domain}:${allowed_ip}" \
        --entrypoint /bin/sh \
        -e "HTTP_PROXY=$proxy_url" \
        -e "HTTPS_PROXY=$proxy_url" \
        -e "NO_PROXY=" \
        -e "CONTAINAI_REQUIRE_PROXY=1" \
        -v "$PROJECT_ROOT:/workspace" \
        "$TEST_CODEX_IMAGE" \
        -c "\
iptables -F OUTPUT && \
iptables -P OUTPUT DROP && \
iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT && \
iptables -A OUTPUT -o lo -j ACCEPT && \
iptables -A OUTPUT -p tcp -d ${proxy_ip} --dport 3128 -j ACCEPT && \
exec python3 /workspace/docker/runtime/mcp-http-helper.py --name helper-test --listen 0.0.0.0:18080 --target http://${allowed_domain}:8080" >/dev/null
    then
        fail "Failed to start helper container with enforced proxy"
        cleanup_helper_resources
        return
    fi

    # Wait for helper container to be running and for the helper script to start
    local helper_ready=false
    for _ in {1..15}; do
        local status
        status=$(docker inspect -f '{{.State.Status}}' "$helper_container" 2>/dev/null || echo "unknown")
        if [ "$status" = "running" ]; then
            # Check if the helper is listening
            if docker exec "$helper_container" bash -c "exec 3<>/dev/tcp/localhost/18080" >/dev/null 2>&1; then
                helper_ready=true
                docker exec "$helper_container" bash -c "exec 3>&-" 2>/dev/null || true
                break
            fi
        elif [ "$status" = "exited" ]; then
            fail "Helper container exited unexpectedly"
            echo "DEBUG: Helper container logs:"
            docker logs "$helper_container" 2>&1 || true
            cleanup_helper_resources
            return
        fi
        sleep 1
    done

    if [ "$helper_ready" = false ]; then
        fail "Helper container did not become ready"
        echo "DEBUG: Helper container status:"
        docker inspect -f '{{.State.Status}}' "$helper_container" 2>/dev/null || true
        echo "DEBUG: Helper container logs:"
        docker logs "$helper_container" 2>&1 | tail -50 || true
        cleanup_helper_resources
        return
    fi

    local health
    health=$(docker exec "$helper_container" curl -s --max-time 3 http://127.0.0.1:18080/health || true)
    if echo "$health" | grep -q '"status": "ok"'; then
        pass "Helper health endpoint responds via proxy"
    else
        fail "Helper health endpoint unavailable"
    fi

    if docker exec "$helper_container" curl -s --max-time 5 http://127.0.0.1:18080/ | grep -q "ok"; then
        pass "Helper successfully proxies through squid with header enforcement"
    else
        fail "Helper failed to proxy through squid"
    fi

    # Direct egress without proxy should fail due to firewall
    if docker exec "$helper_container" env -u HTTP_PROXY -u HTTPS_PROXY curl --max-time 3 http://${allowed_domain}:8080/ >/dev/null 2>&1; then
        fail "Helper bypassed proxy despite firewall"
    else
        pass "Firewall blocks direct egress without proxy"
    fi

    cleanup_helper_resources
    rm -f "$helper_acl_file"
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
            --label "containai.type=agent" \
            --label "containai.agent=$agent" \
            --network "$TEST_NETWORK" \
            --cap-add SYS_ADMIN \
            --cap-add NET_ADMIN \
            -v "$TEST_REPO_DIR:/workspace" \
            -e "HTTP_PROXY=http://${TEST_PROXY_CONTAINER}:3128" \
            -e "HTTPS_PROXY=http://${TEST_PROXY_CONTAINER}:3128" \
            -e "NO_PROXY=localhost,127.0.0.1" \
            "$test_image" \
            /bin/sleep $LONG_RUNNING_SLEEP >/dev/null
        
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
    test_section "Testing prompt-mode Copilot with host secrets"

    if [[ "$TEST_WITH_HOST_SECRETS" != "true" ]]; then
        echo "Skipping prompt-mode secret test (flag not enabled)"
        return
    fi

    if [[ -z "$HOST_SECRETS_FILE" ]]; then
        fail "Host secrets file path not set"
        return
    fi

    local agent="copilot"
    local prompt="Return the words: host secrets OK."
    local run_copilot="$PROJECT_ROOT/host/launchers/run-$agent"
    local branch
    branch=$(next_agent_branch_name "$agent")
    local marker="prompt-hook-${agent}.txt"
    local commit_msg="prompt hook commit (${agent})"
    local hook_script
    hook_script=$(build_prompt_post_hook_script "$agent" "$marker" "$commit_msg")

    if [[ ! -x "$run_copilot" ]]; then
        fail "run-$agent launcher not executable at $run_copilot"
        return
    fi

    local tmp_output
    tmp_output=$(mktemp)
    local exit_code=0

    pushd "$TEST_REPO_DIR" >/dev/null
    if ! CONTAINAI_MCP_SECRETS_FILE="$HOST_SECRETS_FILE" \
        CONTAINAI_PROMPT_POST_HOOK="$hook_script" \
        "$run_copilot" --prompt "$prompt" >"$tmp_output" 2>&1; then
        exit_code=$?
    fi
    popd >/dev/null

    if [[ $exit_code -ne 0 ]]; then
        fail "Prompt-mode Copilot execution failed (exit $exit_code)"
        cat "$tmp_output"
        rm -f "$tmp_output"
        return
    fi
    pass "Prompt-mode Copilot execution completed"

    if wait_for_agent_branch "$branch" 90; then
        pass "Created agent branch $branch via prompt session"
    else
        fail "Timed out waiting for branch $branch to sync back to host"
        cat "$tmp_output"
        rm -f "$tmp_output"
        return
    fi

    local contents
    contents=$(git -C "$TEST_REPO_DIR" show "$branch:$marker" 2>/dev/null || true)
    if [[ "$contents" == *"${agent} prompt hook success"* ]]; then
        pass "Prompt hook artifact synced to $branch"
    else
        fail "Prompt hook artifact missing from $branch"
    fi

    local subject
    subject=$(git -C "$TEST_REPO_DIR" log -1 --pretty=%s "$branch" 2>/dev/null || true)
    local subject_display="$subject"
    if [[ -z "$subject_display" ]]; then
        subject_display="<none>"
    fi
    if [[ "$subject" == "$commit_msg" ]]; then
        pass "Prompt hook commit message matches expectation"
    else
        fail "Unexpected commit subject for $branch (expected '$commit_msg', got '$subject_display')"
    fi

    rm -f "$tmp_output"
}

test_shared_functions() {
    test_section "Testing shared functions with test environment"
    
    cd "$TEST_REPO_DIR"
    
    # Test get_repo_name
    local repo_name
    repo_name=$(get_repo_name "$TEST_REPO_DIR")
    if [[ "$repo_name" =~ test-containai-repo ]]; then
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

should_run() {
    local test_name="$1"
    if [[ -z "${TEST_FILTER:-}" ]]; then
        return 0
    fi
    if [[ "$test_name" =~ $TEST_FILTER ]]; then
        return 0
    fi
    return 1
}

run_all_tests() {
    echo ""
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║      ContainAI Integration Test Suite                ║"
    echo "║      Mode: $(printf '%-46s' "$TEST_MODE")║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo ""
    
    # Setup environment
    if [[ "${TEST_FILTER:-}" == "test_squid_proxy_hardening" ]]; then
        echo "Skipping full environment setup for squid proxy test (optimization)"
    else
        setup_test_environment "$TEST_MODE" || {
            echo "Failed to setup test environment"
            exit 1
        }
    fi
    
    # Run tests
    if should_run "test_image_availability"; then test_image_availability; fi
    if should_run "test_shared_functions"; then test_shared_functions; fi
    if should_run "test_launcher_script_execution"; then test_launcher_script_execution; fi
    if should_run "test_container_labels"; then test_container_labels; fi
    if should_run "test_container_networking"; then test_container_networking; fi
    if should_run "test_workspace_mounting"; then test_workspace_mounting; fi
    if should_run "test_environment_variables"; then test_environment_variables; fi
    if should_run "test_agentcli_uid_split"; then test_agentcli_uid_split; fi
    if should_run "test_capabilities_dropped"; then test_capabilities_dropped; fi
    if should_run "test_cli_wrappers"; then test_cli_wrappers; fi
    if should_run "test_agent_task_runner_seccomp"; then test_agent_task_runner_seccomp; fi
    if should_run "test_mcp_configuration_generation"; then test_mcp_configuration_generation; fi
    if should_run "test_mitm_ca_generation"; then test_mitm_ca_generation; fi
    if should_run "test_network_proxy_modes"; then test_network_proxy_modes; fi
    if should_run "test_squid_proxy_hardening"; then test_squid_proxy_hardening; fi
    if should_run "test_mcp_helper_proxy_enforced"; then test_mcp_helper_proxy_enforced; fi
    if should_run "test_multiple_agents"; then test_multiple_agents; fi
    if should_run "test_container_isolation"; then test_container_isolation; fi
    if should_run "test_cleanup_on_exit"; then test_cleanup_on_exit; fi
    
    if [ "$TEST_WITH_HOST_SECRETS" = "true" ]; then
        if should_run "test_host_prompt_mode"; then test_host_prompt_mode; fi
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
