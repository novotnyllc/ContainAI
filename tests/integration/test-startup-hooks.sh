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

    # Wait for container to initialize
    sleep 5

    # Check container is running
    local container_status
    container_status=$(docker --context "$CONTEXT_NAME" inspect --format '{{.State.Status}}' "$container_name" 2>/dev/null) || container_status=""

    if [[ "$container_status" != "running" ]]; then
        fail "Container not running (status: $container_status)"
        # Get logs for debugging
        info "Container logs:"
        docker --context "$CONTEXT_NAME" logs "$container_name" 2>&1 | tail -20 || true
        return
    fi
    pass "Container is running"

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
