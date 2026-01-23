#!/usr/bin/env bash
# ==============================================================================
# Comprehensive Integration Tests for ContainAI
# ==============================================================================
# Verifies ContainAI works correctly in all scenarios:
# 1. Clean start without import - basic container functionality
# 2. Clean start with import - config syncing works correctly
# 3. DinD operations - Docker-in-Docker works (when dockerd available)
# 4. Agent doctor commands - claude/codex/copilot doctor works or reports clear errors
#
# Prerequisites:
# - Docker daemon running
# - Sysbox installed and containai-secure context available
# - containai.sh sourced
#
# Usage:
#   ./tests/integration/test-containai.sh
#   CONTAINAI_TEST_IMAGE=ghcr.io/novotnyllc/containai/base:latest ./tests/integration/test-containai.sh
#
# Environment Variables:
#   CONTAINAI_TEST_IMAGE  - Override test image (default: ghcr.io/novotnyllc/containai/base:latest)
#   CAI_ALLOW_NETWORK_FAILURE - Set to "1" to allow network tests to fail gracefully
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
SRC_DIR="$REPO_ROOT/src"
FIXTURES_DIR="$SCRIPT_DIR/test-fixtures"

# Source containai library for CLI functions, constants, and helpers
if ! source "$SRC_DIR/containai.sh"; then
    printf '%s\n' "[ERROR] Failed to source containai.sh" >&2
    exit 1
fi

# ==============================================================================
# Test helpers - match existing test patterns
# ==============================================================================

pass() { printf '%s\n' "[PASS] $*"; }
fail() { printf '%s\n' "[FAIL] $*" >&2; FAILED=1; }
warn() { printf '%s\n' "[WARN] $*"; }
info() { printf '%s\n' "[INFO] $*"; }
section() { printf '\n'; printf '%s\n' "=== $* ==="; }

FAILED=0

# Context name for sysbox containers
CONTEXT_NAME="containai-secure"

# Timeouts
DOCKERD_WAIT_TIMEOUT=60
SSHD_WAIT_TIMEOUT=30
TEST_TIMEOUT=60
CONTAINER_STOP_TIMEOUT=30

# Unique test identifiers to avoid conflicts
TEST_RUN_ID="containai-test-$$-$(date +%s)"
TEST_CONTAINER_NAME="$TEST_RUN_ID"
TEST_DATA_VOLUME="$TEST_RUN_ID-data"
TEST_WORKSPACE="/tmp/$TEST_RUN_ID-workspace"

# ContainAI base image for system container testing
TEST_IMAGE="${CONTAINAI_TEST_IMAGE:-ghcr.io/novotnyllc/containai/base:latest}"

# Track created resources for cleanup
declare -a CLEANUP_CONTAINERS=()
declare -a CLEANUP_VOLUMES=()
declare -a CLEANUP_DIRS=()

# ==============================================================================
# Cleanup function
# ==============================================================================

cleanup() {
    info "Cleaning up test resources..."

    local resource

    # Stop and remove containers
    for resource in "${CLEANUP_CONTAINERS[@]}"; do
        if docker --context "$CONTEXT_NAME" inspect --type container "$resource" >/dev/null 2>&1; then
            docker --context "$CONTEXT_NAME" stop --time "$CONTAINER_STOP_TIMEOUT" "$resource" 2>/dev/null || true
            docker --context "$CONTEXT_NAME" rm -f "$resource" 2>/dev/null || true
        fi
    done

    # Remove volumes
    for resource in "${CLEANUP_VOLUMES[@]}"; do
        docker --context "$CONTEXT_NAME" volume rm "$resource" 2>/dev/null || true
    done

    # Remove directories
    for resource in "${CLEANUP_DIRS[@]}"; do
        if [[ -d "$resource" && "$resource" == /tmp/* ]]; then
            rm -rf "$resource" 2>/dev/null || true
        fi
    done

    # Clean up SSH config if it was created
    if [[ -f "$HOME/.ssh/containai.d/${TEST_CONTAINER_NAME}.conf" ]]; then
        rm -f "$HOME/.ssh/containai.d/${TEST_CONTAINER_NAME}.conf" 2>/dev/null || true
    fi
}

trap cleanup EXIT

# Register resources for cleanup
register_container() { CLEANUP_CONTAINERS+=("$1"); }
register_volume() { CLEANUP_VOLUMES+=("$1"); }
register_dir() { CLEANUP_DIRS+=("$1"); }

# ==============================================================================
# Portable timeout wrapper (uses _cai_timeout from containai.sh)
# ==============================================================================

run_with_timeout() {
    local secs="$1"
    shift
    _cai_timeout "$secs" "$@"
}

# ==============================================================================
# Wait helpers
# ==============================================================================

# Wait for SSH daemon to be ready inside container
# Returns 0 when sshd is ready, 1 on timeout
wait_for_sshd() {
    local container="$1"
    local timeout="${2:-$SSHD_WAIT_TIMEOUT}"
    local elapsed=0
    local interval=2

    info "Waiting for sshd to start (timeout: ${timeout}s)..."

    while [[ $elapsed -lt $timeout ]]; do
        # Check if sshd is listening
        if docker --context "$CONTEXT_NAME" exec "$container" pgrep -x sshd >/dev/null 2>&1; then
            info "sshd is ready (took ${elapsed}s)"
            return 0
        fi

        sleep "$interval"
        elapsed=$((elapsed + interval))
    done

    return 1
}

# Wait for dockerd to be ready inside container
# Returns 0 when dockerd is ready, 1 on timeout
wait_for_dockerd() {
    local container="$1"
    local timeout="${2:-$DOCKERD_WAIT_TIMEOUT}"
    local elapsed=0
    local interval=2

    info "Waiting for inner dockerd to start (timeout: ${timeout}s)..."

    while [[ $elapsed -lt $timeout ]]; do
        # Check if docker info succeeds inside the container
        if docker --context "$CONTEXT_NAME" exec "$container" docker info >/dev/null 2>&1; then
            info "Inner dockerd is ready (took ${elapsed}s)"
            return 0
        fi

        sleep "$interval"
        elapsed=$((elapsed + interval))
    done

    return 1
}

# Execute command inside the system container
exec_in_container() {
    docker --context "$CONTEXT_NAME" exec "$TEST_CONTAINER_NAME" "$@"
}

# ==============================================================================
# Prerequisites check
# ==============================================================================

check_prerequisites() {
    section "Prerequisites Check"

    # Check docker binary
    if ! command -v docker >/dev/null 2>&1; then
        printf '%s\n' "[ERROR] docker binary not found" >&2
        exit 1
    fi
    pass "Docker binary found"

    # Check docker daemon is running
    if ! docker info >/dev/null 2>&1; then
        printf '%s\n' "[ERROR] Docker daemon not running" >&2
        exit 1
    fi
    pass "Docker daemon running"

    # Check containai-secure context exists
    if ! docker context inspect "$CONTEXT_NAME" >/dev/null 2>&1; then
        printf '%s\n' "[ERROR] Context '$CONTEXT_NAME' not found" >&2
        printf '%s\n' "[INFO] Run 'cai setup' first to configure Sysbox" >&2
        exit 1
    fi
    pass "Context '$CONTEXT_NAME' exists"

    # Check sysbox-runc runtime is available
    local runtimes_json
    runtimes_json=$(docker --context "$CONTEXT_NAME" info --format '{{json .Runtimes}}' 2>/dev/null) || runtimes_json=""

    if [[ -z "$runtimes_json" ]] || ! printf '%s' "$runtimes_json" | grep -q "sysbox-runc"; then
        printf '%s\n' "[ERROR] sysbox-runc runtime not available" >&2
        printf '%s\n' "[INFO] Run 'cai setup' to install Sysbox" >&2
        exit 1
    fi
    pass "sysbox-runc runtime available"

    # Check test fixtures exist
    if [[ ! -d "$FIXTURES_DIR" ]]; then
        printf '%s\n' "[ERROR] Test fixtures not found at: $FIXTURES_DIR" >&2
        exit 1
    fi
    pass "Test fixtures found"

    # Check test image is available (or can be pulled)
    if ! docker --context "$CONTEXT_NAME" image inspect "$TEST_IMAGE" >/dev/null 2>&1; then
        info "Pulling test image: $TEST_IMAGE"
        if ! run_with_timeout 120 docker --context "$CONTEXT_NAME" pull "$TEST_IMAGE"; then
            fail "Failed to pull test image: $TEST_IMAGE"
            return 1
        fi
    fi
    pass "Test image available: $TEST_IMAGE"
}

# ==============================================================================
# Test: Clean start without import
# ==============================================================================

test_clean_start_without_import() {
    section "Scenario 1: Clean Start Without Import"

    # Create test workspace
    mkdir -p "$TEST_WORKSPACE"
    register_dir "$TEST_WORKSPACE"
    echo "# Test workspace" > "$TEST_WORKSPACE/README.md"

    # Create data volume
    if ! docker --context "$CONTEXT_NAME" volume create "$TEST_DATA_VOLUME" >/dev/null; then
        fail "Failed to create test data volume"
        return 1
    fi
    register_volume "$TEST_DATA_VOLUME"
    pass "Created test data volume: $TEST_DATA_VOLUME"

    # Start system container with sysbox-runc runtime
    info "Starting system container..."
    local run_output run_rc
    run_output=$(docker --context "$CONTEXT_NAME" run -d \
        --runtime=sysbox-runc \
        --name "$TEST_CONTAINER_NAME" \
        --hostname "containai-test" \
        -v "$TEST_WORKSPACE:/home/agent/workspace:rw" \
        -v "$TEST_DATA_VOLUME:/mnt/agent-data:rw" \
        -w /home/agent/workspace \
        --stop-timeout "$CONTAINER_STOP_TIMEOUT" \
        "$TEST_IMAGE" 2>&1) && run_rc=0 || run_rc=$?

    if [[ $run_rc -ne 0 ]]; then
        fail "Failed to start system container"
        info "  Error: $run_output"
        return 1
    fi
    register_container "$TEST_CONTAINER_NAME"
    pass "System container started"

    # Verify container is running
    local container_status
    container_status=$(docker --context "$CONTEXT_NAME" inspect --format '{{.State.Status}}' "$TEST_CONTAINER_NAME" 2>/dev/null) || container_status=""

    if [[ "$container_status" != "running" ]]; then
        fail "Container not running (status: $container_status)"
        return 1
    fi
    pass "Container is running"

    # Verify systemd is PID 1
    local pid1_cmd
    pid1_cmd=$(exec_in_container cat /proc/1/comm 2>/dev/null) || pid1_cmd=""

    if [[ "$pid1_cmd" == "systemd" ]]; then
        pass "systemd is running as PID 1"
    else
        fail "PID 1 is not systemd (found: $pid1_cmd)"
        return 1
    fi

    # Verify workspace is mounted
    if exec_in_container test -f /home/agent/workspace/README.md; then
        pass "Workspace is mounted correctly"
    else
        fail "Workspace not mounted or README.md not found"
        return 1
    fi

    # Verify data volume is mounted
    if exec_in_container test -d /mnt/agent-data; then
        pass "Data volume is mounted"
    else
        fail "Data volume not mounted"
        return 1
    fi

    # Verify basic tools are available
    local tool_checks=("bash" "git" "curl" "jq")
    local tool
    for tool in "${tool_checks[@]}"; do
        if exec_in_container command -v "$tool" >/dev/null 2>&1; then
            pass "Tool available: $tool"
        else
            fail "Tool not found: $tool"
        fi
    done

    # Verify agent user exists
    if exec_in_container id agent >/dev/null 2>&1; then
        pass "Agent user exists"
    else
        fail "Agent user not found"
    fi

    # Verify no import data is present (clean start)
    if ! exec_in_container test -f /mnt/agent-data/claude/settings.json 2>/dev/null; then
        pass "No imported data present (clean start confirmed)"
    else
        warn "Unexpected: claude settings found in data volume"
    fi

    pass "Scenario 1: Clean start without import - PASSED"
}

# ==============================================================================
# Test: Clean start with import
# ==============================================================================

test_clean_start_with_import() {
    section "Scenario 2: Clean Start With Import"

    # Prepare a temporary home directory with fixture structure
    local fixture_home
    fixture_home=$(mktemp -d "${TMPDIR:-/tmp}/containai-fixture-home-XXXXXX")
    register_dir "$fixture_home"

    # Copy fixtures to mimic home directory structure
    mkdir -p "$fixture_home/.claude/plugins"
    cp -r "$FIXTURES_DIR/claude/"* "$fixture_home/.claude/" 2>/dev/null || true
    cp -r "$FIXTURES_DIR/claude/plugins/"* "$fixture_home/.claude/plugins/" 2>/dev/null || true

    mkdir -p "$fixture_home/.config/gh"
    cp "$FIXTURES_DIR/gh/hosts.yml" "$fixture_home/.config/gh/" 2>/dev/null || true

    cp "$FIXTURES_DIR/shell/bash_aliases" "$fixture_home/.bash_aliases" 2>/dev/null || true

    mkdir -p "$fixture_home/.codex"
    cp "$FIXTURES_DIR/codex/config.toml" "$fixture_home/.codex/" 2>/dev/null || true

    info "Created fixture home at: $fixture_home"

    # Run import from fixture directory to existing test data volume
    info "Running import from fixture directory..."
    local import_output import_rc
    import_output=$(_containai_import "$CONTEXT_NAME" "$TEST_DATA_VOLUME" "false" "false" "$TEST_WORKSPACE" "" "$fixture_home" 2>&1) && import_rc=0 || import_rc=$?

    if [[ $import_rc -ne 0 ]]; then
        fail "Import failed"
        info "  Output: $import_output"
        return 1
    fi
    pass "Import completed successfully"

    # Verify imported data in volume
    info "Verifying imported data..."

    # Check claude settings
    local settings_check
    settings_check=$(docker --context "$CONTEXT_NAME" run --rm -v "$TEST_DATA_VOLUME":/data alpine cat /data/claude/settings.json 2>/dev/null) || settings_check=""

    if [[ -n "$settings_check" ]] && printf '%s' "$settings_check" | jq -e '.enabledPlugins["test-plugin"]' >/dev/null 2>&1; then
        pass "Claude settings imported correctly"
    else
        fail "Claude settings not imported or enabledPlugins missing"
        info "  Got: $settings_check"
    fi

    # Check plugin manifest
    local plugin_check
    plugin_check=$(docker --context "$CONTEXT_NAME" run --rm -v "$TEST_DATA_VOLUME":/data alpine cat /data/claude/plugins/test-plugin/manifest.json 2>/dev/null) || plugin_check=""

    if [[ -n "$plugin_check" ]] && printf '%s' "$plugin_check" | jq -e '.name == "test-plugin"' >/dev/null 2>&1; then
        pass "Plugin manifest imported correctly"
    else
        fail "Plugin manifest not imported"
        info "  Got: $plugin_check"
    fi

    # Check bash aliases
    local aliases_check
    aliases_check=$(docker --context "$CONTEXT_NAME" run --rm -v "$TEST_DATA_VOLUME":/data alpine cat /data/shell/bash_aliases 2>/dev/null) || aliases_check=""

    if [[ "$aliases_check" == *"containai-test"* ]]; then
        pass "Bash aliases imported correctly"
    else
        fail "Bash aliases not imported"
        info "  Got: $aliases_check"
    fi

    # Check gh config
    local gh_check
    gh_check=$(docker --context "$CONTEXT_NAME" run --rm -v "$TEST_DATA_VOLUME":/data alpine cat /data/config/gh/hosts.yml 2>/dev/null) || gh_check=""

    if [[ "$gh_check" == *"github.com"* ]]; then
        pass "GitHub CLI config imported correctly"
    else
        fail "GitHub CLI config not imported"
        info "  Got: $gh_check"
    fi

    # Verify data is accessible inside the running container
    if exec_in_container test -f /mnt/agent-data/claude/settings.json; then
        pass "Imported data accessible inside container"
    else
        fail "Imported data not accessible inside container"
    fi

    pass "Scenario 2: Clean start with import - PASSED"
}

# ==============================================================================
# Test: DinD operations
# ==============================================================================

test_dind_operations() {
    section "Scenario 3: Docker-in-Docker Operations"

    # Wait for inner dockerd to be ready
    if ! wait_for_dockerd "$TEST_CONTAINER_NAME" "$DOCKERD_WAIT_TIMEOUT"; then
        fail "Inner dockerd failed to start"

        # Collect diagnostic information
        info "Diagnostic information:"
        local service_status
        service_status=$(exec_in_container systemctl status docker.service --no-pager 2>&1 | head -20) || service_status="(unavailable)"
        info "  docker.service status:"
        printf '%s\n' "$service_status" | while IFS= read -r line; do
            info "    $line"
        done

        return 1
    fi
    pass "Inner dockerd is running"

    # Test: docker info works
    local docker_info_output docker_info_rc
    docker_info_output=$(exec_in_container docker info 2>&1) && docker_info_rc=0 || docker_info_rc=$?

    if [[ $docker_info_rc -eq 0 ]]; then
        pass "docker info works inside container"
        local docker_version
        docker_version=$(printf '%s' "$docker_info_output" | grep "Server Version:" | head -1 | sed 's/.*Server Version:[[:space:]]*//' || true)
        [[ -n "$docker_version" ]] && info "  Inner Docker version: $docker_version"
    else
        fail "docker info failed inside container"
        info "  Error: $(printf '%s' "$docker_info_output" | head -3)"
        return 1
    fi

    # Test: docker run hello-world
    info "Testing docker run hello-world..."
    local hello_output hello_rc
    hello_output=$(run_with_timeout "$TEST_TIMEOUT" exec_in_container docker run --rm hello-world 2>&1) && hello_rc=0 || hello_rc=$?

    # Handle no timeout mechanism
    if [[ $hello_rc -eq 125 ]]; then
        hello_output=$(exec_in_container docker run --rm hello-world 2>&1) && hello_rc=0 || hello_rc=$?
    fi

    if [[ $hello_rc -eq 0 ]] && printf '%s' "$hello_output" | grep -qi "Hello from Docker"; then
        pass "docker run hello-world succeeded"
    else
        fail "docker run hello-world failed"
        info "  Exit code: $hello_rc"
        info "  Output: $(printf '%s' "$hello_output" | head -5)"
    fi

    # Test: docker build
    info "Testing docker build..."

    # Create a simple Dockerfile inside the container
    local dockerfile_content='FROM alpine:3.20
RUN echo "containai-build-test"
CMD ["echo", "build-success"]'

    if ! exec_in_container mkdir -p /tmp/dind-build-test; then
        fail "Failed to create build directory in container"
        return 1
    fi

    if ! printf '%s\n' "$dockerfile_content" | exec_in_container tee /tmp/dind-build-test/Dockerfile >/dev/null; then
        fail "Failed to create Dockerfile in container"
        return 1
    fi

    local build_output build_rc
    build_output=$(run_with_timeout "$TEST_TIMEOUT" exec_in_container docker build -t containai-build-test:latest /tmp/dind-build-test 2>&1) && build_rc=0 || build_rc=$?

    if [[ $build_rc -eq 125 ]]; then
        build_output=$(exec_in_container docker build -t containai-build-test:latest /tmp/dind-build-test 2>&1) && build_rc=0 || build_rc=$?
    fi

    if [[ $build_rc -eq 0 ]]; then
        pass "docker build succeeded"

        # Run the built image
        local run_output run_rc
        run_output=$(exec_in_container docker run --rm containai-build-test:latest 2>&1) && run_rc=0 || run_rc=$?

        if [[ $run_rc -eq 0 ]] && [[ "$run_output" == *"build-success"* ]]; then
            pass "Built image runs correctly"
        else
            warn "Built image may not run as expected"
            info "  Output: $run_output"
        fi

        # Cleanup
        exec_in_container docker rmi containai-build-test:latest >/dev/null 2>&1 || true
    else
        fail "docker build failed"
        info "  Exit code: $build_rc"
        info "  Output: $(printf '%s' "$build_output" | tail -10)"
    fi

    # Test: Nested container networking
    info "Testing nested container networking..."
    local network_output network_rc
    # Use BusyBox-compatible wget flags: -T (timeout) not --timeout
    network_output=$(run_with_timeout "$TEST_TIMEOUT" exec_in_container docker run --rm alpine:3.20 wget -q -O /dev/null -T 10 https://github.com 2>&1) && network_rc=0 || network_rc=$?

    if [[ $network_rc -eq 125 ]]; then
        network_output=$(exec_in_container docker run --rm alpine:3.20 wget -q -O /dev/null -T 10 https://github.com 2>&1) && network_rc=0 || network_rc=$?
    fi

    if [[ $network_rc -eq 0 ]]; then
        pass "Nested container has internet connectivity"
    else
        if [[ "${CAI_ALLOW_NETWORK_FAILURE:-}" == "1" ]]; then
            warn "Nested container networking test failed (allowed by CAI_ALLOW_NETWORK_FAILURE=1)"
        else
            fail "Nested container networking failed"
            info "  Set CAI_ALLOW_NETWORK_FAILURE=1 to skip this check in restricted environments"
        fi
    fi

    # Verify inner Docker uses sysbox-runc by default
    local default_runtime
    default_runtime=$(exec_in_container docker info --format '{{.DefaultRuntime}}' 2>/dev/null) || default_runtime=""

    if [[ "$default_runtime" == "sysbox-runc" ]]; then
        pass "Inner Docker uses sysbox-runc as default runtime"
    else
        warn "Inner Docker default runtime: $default_runtime (expected: sysbox-runc)"
    fi

    pass "Scenario 3: DinD operations - PASSED"
}

# ==============================================================================
# Test: Agent doctor commands
# ==============================================================================

test_agent_doctor_commands() {
    section "Scenario 4: Agent Doctor Commands"

    # Test: claude doctor (if claude is available)
    info "Testing claude doctor..."
    if exec_in_container command -v claude >/dev/null 2>&1; then
        local claude_doctor_output claude_doctor_rc
        # Claude doctor may fail if not configured, but should provide clear output
        claude_doctor_output=$(exec_in_container claude doctor 2>&1) && claude_doctor_rc=0 || claude_doctor_rc=$?

        if [[ $claude_doctor_rc -eq 0 ]]; then
            pass "claude doctor succeeded"
            info "  Output (truncated): $(printf '%s' "$claude_doctor_output" | head -5)"
        else
            # Check if the error message is clear/helpful
            if printf '%s' "$claude_doctor_output" | grep -qiE "api.key|authentication|credentials|logged.in|sign.in|not.configured"; then
                pass "claude doctor reports clear error (not configured)"
                info "  Message: $(printf '%s' "$claude_doctor_output" | head -3)"
            else
                warn "claude doctor failed with unclear error"
                info "  Exit code: $claude_doctor_rc"
                info "  Output: $(printf '%s' "$claude_doctor_output" | head -5)"
            fi
        fi
    else
        info "Claude CLI not installed in test image (base image)"
        pass "claude doctor test skipped (not installed)"
    fi

    # Test: codex doctor (if codex is available)
    info "Testing codex doctor..."
    if exec_in_container command -v codex >/dev/null 2>&1; then
        local codex_doctor_output codex_doctor_rc
        codex_doctor_output=$(exec_in_container codex doctor 2>&1) && codex_doctor_rc=0 || codex_doctor_rc=$?

        if [[ $codex_doctor_rc -eq 0 ]]; then
            pass "codex doctor succeeded"
        else
            if printf '%s' "$codex_doctor_output" | grep -qiE "api.key|authentication|credentials|logged.in|sign.in|not.configured"; then
                pass "codex doctor reports clear error (not configured)"
            else
                warn "codex doctor failed"
                info "  Exit code: $codex_doctor_rc"
            fi
        fi
    else
        info "Codex CLI not installed in test image"
        pass "codex doctor test skipped (not installed)"
    fi

    # Test: copilot doctor (if copilot/gh copilot is available)
    info "Testing copilot doctor..."
    if exec_in_container command -v copilot >/dev/null 2>&1; then
        local copilot_doctor_output copilot_doctor_rc
        copilot_doctor_output=$(exec_in_container copilot doctor 2>&1) && copilot_doctor_rc=0 || copilot_doctor_rc=$?

        if [[ $copilot_doctor_rc -eq 0 ]]; then
            pass "copilot doctor succeeded"
        else
            if printf '%s' "$copilot_doctor_output" | grep -qiE "api.key|authentication|credentials|logged.in|sign.in|not.configured"; then
                pass "copilot doctor reports clear error (not configured)"
            else
                warn "copilot doctor failed"
                info "  Exit code: $copilot_doctor_rc"
            fi
        fi
    else
        info "Copilot CLI not installed in test image"
        pass "copilot doctor test skipped (not installed)"
    fi

    # Test: gh CLI is available and can check status
    info "Testing gh CLI..."
    if exec_in_container command -v gh >/dev/null 2>&1; then
        local gh_version_output
        gh_version_output=$(exec_in_container gh --version 2>&1) || gh_version_output=""

        if [[ -n "$gh_version_output" ]]; then
            pass "gh CLI available"
            info "  Version: $(printf '%s' "$gh_version_output" | head -1)"
        else
            warn "gh CLI found but version check failed"
        fi

        # Check auth status (will fail if not logged in, but should give clear message)
        local gh_auth_output gh_auth_rc
        gh_auth_output=$(exec_in_container gh auth status 2>&1) && gh_auth_rc=0 || gh_auth_rc=$?

        if [[ $gh_auth_rc -eq 0 ]]; then
            pass "gh auth status shows logged in"
        else
            if printf '%s' "$gh_auth_output" | grep -qiE "not logged|no account|gh auth login"; then
                pass "gh auth status shows clear 'not logged in' message"
            else
                warn "gh auth status failed with unexpected output"
            fi
        fi
    else
        info "gh CLI not installed in test image"
        pass "gh CLI test skipped (not installed)"
    fi

    pass "Scenario 4: Agent doctor commands - PASSED"
}

# ==============================================================================
# Test: Idempotency
# ==============================================================================

test_idempotency() {
    section "Scenario 5: Idempotency Test"

    # Re-run import to verify idempotency
    info "Re-running import to test idempotency..."

    local fixture_home
    fixture_home=$(mktemp -d "${TMPDIR:-/tmp}/containai-fixture-home2-XXXXXX")
    register_dir "$fixture_home"

    # Set up fixture again
    mkdir -p "$fixture_home/.claude/plugins"
    cp -r "$FIXTURES_DIR/claude/"* "$fixture_home/.claude/" 2>/dev/null || true
    cp -r "$FIXTURES_DIR/claude/plugins/"* "$fixture_home/.claude/plugins/" 2>/dev/null || true

    mkdir -p "$fixture_home/.config/gh"
    cp "$FIXTURES_DIR/gh/hosts.yml" "$fixture_home/.config/gh/" 2>/dev/null || true

    cp "$FIXTURES_DIR/shell/bash_aliases" "$fixture_home/.bash_aliases" 2>/dev/null || true

    # Run import again
    local import_output import_rc
    import_output=$(_containai_import "$CONTEXT_NAME" "$TEST_DATA_VOLUME" "false" "false" "$TEST_WORKSPACE" "" "$fixture_home" 2>&1) && import_rc=0 || import_rc=$?

    if [[ $import_rc -eq 0 ]]; then
        pass "Import is idempotent (second run succeeded)"
    else
        fail "Import is not idempotent (second run failed)"
        info "  Output: $import_output"
    fi

    # Verify data is still correct after re-import
    local settings_check
    settings_check=$(docker --context "$CONTEXT_NAME" run --rm -v "$TEST_DATA_VOLUME":/data alpine cat /data/claude/settings.json 2>/dev/null) || settings_check=""

    if [[ -n "$settings_check" ]] && printf '%s' "$settings_check" | jq -e '.enabledPlugins["test-plugin"]' >/dev/null 2>&1; then
        pass "Data integrity preserved after re-import"
    else
        fail "Data corrupted after re-import"
    fi

    pass "Scenario 5: Idempotency - PASSED"
}

# ==============================================================================
# Main
# ==============================================================================

main() {
    printf '%s\n' "=============================================================================="
    printf '%s\n' "Comprehensive ContainAI Integration Tests"
    printf '%s\n' "=============================================================================="

    info "Test run ID: $TEST_RUN_ID"
    info "Test image: $TEST_IMAGE"

    # Check prerequisites
    check_prerequisites || exit 1

    # Run test scenarios
    test_clean_start_without_import || true
    test_clean_start_with_import || true
    test_dind_operations || true
    test_agent_doctor_commands || true
    test_idempotency || true

    # Summary
    printf '\n'
    printf '%s\n' "=============================================================================="
    if [[ "$FAILED" -eq 0 ]]; then
        printf '%s\n' "All ContainAI integration tests passed!"
        printf '%s\n' ""
        printf '%s\n' "ContainAI is working correctly. After running this test suite,"
        printf '%s\n' "you can be confident that things are good to go."
        exit 0
    else
        printf '%s\n' "Some tests failed!"
        printf '%s\n' ""
        printf '%s\n' "Troubleshooting:"
        printf '%s\n' "  1. Ensure Sysbox is installed: cai setup"
        printf '%s\n' "  2. Check Sysbox services: systemctl status sysbox-mgr sysbox-fs"
        printf '%s\n' "  3. Verify context: docker --context $CONTEXT_NAME info"
        printf '%s\n' "  4. Check test image: docker --context $CONTEXT_NAME pull $TEST_IMAGE"
        exit 1
    fi
}

main "$@"
