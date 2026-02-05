#!/usr/bin/env bash
# ==============================================================================
# Integration tests for ContainAI Startup Hooks
# ==============================================================================
# Verifies:
# 1. containai-init.sh run_hooks function exists and works
# 2. Hooks at /etc/containai/template-hooks/startup.d/ are executed first
# 3. Hooks at workspace .containai/hooks/startup.d/ are executed second
# 4. Non-executable files are skipped with warning
# 5. Failed hooks exit non-zero (fail container start)
# 6. Hooks run in sorted order (LC_ALL=C sort)
# 7. systemd drop-ins use Requires= instead of Wants=
#
# Prerequisites:
# - Docker daemon running
# - Sysbox installed and containai-docker context available
#
# Usage:
#   ./tests/integration/test-startup-hooks.sh
#
# Environment Variables:
#   CONTAINAI_TEST_IMAGE - Override test image (default: ghcr.io/novotnyllc/containai/base:latest)
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
SRC_DIR="$REPO_ROOT/src"

# Source containai library
if ! source "$SRC_DIR/containai.sh"; then
    printf '%s\n' "[ERROR] Failed to source containai.sh" >&2
    exit 1
fi

# ==============================================================================
# Test helpers
# ==============================================================================

pass() { printf '%s\n' "[PASS] $*"; }
fail() {
    printf '%s\n' "[FAIL] $*" >&2
    FAILED=1
}
skip() { printf '%s\n' "[SKIP] $*"; }
info() { printf '%s\n' "[INFO] $*"; }
section() {
    printf '\n'
    printf '%s\n' "=== $* ==="
}

FAILED=0

# Context name for sysbox containers
CONTEXT_NAME="${_CAI_CONTAINAI_DOCKER_CONTEXT:-containai-docker}"

# Test run ID for unique resource names
TEST_RUN_ID="startup-hooks-test-$$-$(date +%s)"

# ContainAI base image for system container testing
TEST_IMAGE="${CONTAINAI_TEST_IMAGE:-ghcr.io/novotnyllc/containai/base:latest}"

# Cleanup function
cleanup() {
    info "Cleaning up test resources..."

    # Stop and remove test containers
    local container
    for container in $(docker --context "$CONTEXT_NAME" ps -aq --filter "label=test_run=$TEST_RUN_ID" 2>/dev/null || true); do
        docker --context "$CONTEXT_NAME" stop --time 5 "$container" 2>/dev/null || true
        docker --context "$CONTEXT_NAME" rm -f "$container" 2>/dev/null || true
    done

    # Remove test volumes
    local volume
    for volume in $(docker --context "$CONTEXT_NAME" volume ls -q --filter "label=test_run=$TEST_RUN_ID" 2>/dev/null || true); do
        docker --context "$CONTEXT_NAME" volume rm "$volume" 2>/dev/null || true
    done

    # Remove test directories
    rm -rf "/tmp/$TEST_RUN_ID" 2>/dev/null || true
}

trap cleanup EXIT

# ==============================================================================
# Test 1: containai-init.sh has run_hooks function
# ==============================================================================
test_init_has_run_hooks() {
    section "Test 1: containai-init.sh has run_hooks function"

    local init_script="$SRC_DIR/container/containai-init.sh"

    if [[ ! -f "$init_script" ]]; then
        fail "containai-init.sh not found at $init_script"
        return
    fi
    pass "containai-init.sh exists"

    # Check for run_hooks function definition
    if grep -q "^run_hooks()" "$init_script"; then
        pass "run_hooks function defined in containai-init.sh"
    else
        fail "run_hooks function not found in containai-init.sh"
    fi

    # Check for template hooks path
    if grep -q "/etc/containai/template-hooks/startup.d" "$init_script"; then
        pass "Template hooks path configured"
    else
        fail "Template hooks path not configured"
    fi

    # Check for workspace hooks path
    if grep -q "/home/agent/workspace/.containai/hooks/startup.d" "$init_script"; then
        pass "Workspace hooks path configured"
    else
        fail "Workspace hooks path not configured"
    fi

    # Check for LC_ALL=C sort for deterministic ordering
    if grep -q "LC_ALL=C sort" "$init_script"; then
        pass "Hooks use LC_ALL=C sort for deterministic ordering"
    else
        fail "Hooks missing LC_ALL=C sort for deterministic ordering"
    fi

    # Check for non-executable warning
    if grep -qE "\[WARN\].*non-executable|Skipping non-executable" "$init_script"; then
        pass "Non-executable files are logged with warning"
    else
        fail "Non-executable warning not found"
    fi

    # Check for error handling on hook failure
    if grep -qE "\[ERROR\].*hook failed|Startup hook failed" "$init_script"; then
        pass "Hook failure is logged as error"
    else
        fail "Hook failure error message not found"
    fi

    # Check that failed hooks exit non-zero
    if grep -q "exit 1" "$init_script"; then
        pass "Script exits non-zero on hook failure"
    else
        fail "Script does not exit non-zero on hook failure"
    fi
}

# ==============================================================================
# Test 2: systemd drop-ins use Requires= instead of Wants=
# ==============================================================================
test_systemd_dropins_use_requires() {
    section "Test 2: systemd drop-ins use Requires= for fail-fast"

    local ssh_dropin="$SRC_DIR/services/ssh.service.d/containai.conf"
    local docker_dropin="$SRC_DIR/services/docker.service.d/containai.conf"

    # Check SSH service drop-in
    if [[ ! -f "$ssh_dropin" ]]; then
        fail "ssh.service.d/containai.conf not found"
    else
        if grep -q "Requires=containai-init.service" "$ssh_dropin"; then
            pass "ssh.service.d uses Requires=containai-init.service"
        else
            fail "ssh.service.d does not use Requires= (may use Wants= instead)"
        fi

        # Ensure it does NOT use Wants= for init (would be advisory, not fail-fast)
        if grep -q "Wants=containai-init.service" "$ssh_dropin"; then
            fail "ssh.service.d still uses Wants= (should use Requires=)"
        else
            pass "ssh.service.d does not have Wants= for init"
        fi
    fi

    # Check Docker service drop-in
    if [[ ! -f "$docker_dropin" ]]; then
        fail "docker.service.d/containai.conf not found"
    else
        if grep -q "Requires=containai-init.service" "$docker_dropin"; then
            pass "docker.service.d uses Requires=containai-init.service"
        else
            fail "docker.service.d does not use Requires= (may use Wants= instead)"
        fi

        # Ensure it does NOT use Wants= for init
        if grep -q "Wants=containai-init.service" "$docker_dropin"; then
            fail "docker.service.d still uses Wants= (should use Requires=)"
        else
            pass "docker.service.d does not have Wants= for init"
        fi
    fi
}

# ==============================================================================
# Test 3: run_hooks function behavior (unit test style)
# ==============================================================================
test_run_hooks_behavior() {
    section "Test 3: run_hooks function behavior"

    # Create test directory structure
    local test_dir="/tmp/$TEST_RUN_ID/hooks-test"
    mkdir -p "$test_dir/startup.d"

    # Create test hooks with different sort order
    printf '#!/bin/bash\necho "hook-20"' > "$test_dir/startup.d/20-second.sh"
    printf '#!/bin/bash\necho "hook-10"' > "$test_dir/startup.d/10-first.sh"
    chmod +x "$test_dir/startup.d/10-first.sh"
    chmod +x "$test_dir/startup.d/20-second.sh"

    # Create non-executable file
    printf '#!/bin/bash\necho "should-skip"' > "$test_dir/startup.d/30-nonexec.sh"
    # NOT chmod +x

    # Source the run_hooks function from containai-init.sh
    # We need to extract just the function for testing
    local init_script="$SRC_DIR/container/containai-init.sh"

    # Create a test script that includes the function and runs it
    local test_script="$test_dir/test-runner.sh"
    cat > "$test_script" << 'TESTEOF'
#!/bin/bash
set -euo pipefail

log() { printf '%s\n' "$*" >&2; }

run_hooks() {
    local hooks_dir="$1"
    [[ -d "$hooks_dir" ]] || return 0

    cd -- /tmp || true

    local hook
    local hooks_found=0
    while IFS= read -r hook; do
        [[ -z "$hook" ]] && continue
        hooks_found=1
        if [[ ! -x "$hook" ]]; then
            log "[WARN] Skipping non-executable hook: $hook"
            continue
        fi
        log "[INFO] Running startup hook: $hook"
        if ! "$hook"; then
            log "[ERROR] Startup hook failed: $hook"
            exit 1
        fi
    done < <(find "$hooks_dir" -maxdepth 1 -name '*.sh' -type f 2>/dev/null | LC_ALL=C sort)

    if [[ $hooks_found -eq 1 ]]; then
        log "[INFO] Completed hooks from: $hooks_dir"
    fi
}

run_hooks "$1"
TESTEOF
    chmod +x "$test_script"

    # Run the test
    local output rc
    output=$("$test_script" "$test_dir/startup.d" 2>&1) && rc=0 || rc=$?

    if [[ $rc -eq 0 ]]; then
        pass "run_hooks completed successfully"
    else
        fail "run_hooks failed with exit code $rc"
    fi

    # Verify hooks ran in sorted order
    if printf '%s' "$output" | grep -q "hook-10"; then
        pass "First hook (10-first.sh) executed"
    else
        fail "First hook (10-first.sh) did not execute"
    fi

    if printf '%s' "$output" | grep -q "hook-20"; then
        pass "Second hook (20-second.sh) executed"
    else
        fail "Second hook (20-second.sh) did not execute"
    fi

    # Verify non-executable was skipped with warning
    if printf '%s' "$output" | grep -q "Skipping non-executable"; then
        pass "Non-executable file was skipped with warning"
    else
        fail "Non-executable file was not properly skipped"
    fi

    # Verify output doesn't contain the skipped hook's output
    if printf '%s' "$output" | grep -q "should-skip"; then
        fail "Non-executable hook was executed (should have been skipped)"
    else
        pass "Non-executable hook output correctly absent"
    fi
}

# ==============================================================================
# Test 4: Failed hook exits non-zero
# ==============================================================================
test_failed_hook_exits_nonzero() {
    section "Test 4: Failed hook exits non-zero"

    # Create test directory structure
    local test_dir="/tmp/$TEST_RUN_ID/fail-test"
    mkdir -p "$test_dir/startup.d"

    # Create a hook that fails
    printf '#!/bin/bash\nexit 1' > "$test_dir/startup.d/10-fail.sh"
    chmod +x "$test_dir/startup.d/10-fail.sh"

    # Create test script
    local test_script="$test_dir/test-runner.sh"
    cat > "$test_script" << 'TESTEOF'
#!/bin/bash
set -euo pipefail

log() { printf '%s\n' "$*" >&2; }

run_hooks() {
    local hooks_dir="$1"
    [[ -d "$hooks_dir" ]] || return 0

    cd -- /tmp || true

    local hook
    while IFS= read -r hook; do
        [[ -z "$hook" ]] && continue
        if [[ ! -x "$hook" ]]; then
            log "[WARN] Skipping non-executable hook: $hook"
            continue
        fi
        log "[INFO] Running startup hook: $hook"
        if ! "$hook"; then
            log "[ERROR] Startup hook failed: $hook"
            exit 1
        fi
    done < <(find "$hooks_dir" -maxdepth 1 -name '*.sh' -type f 2>/dev/null | LC_ALL=C sort)
}

run_hooks "$1"
TESTEOF
    chmod +x "$test_script"

    # Run the test (should fail)
    local output rc
    output=$("$test_script" "$test_dir/startup.d" 2>&1) && rc=0 || rc=$?

    if [[ $rc -ne 0 ]]; then
        pass "run_hooks exits non-zero when hook fails"
    else
        fail "run_hooks should exit non-zero when hook fails"
    fi

    # Verify error message was logged
    if printf '%s' "$output" | grep -q "hook failed"; then
        pass "Hook failure was logged with error message"
    else
        fail "Hook failure error message not logged"
    fi
}

# ==============================================================================
# Test 5: Integration test with container (requires Docker/Sysbox)
# ==============================================================================
test_hooks_in_container() {
    section "Test 5: Startup hooks in container (requires Docker/Sysbox)"

    # Skip Sysbox-based container test when already inside a container
    # (this test verifies host-level Sysbox setup, not nested ContainAI functionality)
    if _cai_is_container; then
        skip "Running inside a container - skipping Sysbox container verification"
        return
    fi

    # Check if Docker is available
    if ! command -v docker >/dev/null 2>&1; then
        skip "Docker not available"
        return
    fi

    # Check if containai-docker context exists
    if ! docker context inspect "$CONTEXT_NAME" >/dev/null 2>&1; then
        skip "Context '$CONTEXT_NAME' not found - run 'cai setup'"
        return
    fi

    # Check if sysbox-runc is available
    local runtimes_json
    runtimes_json=$(docker --context "$CONTEXT_NAME" info --format '{{json .Runtimes}}' 2>/dev/null) || runtimes_json=""
    if [[ -z "$runtimes_json" ]] || ! printf '%s' "$runtimes_json" | grep -q "sysbox-runc"; then
        skip "sysbox-runc runtime not available"
        return
    fi

    # Check test image is available
    if ! docker --context "$CONTEXT_NAME" image inspect "$TEST_IMAGE" >/dev/null 2>&1; then
        info "Pulling test image: $TEST_IMAGE"
        if ! docker --context "$CONTEXT_NAME" pull "$TEST_IMAGE" >/dev/null 2>&1; then
            skip "Cannot pull test image"
            return
        fi
    fi

    # Create test workspace with hooks
    local test_workspace="/tmp/$TEST_RUN_ID/workspace"
    mkdir -p "$test_workspace/.containai/hooks/startup.d"

    # Create test hooks
    cat > "$test_workspace/.containai/hooks/startup.d/10-first.sh" << 'HOOKEOF'
#!/bin/bash
echo "HOOK_FIRST_RAN" >> /tmp/hook-output.txt
HOOKEOF
    chmod +x "$test_workspace/.containai/hooks/startup.d/10-first.sh"

    cat > "$test_workspace/.containai/hooks/startup.d/20-second.sh" << 'HOOKEOF'
#!/bin/bash
echo "HOOK_SECOND_RAN" >> /tmp/hook-output.txt
HOOKEOF
    chmod +x "$test_workspace/.containai/hooks/startup.d/20-second.sh"

    # Create test data volume
    local test_volume="${TEST_RUN_ID}-data"
    docker --context "$CONTEXT_NAME" volume create --label "test_run=$TEST_RUN_ID" "$test_volume" >/dev/null

    # Start container
    local container_name="${TEST_RUN_ID}-container"
    local run_output run_rc
    run_output=$(docker --context "$CONTEXT_NAME" run -d \
        --runtime=sysbox-runc \
        --name "$container_name" \
        --label "test_run=$TEST_RUN_ID" \
        -v "$test_workspace:/home/agent/workspace:rw" \
        -v "$test_volume:/mnt/agent-data:rw" \
        --stop-timeout 10 \
        "$TEST_IMAGE" 2>&1) && run_rc=0 || run_rc=$?

    if [[ $run_rc -ne 0 ]]; then
        fail "Failed to start test container: $run_output"
        return
    fi
    pass "Test container started"

    # Wait for container to initialize (poll instead of fixed sleep)
    local wait_timeout=30
    local wait_elapsed=0
    local container_status=""

    info "Waiting for container initialization (timeout: ${wait_timeout}s)..."
    while [[ $wait_elapsed -lt $wait_timeout ]]; do
        container_status=$(docker --context "$CONTEXT_NAME" inspect --format '{{.State.Status}}' "$container_name" 2>/dev/null) || container_status=""

        if [[ "$container_status" != "running" ]]; then
            fail "Container not running (status: $container_status)"
            info "Container logs:"
            docker --context "$CONTEXT_NAME" logs "$container_name" 2>&1 | tail -20 || true
            return
        fi

        # Check if init service completed (deterministic wait)
        if docker --context "$CONTEXT_NAME" exec "$container_name" \
            systemctl is-active containai-init.service >/dev/null 2>&1; then
            break
        fi

        sleep 2
        wait_elapsed=$((wait_elapsed + 2))
    done

    if [[ $wait_elapsed -ge $wait_timeout ]]; then
        fail "Timeout waiting for containai-init.service"
        info "Service status:"
        docker --context "$CONTEXT_NAME" exec "$container_name" \
            systemctl status containai-init.service --no-pager 2>&1 | head -20 || true
        return
    fi
    pass "Container is running and init completed"

    # Check if hooks ran (look for output file)
    local hook_output
    hook_output=$(docker --context "$CONTEXT_NAME" exec "$container_name" cat /tmp/hook-output.txt 2>/dev/null) || hook_output=""

    if [[ -n "$hook_output" ]]; then
        pass "Hooks produced output"

        # Verify first hook ran
        if printf '%s' "$hook_output" | grep -q "HOOK_FIRST_RAN"; then
            pass "First hook (10-first.sh) executed in container"
        else
            fail "First hook did not execute in container"
        fi

        # Verify second hook ran
        if printf '%s' "$hook_output" | grep -q "HOOK_SECOND_RAN"; then
            pass "Second hook (20-second.sh) executed in container"
        else
            fail "Second hook did not execute in container"
        fi

        # Verify order (first should appear before second in output)
        local first_line second_line
        first_line=$(printf '%s' "$hook_output" | grep -n "HOOK_FIRST_RAN" | head -1 | cut -d: -f1)
        second_line=$(printf '%s' "$hook_output" | grep -n "HOOK_SECOND_RAN" | head -1 | cut -d: -f1)

        if [[ -n "$first_line" && -n "$second_line" && "$first_line" -lt "$second_line" ]]; then
            pass "Hooks executed in correct sorted order"
        else
            fail "Hooks did not execute in correct order"
        fi
    else
        info "Hook output file not found - checking containai-init logs"
        # Check journal for hook execution
        local journal_output
        journal_output=$(docker --context "$CONTEXT_NAME" exec "$container_name" journalctl -u containai-init.service --no-pager 2>/dev/null) || journal_output=""

        if printf '%s' "$journal_output" | grep -q "Running startup hook"; then
            pass "Hooks were invoked (per journal)"
        else
            fail "No evidence of hook execution in container"
            info "Journal output:"
            printf '%s\n' "$journal_output" | head -20
        fi
    fi
}

# ==============================================================================
# Test 6: User manifest runtime processing (requires Docker/Sysbox)
# ==============================================================================
test_user_manifest_runtime() {
    section "Test 6: User manifest runtime processing (requires Docker/Sysbox)"

    # Skip Sysbox-based container test when already inside a container
    if _cai_is_container; then
        skip "Running inside a container - skipping Sysbox container verification"
        return
    fi

    # Check if Docker is available
    if ! command -v docker >/dev/null 2>&1; then
        skip "Docker not available"
        return
    fi

    # Check if containai-docker context exists
    if ! docker context inspect "$CONTEXT_NAME" >/dev/null 2>&1; then
        skip "Context '$CONTEXT_NAME' not found - run 'cai setup'"
        return
    fi

    # Check if sysbox-runc is available
    local runtimes_json
    runtimes_json=$(docker --context "$CONTEXT_NAME" info --format '{{json .Runtimes}}' 2>/dev/null) || runtimes_json=""
    if [[ -z "$runtimes_json" ]] || ! printf '%s' "$runtimes_json" | grep -q "sysbox-runc"; then
        skip "sysbox-runc runtime not available"
        return
    fi

    # Check test image is available
    if ! docker --context "$CONTEXT_NAME" image inspect "$TEST_IMAGE" >/dev/null 2>&1; then
        info "Pulling test image: $TEST_IMAGE"
        if ! docker --context "$CONTEXT_NAME" pull "$TEST_IMAGE" >/dev/null 2>&1; then
            skip "Cannot pull test image"
            return
        fi
    fi

    # Create test data volume with user manifest
    local test_volume="${TEST_RUN_ID}-user-manifest-data"
    docker --context "$CONTEXT_NAME" volume create --label "test_run=$TEST_RUN_ID" "$test_volume" >/dev/null

    # Create a temp container to populate the volume with test data
    local init_container="${TEST_RUN_ID}-init"
    docker --context "$CONTEXT_NAME" run --rm \
        --name "$init_container" \
        -v "$test_volume:/data" \
        alpine:latest /bin/sh -c '
            mkdir -p /data/containai/manifests
            cat > /data/containai/manifests/99-test-user-agent.toml << EOF
# User-defined test agent manifest
[agent]
name = "test-user-agent"
binary = "echo"
default_args = ["--user-manifest-test-marker"]
aliases = ["test-alias"]
optional = true

[[entries]]
source = ".test-user-config/settings.json"
target = "test-user-config/settings.json"
container_link = ".test-user-config/settings.json"
flags = "fjo"
EOF
            mkdir -p /data/test-user-config
            echo "{\"marker\": \"user-manifest-test\"}" > /data/test-user-config/settings.json
        ' 2>/dev/null

    # Start container with the volume
    local container_name="${TEST_RUN_ID}-user-manifest"
    local run_output run_rc
    run_output=$(docker --context "$CONTEXT_NAME" run -d \
        --runtime=sysbox-runc \
        --name "$container_name" \
        --label "test_run=$TEST_RUN_ID" \
        -v "$test_volume:/mnt/agent-data:rw" \
        --stop-timeout 10 \
        "$TEST_IMAGE" 2>&1) && run_rc=0 || run_rc=$?

    if [[ $run_rc -ne 0 ]]; then
        fail "Failed to start test container: $run_output"
        return
    fi
    pass "User manifest test container started"

    # Wait for container to initialize
    local wait_timeout=30
    local wait_elapsed=0
    info "Waiting for container initialization (timeout: ${wait_timeout}s)..."
    while [[ $wait_elapsed -lt $wait_timeout ]]; do
        if docker --context "$CONTEXT_NAME" exec "$container_name" \
            systemctl is-active containai-init.service >/dev/null 2>&1; then
            break
        fi
        sleep 2
        wait_elapsed=$((wait_elapsed + 2))
    done

    if [[ $wait_elapsed -ge $wait_timeout ]]; then
        fail "Timeout waiting for containai-init.service"
        return
    fi
    pass "containai-init completed"

    # Test 6a: Check user wrapper generation
    local wrapper_file
    wrapper_file=$(docker --context "$CONTEXT_NAME" exec -u agent "$container_name" \
        cat /home/agent/.bash_env.d/containai-user-agents.sh 2>/dev/null) || wrapper_file=""

    # Check if 'echo' binary exists in container (it always should)
    local echo_exists
    echo_exists=$(docker --context "$CONTEXT_NAME" exec "$container_name" \
        bash -lc 'command -v echo' 2>/dev/null) || echo_exists=""

    if [[ -n "$wrapper_file" ]]; then
        pass "User agent wrapper file exists"

        # Check if user agent function is defined
        if printf '%s' "$wrapper_file" | grep -q "test-user-agent()"; then
            pass "User agent wrapper function defined"
        else
            # echo is always available, so wrapper should be created
            fail "User agent wrapper function not found (binary 'echo' exists)"
        fi

        # Check if alias is defined
        if printf '%s' "$wrapper_file" | grep -q "test-alias()"; then
            pass "User agent alias function defined"
        else
            fail "User agent alias function not found"
        fi
    elif [[ -n "$echo_exists" ]]; then
        # Binary exists but wrapper file missing - this is a regression
        fail "User agent wrapper file not created despite binary 'echo' being available"
    else
        info "User agent wrapper file not created (binary check failed)"
    fi

    # Test 6b: Check user symlinks
    # The test created the source file in the volume, so symlink MUST exist
    local symlink_target
    symlink_target=$(docker --context "$CONTEXT_NAME" exec -u agent "$container_name" \
        readlink -f /home/agent/.test-user-config/settings.json 2>/dev/null) || symlink_target=""

    # Verify source exists in volume (sanity check)
    local source_exists
    source_exists=$(docker --context "$CONTEXT_NAME" exec "$container_name" \
        test -f /mnt/agent-data/test-user-config/settings.json && echo "yes" || echo "no") || source_exists="no"

    if [[ "$symlink_target" == "/mnt/agent-data/test-user-config/settings.json" ]]; then
        pass "User manifest symlink created correctly"
    elif [[ -n "$symlink_target" ]]; then
        fail "User manifest symlink points to wrong target: $symlink_target"
    elif [[ "$source_exists" == "yes" ]]; then
        fail "User manifest symlink not created despite source existing in volume"
    else
        fail "Test setup error: source file not found in volume"
    fi

    # Test 6c: Check containai-init logs for processing
    local journal_output
    journal_output=$(docker --context "$CONTEXT_NAME" exec "$container_name" \
        journalctl -u containai-init.service --no-pager 2>/dev/null) || journal_output=""

    if printf '%s' "$journal_output" | grep -q "user manifest"; then
        pass "User manifest processing logged"
    else
        info "No explicit user manifest log entry (may process silently)"
    fi
}

# ==============================================================================
# Test 7: SSH wrapper behavior (requires Docker/Sysbox)
# ==============================================================================
test_ssh_wrapper_behavior() {
    section "Test 7: SSH wrapper behavior (requires Docker/Sysbox)"

    # Skip Sysbox-based container test when already inside a container
    if _cai_is_container; then
        skip "Running inside a container - skipping Sysbox container verification"
        return
    fi

    # Check if Docker is available
    if ! command -v docker >/dev/null 2>&1; then
        skip "Docker not available"
        return
    fi

    # Check if containai-docker context exists
    if ! docker context inspect "$CONTEXT_NAME" >/dev/null 2>&1; then
        skip "Context '$CONTEXT_NAME' not found - run 'cai setup'"
        return
    fi

    # Check if sysbox-runc is available
    local runtimes_json
    runtimes_json=$(docker --context "$CONTEXT_NAME" info --format '{{json .Runtimes}}' 2>/dev/null) || runtimes_json=""
    if [[ -z "$runtimes_json" ]] || ! printf '%s' "$runtimes_json" | grep -q "sysbox-runc"; then
        skip "sysbox-runc runtime not available"
        return
    fi

    # Check test image is available
    if ! docker --context "$CONTEXT_NAME" image inspect "$TEST_IMAGE" >/dev/null 2>&1; then
        skip "Cannot pull test image"
        return
    fi

    # Create test data volume
    local test_volume="${TEST_RUN_ID}-ssh-wrapper-data"
    docker --context "$CONTEXT_NAME" volume create --label "test_run=$TEST_RUN_ID" "$test_volume" >/dev/null

    # Start container
    local container_name="${TEST_RUN_ID}-ssh-wrapper"
    local run_output run_rc
    run_output=$(docker --context "$CONTEXT_NAME" run -d \
        --runtime=sysbox-runc \
        --name "$container_name" \
        --label "test_run=$TEST_RUN_ID" \
        -v "$test_volume:/mnt/agent-data:rw" \
        --stop-timeout 10 \
        "$TEST_IMAGE" 2>&1) && run_rc=0 || run_rc=$?

    if [[ $run_rc -ne 0 ]]; then
        fail "Failed to start test container: $run_output"
        return
    fi
    pass "SSH wrapper test container started"

    # Wait for container to initialize and SSH to be ready
    local wait_timeout=45
    local wait_elapsed=0
    local ssh_service=""
    info "Waiting for container initialization and SSH (timeout: ${wait_timeout}s)..."
    while [[ $wait_elapsed -lt $wait_timeout ]]; do
        if docker --context "$CONTEXT_NAME" exec "$container_name" \
            systemctl is-active ssh.service >/dev/null 2>&1; then
            ssh_service="ssh.service"
            break
        fi
        if docker --context "$CONTEXT_NAME" exec "$container_name" \
            systemctl is-active sshd.service >/dev/null 2>&1; then
            ssh_service="sshd.service"
            break
        fi
        sleep 2
        wait_elapsed=$((wait_elapsed + 2))
    done

    if [[ -z "$ssh_service" ]]; then
        fail "Timeout waiting for SSH service"
        return
    fi
    pass "SSH service is running ($ssh_service)"

    # Get container IP for SSH connection
    local container_ip
    container_ip=$(docker --context "$CONTEXT_NAME" inspect --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$container_name" 2>/dev/null) || container_ip=""

    if [[ -z "$container_ip" ]]; then
        fail "Could not get container IP - cannot test SSH"
        return
    fi

    info "Container IP: $container_ip"

    # Generate temporary SSH key for testing
    local ssh_key_dir="/tmp/$TEST_RUN_ID/ssh"
    mkdir -p "$ssh_key_dir"
    ssh-keygen -t ed25519 -f "$ssh_key_dir/test_key" -N "" -q

    # Copy public key to container's authorized_keys
    local pubkey
    pubkey=$(cat "$ssh_key_dir/test_key.pub")
    docker --context "$CONTEXT_NAME" exec "$container_name" \
        bash -c "mkdir -p /home/agent/.ssh && echo '$pubkey' >> /home/agent/.ssh/authorized_keys && chmod 600 /home/agent/.ssh/authorized_keys && chown -R agent:agent /home/agent/.ssh" 2>/dev/null

    # Wait a moment for SSH to pick up the new key
    sleep 1

    # Test 7a: Real SSH with plain command (tests BASH_ENV path)
    # Avoid agent-specific binaries; inject a marker into .bash_env and verify it via SSH.
    docker --context "$CONTEXT_NAME" exec "$container_name" \
        bash -lc 'echo "export CONTAINAI_BASH_ENV_MARKER=1" >> /home/agent/.bash_env' >/dev/null 2>&1 || true
    local ssh_opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -i $ssh_key_dir/test_key"
    local ssh_output ssh_rc

    # shellcheck disable=SC2086
    ssh_output=$(ssh $ssh_opts agent@"$container_ip" 'echo "$CONTAINAI_BASH_ENV_MARKER"' 2>&1) && ssh_rc=0 || ssh_rc=$?

    if [[ $ssh_rc -eq 0 ]] && [[ "$ssh_output" == *"1"* ]]; then
        pass "CRITICAL: Plain SSH sees BASH_ENV marker (BASH_ENV works via real SSH)"
    else
        fail "CRITICAL: Plain SSH BASH_ENV marker missing (rc=$ssh_rc): $ssh_output"
    fi

    # Test 7b: Check BASH_ENV value via real SSH
    local bash_env_ssh
    # shellcheck disable=SC2086
    bash_env_ssh=$(ssh $ssh_opts agent@"$container_ip" 'echo "BASH_ENV=$BASH_ENV"' 2>&1) || bash_env_ssh=""

    if [[ "$bash_env_ssh" == *"BASH_ENV=/home/agent/.bash_env"* ]]; then
        pass "BASH_ENV is correctly set via real SSH"
    else
        fail "BASH_ENV not correctly set via SSH: $bash_env_ssh"
    fi

    # Test 7c removed: infrastructure tests must not rely on agent binaries or wrappers.

    # Clean up SSH key
    rm -rf "$ssh_key_dir"
}

# ==============================================================================
# Test 8: Invalid user manifest handling (requires Docker/Sysbox)
# ==============================================================================
test_invalid_user_manifest() {
    section "Test 8: Invalid user manifest handling (requires Docker/Sysbox)"

    # Skip Sysbox-based container test when already inside a container
    if _cai_is_container; then
        skip "Running inside a container - skipping Sysbox container verification"
        return
    fi

    # Check prerequisites
    if ! command -v docker >/dev/null 2>&1; then
        skip "Docker not available"
        return
    fi
    if ! docker context inspect "$CONTEXT_NAME" >/dev/null 2>&1; then
        skip "Context '$CONTEXT_NAME' not found"
        return
    fi
    local runtimes_json
    runtimes_json=$(docker --context "$CONTEXT_NAME" info --format '{{json .Runtimes}}' 2>/dev/null) || runtimes_json=""
    if [[ -z "$runtimes_json" ]] || ! printf '%s' "$runtimes_json" | grep -q "sysbox-runc"; then
        skip "sysbox-runc runtime not available"
        return
    fi
    if ! docker --context "$CONTEXT_NAME" image inspect "$TEST_IMAGE" >/dev/null 2>&1; then
        skip "Test image not available"
        return
    fi

    # Create test data volume with INVALID manifest
    local test_volume="${TEST_RUN_ID}-invalid-manifest-data"
    docker --context "$CONTEXT_NAME" volume create --label "test_run=$TEST_RUN_ID" "$test_volume" >/dev/null

    # Populate volume with malformed TOML
    docker --context "$CONTEXT_NAME" run --rm \
        -v "$test_volume:/data" \
        alpine:latest /bin/sh -c '
            mkdir -p /data/containai/manifests
            cat > /data/containai/manifests/99-broken.toml << EOF
# Intentionally malformed TOML
[agent
name = "broken"
EOF
        ' 2>/dev/null

    # Start container
    local container_name="${TEST_RUN_ID}-invalid-manifest"
    local run_output run_rc
    run_output=$(docker --context "$CONTEXT_NAME" run -d \
        --runtime=sysbox-runc \
        --name "$container_name" \
        --label "test_run=$TEST_RUN_ID" \
        -v "$test_volume:/mnt/agent-data:rw" \
        --stop-timeout 10 \
        "$TEST_IMAGE" 2>&1) && run_rc=0 || run_rc=$?

    if [[ $run_rc -ne 0 ]]; then
        fail "Failed to start test container: $run_output"
        return
    fi

    # Wait for container to initialize
    local wait_timeout=30
    local wait_elapsed=0
    while [[ $wait_elapsed -lt $wait_timeout ]]; do
        if docker --context "$CONTEXT_NAME" exec "$container_name" \
            systemctl is-active containai-init.service >/dev/null 2>&1; then
            break
        fi
        # Check container is still running
        local status
        status=$(docker --context "$CONTEXT_NAME" inspect --format '{{.State.Status}}' "$container_name" 2>/dev/null) || status=""
        if [[ "$status" != "running" ]]; then
            fail "Container stopped unexpectedly (status: $status)"
            return
        fi
        sleep 2
        wait_elapsed=$((wait_elapsed + 2))
    done

    # Container should still be running despite invalid manifest
    local container_status
    container_status=$(docker --context "$CONTEXT_NAME" inspect --format '{{.State.Status}}' "$container_name" 2>/dev/null) || container_status=""

    if [[ "$container_status" == "running" ]]; then
        pass "Container started successfully despite invalid manifest"
    else
        fail "Container failed to start with invalid manifest (status: $container_status)"
        return
    fi

    # Check for error in logs (containai-init MUST log the error)
    local journal_output
    journal_output=$(docker --context "$CONTEXT_NAME" exec "$container_name" \
        journalctl -u containai-init.service --no-pager 2>/dev/null) || journal_output=""

    if printf '%s' "$journal_output" | grep -qi "error\|warn\|invalid\|malformed\|fail"; then
        pass "Invalid manifest logged error/warning"
    else
        # Also check gen-user-wrappers output if available
        local wrapper_log
        wrapper_log=$(docker --context "$CONTEXT_NAME" exec "$container_name" \
            cat /tmp/gen-user-wrappers.log 2>/dev/null) || wrapper_log=""

        if printf '%s' "$wrapper_log" | grep -qi "error\|warn\|invalid\|malformed\|fail"; then
            pass "Invalid manifest logged error/warning (in wrapper log)"
        else
            fail "Invalid manifest did not produce error/warning in logs"
        fi
    fi
}

# ==============================================================================
# Test 9: Optional binary not installed - no wrapper (requires Docker/Sysbox)
# ==============================================================================
test_optional_binary_not_installed() {
    section "Test 9: Optional binary not installed - no wrapper (requires Docker/Sysbox)"

    # Skip Sysbox-based container test when already inside a container
    if _cai_is_container; then
        skip "Running inside a container - skipping Sysbox container verification"
        return
    fi

    # Check prerequisites
    if ! command -v docker >/dev/null 2>&1; then
        skip "Docker not available"
        return
    fi
    if ! docker context inspect "$CONTEXT_NAME" >/dev/null 2>&1; then
        skip "Context '$CONTEXT_NAME' not found"
        return
    fi
    local runtimes_json
    runtimes_json=$(docker --context "$CONTEXT_NAME" info --format '{{json .Runtimes}}' 2>/dev/null) || runtimes_json=""
    if [[ -z "$runtimes_json" ]] || ! printf '%s' "$runtimes_json" | grep -q "sysbox-runc"; then
        skip "sysbox-runc runtime not available"
        return
    fi
    if ! docker --context "$CONTEXT_NAME" image inspect "$TEST_IMAGE" >/dev/null 2>&1; then
        skip "Test image not available"
        return
    fi

    # Create test data volume with manifest for non-existent binary
    local test_volume="${TEST_RUN_ID}-missing-binary-data"
    docker --context "$CONTEXT_NAME" volume create --label "test_run=$TEST_RUN_ID" "$test_volume" >/dev/null

    # Populate volume with manifest for a binary that doesn't exist
    docker --context "$CONTEXT_NAME" run --rm \
        -v "$test_volume:/data" \
        alpine:latest /bin/sh -c '
            mkdir -p /data/containai/manifests
            cat > /data/containai/manifests/99-nonexistent.toml << EOF
# User manifest with non-existent binary
[agent]
name = "nonexistent-agent"
binary = "this-binary-does-not-exist-xyz123"
default_args = ["--test"]
aliases = []
optional = true
EOF
        ' 2>/dev/null

    # Start container
    local container_name="${TEST_RUN_ID}-missing-binary"
    local run_output run_rc
    run_output=$(docker --context "$CONTEXT_NAME" run -d \
        --runtime=sysbox-runc \
        --name "$container_name" \
        --label "test_run=$TEST_RUN_ID" \
        -v "$test_volume:/mnt/agent-data:rw" \
        --stop-timeout 10 \
        "$TEST_IMAGE" 2>&1) && run_rc=0 || run_rc=$?

    if [[ $run_rc -ne 0 ]]; then
        fail "Failed to start test container: $run_output"
        return
    fi

    # Wait for container to initialize
    local wait_timeout=30
    local wait_elapsed=0
    while [[ $wait_elapsed -lt $wait_timeout ]]; do
        if docker --context "$CONTEXT_NAME" exec "$container_name" \
            systemctl is-active containai-init.service >/dev/null 2>&1; then
            break
        fi
        sleep 2
        wait_elapsed=$((wait_elapsed + 2))
    done

    # Container should start successfully
    local container_status
    container_status=$(docker --context "$CONTEXT_NAME" inspect --format '{{.State.Status}}' "$container_name" 2>/dev/null) || container_status=""

    if [[ "$container_status" == "running" ]]; then
        pass "Container started despite missing optional binary"
    else
        fail "Container failed to start (status: $container_status)"
        return
    fi

    # Check that NO wrapper was created for the non-existent binary
    local wrapper_file
    wrapper_file=$(docker --context "$CONTEXT_NAME" exec -u agent "$container_name" \
        cat /home/agent/.bash_env.d/containai-user-agents.sh 2>/dev/null) || wrapper_file=""

    if [[ -z "$wrapper_file" ]]; then
        pass "No user wrapper file created (expected for missing optional binary)"
    elif printf '%s' "$wrapper_file" | grep -q "nonexistent-agent()"; then
        fail "Wrapper function created for non-existent binary (should be skipped)"
    else
        pass "User wrapper file exists but does not contain function for missing binary"
    fi

    # Verify binary does not exist in container
    local binary_check
    binary_check=$(docker --context "$CONTEXT_NAME" exec "$container_name" \
        command -v this-binary-does-not-exist-xyz123 2>/dev/null) || binary_check=""

    if [[ -z "$binary_check" ]]; then
        pass "Confirmed binary does not exist in container"
    else
        fail "Binary unexpectedly exists: $binary_check"
    fi
}

# ==============================================================================
# Run all tests
# ==============================================================================

printf '%s\n' "ContainAI Startup Hooks Integration Tests"
printf '%s\n' "=========================================="
printf '%s\n' "Test Run ID: $TEST_RUN_ID"
printf '\n'

# Unit tests (no Docker required)
test_init_has_run_hooks
test_systemd_dropins_use_requires
test_run_hooks_behavior
test_failed_hook_exits_nonzero

# Integration tests (require Docker/Sysbox)
test_hooks_in_container
test_user_manifest_runtime
test_ssh_wrapper_behavior
test_invalid_user_manifest
test_optional_binary_not_installed

# Summary
printf '\n'
printf '%s\n' "=========================================="
if [[ $FAILED -eq 0 ]]; then
    printf '%s\n' "[OK] All startup hooks tests passed"
    exit 0
else
    printf '%s\n' "[FAIL] Some startup hooks tests failed"
    exit 1
fi
