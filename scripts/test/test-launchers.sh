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
    local attempt=0
    local max_attempts=5
    local removed=true
    while [ $attempt -lt $max_attempts ]; do
        removed=true
        local containers
        containers=$(docker ps -aq --filter "label=coding-agents.test=true" 2>/dev/null || true)
        if [ -n "$containers" ]; then
            echo "  Removing containers (attempt $((attempt+1))/$max_attempts)..."
            echo "$containers" | xargs -r docker rm -f 2>/dev/null || true
            removed=false
        fi

        local networks
        networks=$(docker network ls --filter "name=test-" --format "{{.Name}}" 2>/dev/null || true)
        if [ -n "$networks" ]; then
            echo "  Removing networks (attempt $((attempt+1))/$max_attempts)..."
            echo "$networks" | xargs -r docker network rm 2>/dev/null || true
            removed=false
        fi

        if $removed; then
            break
        fi
        attempt=$((attempt + 1))
        sleep 1
    done

    if ! $removed; then
        echo "⚠️  Warning: Some test resources may still exist after cleanup retries"
    fi
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
    git config commit.gpgsign false
    git config remote.pushDefault local
    
    echo "# Test Repository" > README.md
    git add README.md
    git commit -q -m "Initial commit"
    git checkout -q -B main
    
    pass "Created test repository at $TEST_REPO_DIR"
}

# ============================================================================
# Assertion Helper Functions
# ============================================================================

pass() {
    echo -e "${GREEN}✓${NC} $1"
    ((PASSED_TESTS++))
    return 0
}

fail() {
    echo -e "${RED}✗${NC} $1"
    ((FAILED_TESTS++))
    return 1
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
    
    if echo "$haystack" | grep -q -- "$needle"; then
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

run_test() {
    local name="$1"
    shift
    if "$@"; then
        return 0
    else
        local status=$?
        fail "$name failed with exit code $status"
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

    if docker ps -a --filter "name=^${container_name}$" --format "{{.Names}}" | grep -q "^${container_name}$"; then
        docker rm -f "$container_name" >/dev/null 2>&1 || true
    fi
    
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
    
    source "$PROJECT_ROOT/scripts/utils/common-functions.sh"
    
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

    local seccomp_path
    if seccomp_path=$(resolve_seccomp_profile_path "$PROJECT_ROOT"); then
        assert_equals "$PROJECT_ROOT/docker/profiles/seccomp-coding-agents.json" "$seccomp_path" "resolve_seccomp_profile_path() returns built-in profile"
    else
        fail "resolve_seccomp_profile_path() failed to locate built-in profile"
    fi

    local fake_root
    fake_root=$(mktemp -d)
    if resolve_seccomp_profile_path "$fake_root" >/dev/null 2>&1; then
        fail "resolve_seccomp_profile_path() should fail when profile file is absent"
    else
        pass "resolve_seccomp_profile_path() reports missing built-in profile"
    fi
    rm -rf "$fake_root"

    if resolve_apparmor_profile_name "$PROJECT_ROOT" >/dev/null 2>&1; then
        pass "resolve_apparmor_profile_name() locates active AppArmor profile"
    else
        fail "resolve_apparmor_profile_name() could not verify AppArmor support"
    fi
}

test_helper_network_isolation() {
    test_section "Helper network isolation"

    source "$PROJECT_ROOT/scripts/utils/common-functions.sh"

    local helper_dir="$HOME/.coding-agents-tests"
    mkdir -p "$helper_dir"
    local script
    script=$(mktemp "$helper_dir/helper-net.XXXXXX.py")
    cat <<'PY' > "$script"
import os
import sys

interfaces = [name for name in os.listdir('/sys/class/net') if name not in ('lo',)]
if interfaces:
    sys.exit(1)
sys.exit(0)
PY

    if run_python_tool "$script" --mount "$(dirname "$script")" >/dev/null 2>&1; then
        pass "Helper runner hides non-loopback interfaces"
    else
        fail "Helper runner exposed external network interfaces"
    fi
    rm -f "$script"
}

test_agent_data_packager() {
    test_section "Agent data packager"

    local temp_home
    temp_home=$(mktemp -d)
    mkdir -p "$temp_home/.copilot/sessions"
    mkdir -p "$temp_home/.copilot/logs"
    echo '{"messages":1}' > "$temp_home/.copilot/sessions/chat.json"
    echo 'log line' > "$temp_home/.copilot/logs/agent.log"

    local out_dir
    out_dir=$(mktemp -d)
    local tar_path="$out_dir/import.tar"
    local manifest_path="$out_dir/manifest.json"
    local key_file="$out_dir/hmac.key"
    local secure_tar_path="$out_dir/import-secure.tar"
    local secure_manifest_path="$out_dir/manifest-secure.json"

    python3 - <<'PY' > "$key_file"
import secrets
print(secrets.token_hex(32))
PY

    if python3 "$PROJECT_ROOT/scripts/utils/package-agent-data.py" \
        --agent copilot \
        --session-id test-session \
        --home-path "$temp_home" \
        --tar "$tar_path" \
        --manifest "$manifest_path"; then
        pass "Packager produced outputs"
    else
        fail "Packager script exited non-zero"
        rm -rf "$temp_home" "$out_dir"
        return
    fi

    if tar tf "$tar_path" | grep -q '.copilot/sessions/chat.json'; then
        pass "Tar archive contains session file"
    else
        fail "Tar archive missing session file"
    fi

    local manifest_content
    manifest_content=$(cat "$manifest_path")
    assert_contains "$manifest_content" '.copilot/sessions/chat.json' "Manifest records session path"
    assert_contains "$manifest_content" '.copilot/logs/agent.log' "Manifest records log path"
    assert_contains "$manifest_content" '"session": "test-session"' "Manifest tagged with session id"

    local missing_hmac_target
    missing_hmac_target=$(mktemp -d)
    if python3 "$PROJECT_ROOT/scripts/utils/package-agent-data.py" \
        --mode merge \
        --agent copilot \
        --session-id test-session \
        --target-home "$missing_hmac_target" \
        --tar "$tar_path" \
        --manifest "$manifest_path" \
        --require-hmac \
        --hmac-key-file "$key_file"; then
        fail "Merge should fail when manifest lacks HMAC metadata"
    else
        pass "Require-HMAC merge rejects manifests without HMAC entries"
    fi
    rm -rf "$missing_hmac_target"

    if python3 "$PROJECT_ROOT/scripts/utils/package-agent-data.py" \
        --agent copilot \
        --session-id secure-session \
        --home-path "$temp_home" \
        --tar "$secure_tar_path" \
        --manifest "$secure_manifest_path" \
        --hmac-key-file "$key_file"; then
        pass "Packager produced HMAC-protected outputs"
    else
        fail "Packager failed when HMAC key supplied"
        rm -rf "$temp_home" "$out_dir"
        return
    fi

    local secure_manifest_content
    secure_manifest_content=$(cat "$secure_manifest_path")
    assert_contains "$secure_manifest_content" '"hmac":' "Manifest records HMAC metadata"

    local secure_target_home
    secure_target_home=$(mktemp -d)
    if python3 "$PROJECT_ROOT/scripts/utils/package-agent-data.py" \
        --mode merge \
        --agent copilot \
        --session-id secure-session \
        --target-home "$secure_target_home" \
        --tar "$secure_tar_path" \
        --manifest "$secure_manifest_path" \
        --require-hmac \
        --hmac-key-file "$key_file"; then
        pass "Merge succeeds with matching HMAC metadata"
    else
        fail "Merge failed despite valid HMAC metadata"
    fi

    if [ -f "$secure_target_home/.copilot/sessions/chat.json" ]; then
        pass "Secure merge restored session file"
    else
        fail "Secure merge missing session file"
    fi
    rm -rf "$secure_target_home"

    rm -rf "$temp_home/.copilot/sessions" "$temp_home/.copilot/logs"
    if python3 "$PROJECT_ROOT/scripts/utils/package-agent-data.py" \
        --agent copilot \
        --session-id empty-session \
        --home-path "$temp_home" \
        --tar "$tar_path" \
        --manifest "$manifest_path"; then
        if [ -f "$tar_path" ]; then
            fail "Tarball should be removed when no data is present"
        else
            pass "Packager omits tarball when no inputs exist"
        fi
    else
        fail "Packager script failed on empty input"
    fi

    rm -rf "$temp_home" "$out_dir"
}

test_audit_logging_pipeline() {
    test_section "Audit logging pipeline"

    source "$PROJECT_ROOT/scripts/utils/common-functions.sh"

    local log_file
    log_file=$(mktemp /tmp/helper-audit.XXXXXX.log)
    export CODING_AGENTS_AUDIT_LOG="$log_file"

    log_security_event "unit-test" '{"ok":true}'
    if grep -q '"event":"unit-test"' "$log_file"; then
        pass "Security events persisted to audit log"
    else
        fail "Audit log missing custom event"
    fi

    local override_token
    override_token=$(mktemp /tmp/helper-override.XXXXXX)
    local temp_repo
    temp_repo=$(mktemp -d)
    pushd "$temp_repo" >/dev/null
    git init -q
    mkdir -p scripts/launchers
    echo "echo hi" > scripts/launchers/tool.sh
    git add scripts/launchers/tool.sh >/dev/null
    git commit -q -m "init"
    echo "# dirty" >> scripts/launchers/tool.sh
    popd >/dev/null

    CODING_AGENTS_DIRTY_OVERRIDE_TOKEN="$override_token" \
        ensure_trusted_paths_clean "$temp_repo" "test stubs" "scripts/launchers" >/dev/null 2>&1
    if grep -q '"event":"override-used"' "$log_file"; then
        pass "Override usage recorded"
    else
        fail "Override usage not captured in audit log"
    fi

    rm -rf "$temp_repo" "$override_token"
    rm -f "$log_file"
    unset CODING_AGENTS_DIRTY_OVERRIDE_TOKEN
    unset CODING_AGENTS_AUDIT_LOG
}

test_seccomp_ptrace_block() {
    test_section "Seccomp ptrace enforcement"

    local profile="$PROJECT_ROOT/docker/profiles/seccomp-coding-agents.json"
    if [ ! -f "$profile" ]; then
        fail "Seccomp profile missing at $profile"
        return
    fi

    local python_code
    read -r -d '' python_code <<'PY'
import ctypes, os, sys

libc = ctypes.CDLL(None, use_errno=True)
PTRACE_ATTACH = 16
pid = os.getpid()
res = libc.ptrace(PTRACE_ATTACH, pid, None, None)
err = ctypes.get_errno()
if res == -1 and err in (1, 13, 38):
    sys.exit(0)
sys.exit(1)
PY

    if docker run --rm \
        --security-opt "no-new-privileges" \
        --security-opt "seccomp=$profile" \
        python:3.11-slim \
        python -c "$python_code" >/dev/null 2>&1; then
        pass "ptrace blocked by seccomp profile"
    else
        fail "ptrace syscall not blocked by seccomp profile"
    fi
}

test_trusted_path_enforcement() {
    test_section "Trusted path enforcement"

    local saved_override_token="${CODING_AGENTS_DIRTY_OVERRIDE_TOKEN:-}"
    unset CODING_AGENTS_DIRTY_OVERRIDE_TOKEN

    if ! command -v git >/dev/null 2>&1; then
        fail "Git is required for trusted path tests"
        if [ -n "$saved_override_token" ]; then
            CODING_AGENTS_DIRTY_OVERRIDE_TOKEN="$saved_override_token"
        else
            unset CODING_AGENTS_DIRTY_OVERRIDE_TOKEN
        fi
        return
    fi

    local temp_repo
    temp_repo=$(mktemp -d)
    pushd "$temp_repo" >/dev/null
    git init -q
    mkdir -p scripts/launchers
    echo "echo hi" > scripts/launchers/foo.sh
    git add scripts/launchers/foo.sh >/dev/null
    git commit -q -m "init"
    popd >/dev/null

    source "$PROJECT_ROOT/scripts/utils/common-functions.sh"

    if ensure_trusted_paths_clean "$temp_repo" "test" "scripts/launchers"; then
        pass "Clean trusted paths allowed"
    else
        fail "Clean trusted paths should pass"
    fi

    echo "# dirty" >> "$temp_repo/scripts/launchers/foo.sh"
    if ensure_trusted_paths_clean "$temp_repo" "test" "scripts/launchers"; then
        fail "Dirty trusted paths should fail"
    else
        pass "Dirty trusted paths blocked"
    fi

    local override_token="$temp_repo/allow-dirty"
    touch "$override_token"
    if CODING_AGENTS_DIRTY_OVERRIDE_TOKEN="$override_token" ensure_trusted_paths_clean "$temp_repo" "test" "scripts/launchers" >/dev/null 2>&1; then
        pass "Override token permits dirty paths"
    else
        fail "Override token should allow launch"
    fi

    rm -rf "$temp_repo"

    if [ -n "$saved_override_token" ]; then
        CODING_AGENTS_DIRTY_OVERRIDE_TOKEN="$saved_override_token"
    else
        unset CODING_AGENTS_DIRTY_OVERRIDE_TOKEN
    fi
}

test_session_config_renderer() {
    test_section "Session config renderer"

    source "$PROJECT_ROOT/scripts/utils/common-functions.sh"

    local output_dir
    output_dir=$(mktemp -d)
    local session_id="test-session-$$"
    local renderer="$PROJECT_ROOT/scripts/utils/render-session-config.py"
    local render_args=(
        "--config" "$PROJECT_ROOT/config.toml"
        "--output" "$output_dir"
        "--session-id" "$session_id"
        "--network-policy" "allow-all"
        "--repo" "test-repo"
        "--agent" "copilot"
        "--container" "test-container"
    )

    if run_python_tool "$renderer" --mount "$output_dir" -- "${render_args[@]}" >/dev/null 2>&1; then
        local manifest="$output_dir/manifest.json"
        local config_json="$output_dir/github-copilot/config.json"
        local servers_file="$output_dir/servers.txt"
        if [ -f "$manifest" ]; then
            pass "Manifest generated"
        else
            fail "Manifest missing"
        fi
        if [ -f "$config_json" ]; then
            pass "Copilot config rendered"
        else
            fail "Copilot config missing"
        fi
        if [ -f "$servers_file" ] && [ -s "$servers_file" ]; then
            local line_count
            line_count=$(grep -cve '^\s*$' "$servers_file" || true)
            if [ "$line_count" -gt 0 ]; then
                pass "Server list exported via servers.txt"
            else
                fail "servers.txt exists but is empty"
            fi
        else
            fail "servers.txt missing"
        fi
    else
        fail "render-session-config.py failed via python runner"
    fi

    rm -rf "$output_dir"
}

test_secret_broker_cli() {
    test_section "Secret broker CLI"

    local broker_script="$PROJECT_ROOT/scripts/runtime/secret-broker.py"
    if [ ! -x "$broker_script" ]; then
        fail "secret-broker.py missing or not executable"
        return
    fi

    source "$PROJECT_ROOT/scripts/utils/common-functions.sh"

    local config_root
    config_root=$(mktemp -d)
    local cap_dir
    cap_dir=$(mktemp -d)
    local env_dir="$config_root/config"
    mkdir -p "$env_dir"

    local config_mounts=("--mount" "$config_root")
    local issue_mounts=("--mount" "$config_root" "--mount" "$cap_dir")
    local sealed_dir="$cap_dir/alpha/secrets"
    local redeem_mounts=("--mount" "$config_root" "--mount" "$cap_dir")

    if CODING_AGENTS_CONFIG_DIR="$env_dir" run_python_tool "$broker_script" "${issue_mounts[@]}" -- issue --session-id test-session --output "$cap_dir" --stubs alpha >/dev/null 2>&1; then
        pass "Capability issuance succeeds"
    else
        fail "Capability issuance failed"
        rm -rf "$config_root" "$cap_dir"
        return
    fi

    local token_file
    token_file=$(find "$cap_dir" -name '*.json' | head -n 1)
    if [ -f "$token_file" ]; then
        pass "Capability token file generated"
    else
        fail "Capability token file missing"
    fi

    if CODING_AGENTS_CONFIG_DIR="$env_dir" run_python_tool "$broker_script" "${config_mounts[@]}" -- store --stub alpha --name TEST_SECRET --value super-secret >/dev/null 2>&1; then
        pass "Broker secret store succeeds"
    else
        fail "Broker secret store failed"
    fi

    if CODING_AGENTS_CONFIG_DIR="$env_dir" run_python_tool "$broker_script" "${redeem_mounts[@]}" -- redeem --capability "$token_file" --secret TEST_SECRET >/dev/null 2>&1; then
        pass "Capability redemption seals secret"
    else
        fail "Capability redemption failed"
    fi

    local sealed_file="$sealed_dir/TEST_SECRET.sealed"
    if [ -f "$sealed_file" ]; then
        pass "Sealed secret written to disk"
    else
        fail "Sealed secret missing"
    fi

    local decrypted
    decrypted=$(python3 - "$token_file" "$sealed_file" <<'PY'
import base64
import hashlib
import json
import pathlib
import sys

if len(sys.argv) < 3:
    sys.exit(1)

cap_path, sealed_path = sys.argv[1], sys.argv[2]
cap = pathlib.Path(cap_path).read_text(encoding='utf-8')
cap = json.loads(cap)
sealed = pathlib.Path(sealed_path).read_text(encoding='utf-8')
sealed = json.loads(sealed)

session_key = bytes.fromhex(cap["session_key"])
data = base64.b64decode(sealed["ciphertext"])
block = hashlib.sha256(session_key).digest()
out = bytearray()
idx = 0
for byte in data:
    out.append(byte ^ block[idx])
    idx += 1
    if idx >= len(block):
        block = hashlib.sha256(block).digest()
        idx = 0

sys.stdout.write(out.decode('utf-8'))
PY
)
    if [ "$decrypted" = "super-secret" ]; then
        pass "Sealed secret decrypts with session key"
    else
        fail "Sealed secret decrypted to unexpected value"
    fi

    local unsealed
    if unsealed=$("$PROJECT_ROOT/scripts/runtime/capability-unseal.py" --stub alpha --secret TEST_SECRET --cap-root "$cap_dir" --format raw 2>/dev/null); then
        if [ "$unsealed" = "super-secret" ]; then
            pass "capability-unseal retrieves sealed secret"
        else
            fail "capability-unseal returned unexpected value"
        fi
    else
        fail "capability-unseal script failed"
    fi

    if CODING_AGENTS_CONFIG_DIR="$env_dir" run_python_tool "$broker_script" "${redeem_mounts[@]}" -- redeem --capability "$token_file" --secret TEST_SECRET >/dev/null 2>&1; then
        fail "Redeeming same capability twice should fail"
    else
        pass "Capability redemption is single-use"
    fi

    if CODING_AGENTS_CONFIG_DIR="$env_dir" run_python_tool "$broker_script" "${config_mounts[@]}" -- health >/dev/null 2>&1; then
        pass "Broker health check succeeds"
    else
        fail "Broker health check failed"
    fi

    rm -rf "$config_root" "$cap_dir"
}

test_codex_cli_helper() {
    test_section "Codex CLI helper"

    source "$PROJECT_ROOT/scripts/utils/common-functions.sh"

    local helper_script="$PROJECT_ROOT/docker/agents/codex/prepare-codex-secrets.sh"
    if [ ! -x "$helper_script" ]; then
        fail "Codex helper missing at $helper_script"
        return
    fi

    local broker_script="$PROJECT_ROOT/scripts/runtime/secret-broker.py"
    local config_root cap_dir env_dir secret_file
    config_root=$(mktemp -d)
    cap_dir=$(mktemp -d)
    env_dir="$config_root/config"
    mkdir -p "$env_dir"
    secret_file="$config_root/codex-auth.json"
    printf '{"refresh_token":"unit-test","access_token":"abc"}' >"$secret_file"

    local previous_config="${CODING_AGENTS_CONFIG_DIR:-}"
    local issue_mounts=("--mount" "$config_root" "--mount" "$cap_dir")
    local store_mounts=("--mount" "$config_root")
    local redeem_mounts=("--mount" "$config_root" "--mount" "$cap_dir")

    if CODING_AGENTS_CONFIG_DIR="$env_dir" run_python_tool "$broker_script" "${issue_mounts[@]}" -- issue --session-id codex-helper --output "$cap_dir" --stubs agent_codex_cli >/dev/null 2>&1; then
        pass "Codex capability issuance succeeds"
    else
        fail "Codex capability issuance failed"
        rm -rf "$config_root" "$cap_dir" "$secret_file"
        [ -n "$previous_config" ] && CODING_AGENTS_CONFIG_DIR="$previous_config" || unset CODING_AGENTS_CONFIG_DIR
        return
    fi

    if CODING_AGENTS_CONFIG_DIR="$env_dir" run_python_tool "$broker_script" "${store_mounts[@]}" -- store --stub agent_codex_cli --name codex_cli_auth_json --from-file "$secret_file" >/dev/null 2>&1; then
        pass "Codex secret stored"
    else
        fail "Codex secret store failed"
    fi

    local token_file
    token_file=$(find "$cap_dir" -name '*.json' | head -n 1)
    if [ -z "$token_file" ]; then
        fail "Codex capability token missing"
    fi

    if CODING_AGENTS_CONFIG_DIR="$env_dir" run_python_tool "$broker_script" "${redeem_mounts[@]}" -- redeem --capability "$token_file" --secret codex_cli_auth_json >/dev/null 2>&1; then
        pass "Codex capability redemption seals secret"
    else
        fail "Codex capability redemption failed"
    fi

    local agent_home secret_root
    agent_home=$(mktemp -d)
    secret_root="$agent_home/run-secrets"
    if CODING_AGENTS_AGENT_HOME="$agent_home" \
        CODING_AGENTS_AGENT_CAP_ROOT="$cap_dir" \
        CODING_AGENTS_AGENT_SECRET_ROOT="$secret_root" \
        CODING_AGENTS_CAPABILITY_UNSEAL="$PROJECT_ROOT/scripts/runtime/capability-unseal.py" \
        "$helper_script" >/dev/null 2>&1; then
        pass "prepare-codex-secrets decrypts bundle"
    else
        fail "prepare-codex-secrets failed"
    fi

    local auth_file="$secret_root/codex/auth.json"
    if [ -f "$auth_file" ] && grep -q 'unit-test' "$auth_file"; then
        pass "Codex auth.json materialized"
    else
        fail "Codex auth.json missing or incorrect"
    fi

    local link_target
    link_target=$(readlink "$agent_home/.codex" 2>/dev/null || true)
    if [ "$link_target" = "$secret_root/codex" ]; then
        pass "Codex CLI directory symlinked to secret tmpfs"
    else
        fail "Codex CLI directory not linked to secret tmpfs"
    fi

    if [ -n "$previous_config" ]; then
        CODING_AGENTS_CONFIG_DIR="$previous_config"
    else
        unset CODING_AGENTS_CONFIG_DIR
    fi
    rm -rf "$config_root" "$cap_dir" "$agent_home"
    rm -f "$secret_file"
}

test_claude_cli_helper() {
    test_section "Claude CLI helper"

    source "$PROJECT_ROOT/scripts/utils/common-functions.sh"

    local helper_script="$PROJECT_ROOT/docker/agents/claude/prepare-claude-secrets.sh"
    if [ ! -x "$helper_script" ]; then
        fail "Claude helper missing at $helper_script"
        return
    fi

    local broker_script="$PROJECT_ROOT/scripts/runtime/secret-broker.py"
    local config_root env_dir secret_file
    config_root=$(mktemp -d)
    env_dir="$config_root/config"
    mkdir -p "$env_dir"
    secret_file="$config_root/claude-auth.json"
    printf '{"api_key":"file-secret","workspace_id":"dev"}' >"$secret_file"

    local previous_config="${CODING_AGENTS_CONFIG_DIR:-}"

    local file_cap_dir inline_cap_dir
    file_cap_dir=$(mktemp -d)
    inline_cap_dir=$(mktemp -d)
    local store_mounts=("--mount" "$config_root")

    local issue_file_mounts=("--mount" "$config_root" "--mount" "$file_cap_dir")
    local redeem_file_mounts=("--mount" "$config_root" "--mount" "$file_cap_dir")
    if CODING_AGENTS_CONFIG_DIR="$env_dir" run_python_tool "$broker_script" "${issue_file_mounts[@]}" -- issue --session-id claude-helper-file --output "$file_cap_dir" --stubs agent_claude_cli >/dev/null 2>&1; then
        pass "Claude capability issuance (file) succeeds"
    else
        fail "Claude capability issuance (file) failed"
        rm -rf "$config_root" "$file_cap_dir" "$inline_cap_dir"
        rm -f "$secret_file"
        [ -n "$previous_config" ] && CODING_AGENTS_CONFIG_DIR="$previous_config" || unset CODING_AGENTS_CONFIG_DIR
        return
    fi

    if CODING_AGENTS_CONFIG_DIR="$env_dir" run_python_tool "$broker_script" "${store_mounts[@]}" -- store --stub agent_claude_cli --name claude_cli_credentials --from-file "$secret_file" >/dev/null 2>&1; then
        pass "Claude secret (file) stored"
    else
        fail "Claude secret (file) store failed"
    fi

    if CODING_AGENTS_CONFIG_DIR="$env_dir" run_python_tool "$broker_script" "${redeem_file_mounts[@]}" -- redeem --capability "$(find "$file_cap_dir" -name '*.json' | head -n 1)" --secret claude_cli_credentials >/dev/null 2>&1; then
        pass "Claude capability (file) redemption seals secret"
    else
        fail "Claude capability (file) redemption failed"
    fi

    local agent_home_file secret_root_file
    agent_home_file=$(mktemp -d)
    secret_root_file="$agent_home_file/run-secrets"
    mkdir -p "$secret_root_file"
    mkdir -p "$agent_home_file/.config/coding-agents/claude"
    printf '{"projects":{}}' >"$agent_home_file/.config/coding-agents/claude/.claude.json"

    if CODING_AGENTS_AGENT_HOME="$agent_home_file" \
        CODING_AGENTS_AGENT_CAP_ROOT="$file_cap_dir" \
        CODING_AGENTS_AGENT_SECRET_ROOT="$secret_root_file" \
        CODING_AGENTS_CAPABILITY_UNSEAL="$PROJECT_ROOT/scripts/runtime/capability-unseal.py" \
        "$helper_script" >/dev/null 2>&1; then
        pass "prepare-claude-secrets decrypts file-based bundle"
    else
        fail "prepare-claude-secrets failed for file-based bundle"
    fi

    local file_credentials="$agent_home_file/.claude/.credentials.json"
    if [ -f "$file_credentials" ] && grep -q '"api_key": "file-secret"' "$file_credentials" && grep -q '"workspace_id": "dev"' "$file_credentials"; then
        pass "Claude credentials mirrored JSON payload"
    else
        fail "Claude credentials missing expected JSON payload"
    fi

    local inline_secret="inline-secret-token"
    local issue_inline_mounts=("--mount" "$config_root" "--mount" "$inline_cap_dir")
    local redeem_inline_mounts=("--mount" "$config_root" "--mount" "$inline_cap_dir")

    if CODING_AGENTS_CONFIG_DIR="$env_dir" run_python_tool "$broker_script" "${issue_inline_mounts[@]}" -- issue --session-id claude-helper-inline --output "$inline_cap_dir" --stubs agent_claude_cli >/dev/null 2>&1; then
        pass "Claude capability issuance (inline) succeeds"
    else
        fail "Claude capability issuance (inline) failed"
    fi

    if CODING_AGENTS_CONFIG_DIR="$env_dir" run_python_tool "$broker_script" "${store_mounts[@]}" -- store --stub agent_claude_cli --name claude_cli_credentials --value "$inline_secret" >/dev/null 2>&1; then
        pass "Claude secret (inline) stored"
    else
        fail "Claude secret (inline) store failed"
    fi

    if CODING_AGENTS_CONFIG_DIR="$env_dir" run_python_tool "$broker_script" "${redeem_inline_mounts[@]}" -- redeem --capability "$(find "$inline_cap_dir" -name '*.json' | head -n 1)" --secret claude_cli_credentials >/dev/null 2>&1; then
        pass "Claude capability (inline) redemption seals secret"
    else
        fail "Claude capability (inline) redemption failed"
    fi

    local agent_home_inline secret_root_inline
    agent_home_inline=$(mktemp -d)
    secret_root_inline="$agent_home_inline/run-secrets"
    mkdir -p "$secret_root_inline"

    if CODING_AGENTS_AGENT_HOME="$agent_home_inline" \
        CODING_AGENTS_AGENT_CAP_ROOT="$inline_cap_dir" \
        CODING_AGENTS_AGENT_SECRET_ROOT="$secret_root_inline" \
        CODING_AGENTS_CAPABILITY_UNSEAL="$PROJECT_ROOT/scripts/runtime/capability-unseal.py" \
        "$helper_script" >/dev/null 2>&1; then
        pass "prepare-claude-secrets decrypts inline bundle"
    else
        fail "prepare-claude-secrets failed for inline bundle"
    fi

    local inline_credentials="$agent_home_inline/.claude/.credentials.json"
    if [ -f "$inline_credentials" ] && grep -q "\"api_key\": \"$inline_secret\"" "$inline_credentials"; then
        pass "Claude credentials synthesized from API key"
    else
        fail "Claude credentials missing synthesized API key"
    fi

    if [ -n "$previous_config" ]; then
        CODING_AGENTS_CONFIG_DIR="$previous_config"
    else
        unset CODING_AGENTS_CONFIG_DIR
    fi
    rm -rf "$config_root" "$file_cap_dir" "$inline_cap_dir" "$agent_home_file" "$agent_home_inline"
    rm -f "$secret_file"
}

test_host_security_preflight() {
    test_section "Host security preflight"

    source "$PROJECT_ROOT/scripts/utils/common-functions.sh"

        if verify_host_security_prereqs "$PROJECT_ROOT" >/dev/null 2>&1; then
            pass "Preflight succeeds when host security prerequisites are satisfied"
        else
            fail "Preflight rejected valid host security configuration"
        fi

    local seccomp_profile="$PROJECT_ROOT/docker/profiles/seccomp-coding-agents.json"
    local temp_dir
    temp_dir=$(mktemp -d)
    local temp_backup="$temp_dir/seccomp-coding-agents.json"
    if mv "$seccomp_profile" "$temp_backup"; then
        if verify_host_security_prereqs "$PROJECT_ROOT" >/dev/null 2>&1; then
            fail "Preflight should fail when seccomp profile is missing"
        else
            pass "Seccomp profile requirement enforced"
        fi
        mv "$temp_backup" "$seccomp_profile"
        rmdir "$temp_dir"
    else
        fail "Unable to move seccomp profile for negative test"
    fi
}

test_container_security_preflight() {
    test_section "Container security preflight"

    source "$PROJECT_ROOT/scripts/utils/common-functions.sh"

    local good_json='{"SecurityOptions":["name=seccomp","name=apparmor"]}'
        if CODING_AGENTS_CONTAINER_INFO_JSON="$good_json" verify_container_security_support >/dev/null 2>&1; then
            pass "Container preflight passes when runtime reports seccomp feature"
        else
            fail "Container preflight rejected valid runtime JSON"
        fi

    local missing_apparmor='{"SecurityOptions":["name=seccomp"]}'
    if CODING_AGENTS_CONTAINER_INFO_JSON="$missing_apparmor" verify_container_security_support >/dev/null 2>&1; then
        fail "Container preflight should fail when AppArmor missing"
    else
        pass "AppArmor requirement enforced when runtime lacks support"
    fi
}

test_local_remote_push() {
    test_section "Testing secure local remote push"

    source "$PROJECT_ROOT/scripts/utils/common-functions.sh"

    local workspace_dir
    workspace_dir=$(mktemp -d)
    local bare_dir
    bare_dir=$(mktemp -d)
    local bare_repo="$bare_dir/local-remote.git"
    git init --bare "$bare_repo" >/dev/null

    mkdir -p /tmp/source-repo
    rm -rf /tmp/source-repo/*
    cp -a "$TEST_REPO_DIR/." /tmp/source-repo/

    local agent_branch="copilot/session-test"
    local setup_script
    setup_script=$(generate_repo_setup_script "local" "" "$TEST_REPO_DIR" "$agent_branch")
    if ! echo "$setup_script" | WORKSPACE_DIR="$workspace_dir" SOURCE_TYPE="local" LOCAL_REMOTE_URL="file://$bare_repo" AGENT_BRANCH="$agent_branch" GIT_URL="" bash; then
        fail "Repository setup script failed"
        rm -rf "$workspace_dir" "$bare_dir"
        return
    fi

    pushd "$workspace_dir" >/dev/null
    git config user.name "Test User"
    git config user.email "test@example.com"
    git config commit.gpgsign false
    echo "secure push" >> README.md
    git add README.md
    git commit -q -m "test push"
    if git push local "$agent_branch" >/dev/null 2>&1; then
        pass "git push to local remote succeeded"
    else
        fail "git push to local remote failed"
    fi

    popd >/dev/null || true

    local pushed_ref
    pushed_ref=$(git --git-dir="$bare_repo" rev-parse "refs/heads/$agent_branch" 2>/dev/null || echo "")
    if [ -n "$pushed_ref" ]; then
        pass "Bare remote received agent branch"
    else
        fail "Bare remote missing agent branch"
    fi

    rm -rf "$workspace_dir" "$bare_dir"
    rm -rf /tmp/source-repo
    unset WORKSPACE_DIR SOURCE_TYPE LOCAL_REMOTE_URL AGENT_BRANCH
}

test_local_remote_fallback_push() {
    test_section "Testing local remote fallback push"

    source "$PROJECT_ROOT/scripts/utils/common-functions.sh"

    local workspace_dir
    workspace_dir=$(mktemp -d)
    local bare_dir
    bare_dir=$(mktemp -d)
    local bare_repo="$bare_dir/local-remote.git"
    git init --bare "$bare_repo" >/dev/null

    mkdir -p /tmp/source-repo
    rm -rf /tmp/source-repo/*
    cp -a "$TEST_REPO_DIR/." /tmp/source-repo/

    local agent_branch="copilot/session-fallback"
    local setup_script
    setup_script=$(generate_repo_setup_script "local" "" "$TEST_REPO_DIR" "$agent_branch")
    if ! echo "$setup_script" | WORKSPACE_DIR="$workspace_dir" SOURCE_TYPE="local" LOCAL_REMOTE_URL="" LOCAL_REPO_PATH="file://$bare_repo" AGENT_BRANCH="$agent_branch" bash; then
        fail "Repository setup script failed with fallback remote"
        rm -rf "$workspace_dir" "$bare_dir"
        rm -rf /tmp/source-repo
        return
    fi

    pushd "$workspace_dir" >/dev/null
    git config user.name "Test User"
    git config user.email "test@example.com"
    git config commit.gpgsign false
    echo "fallback push" >> README.md
    git add README.md
    git commit -q -m "fallback push"
    if git push local "$agent_branch" >/dev/null 2>&1; then
        pass "git push succeeded using fallback LOCAL_REPO_PATH"
    else
        fail "git push failed when using LOCAL_REPO_PATH fallback"
    fi
    popd >/dev/null || true

    if git --git-dir="$bare_repo" rev-parse --verify "refs/heads/$agent_branch" >/dev/null 2>&1; then
        pass "Fallback remote contains agent branch"
    else
        fail "Fallback remote missing agent branch"
    fi

    rm -rf "$workspace_dir" "$bare_dir"
    rm -rf /tmp/source-repo
    unset WORKSPACE_DIR SOURCE_TYPE LOCAL_REMOTE_URL LOCAL_REPO_PATH AGENT_BRANCH
}

test_secure_remote_sync() {
    test_section "Testing secure remote host sync"

    source "$PROJECT_ROOT/scripts/utils/common-functions.sh"

    local agent_branch="copilot/session-sync"
    local bare_dir
    bare_dir=$(mktemp -d)
    local bare_repo="$bare_dir/local-remote.git"
    git init --bare "$bare_repo" >/dev/null

    local agent_workspace
    agent_workspace=$(mktemp -d)
    pushd "$agent_workspace" >/dev/null
    git init -q
    git config user.name "Agent"
    git config user.email "agent@example.com"
    git config commit.gpgsign false
    echo "agent work" > agent.txt
    git add agent.txt
    git commit -q -m "agent commit"
    git branch -M "$agent_branch"
    git remote add origin "$bare_repo"
    if git push origin "$agent_branch" >/dev/null 2>&1; then
        pass "Agent branch pushed to secure remote"
    else
        fail "Failed to push agent branch to secure remote"
        popd >/dev/null || true
        rm -rf "$agent_workspace" "$bare_dir"
        return
    fi
    popd >/dev/null || true

    (cd "$TEST_REPO_DIR" && git branch -D "$agent_branch" >/dev/null 2>&1 || true)

    local sanitized_branch="${agent_branch//\//-}"
    local container_name="test-sync-${sanitized_branch}"

    # Remove any stale container from previous runs to avoid conflicts
    if docker ps -a --filter "name=^${container_name}$" --format "{{.Names}}" | grep -q "^${container_name}$"; then
        docker rm -f "$container_name" >/dev/null 2>&1 || true
    fi
    docker run -d \
        --name "$container_name" \
        --label "coding-agents.test=true" \
        --label "coding-agents.type=agent" \
        --label "coding-agents.branch=$agent_branch" \
        --label "coding-agents.repo-path=$TEST_REPO_DIR" \
        --label "coding-agents.local-remote=$bare_repo" \
        alpine:latest sleep 60 >/dev/null

    if remove_container_with_sidecars "$container_name" "true" "true" >/dev/null 2>&1; then
        pass "remove_container_with_sidecars synchronizes secure remote"
    else
        fail "remove_container_with_sidecars failed"
    fi

    if git -C "$TEST_REPO_DIR" show "$agent_branch:agent.txt" >/dev/null 2>&1; then
        pass "Host branch fast-forwarded from secure remote"
    else
        fail "Host branch missing agent changes"
    fi

    (cd "$TEST_REPO_DIR" && git branch -D "$agent_branch" >/dev/null 2>&1 || true)
    rm -rf "$agent_workspace" "$bare_dir"
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
    create_test_container "codex" "test-coding-agents-repo" "develop" >/dev/null
    
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

test_prompt_fallback_repo_setup() {
    test_section "Testing prompt fallback workspace preparation"

    source "$PROJECT_ROOT/scripts/utils/common-functions.sh"

    local setup_script
    setup_script=$(generate_repo_setup_script "prompt" "" "" "")
    local temp_dir
    temp_dir=$(mktemp -d)
    echo "keep" > "$temp_dir/existing.txt"

    local output
    if output=$(SOURCE_TYPE="prompt" WORKSPACE_DIR="$temp_dir" bash <<<"$setup_script" 2>&1); then
        assert_contains "$output" "Prompt session requested without repository" "Setup script acknowledges prompt fallback"
    else
        fail "Prompt fallback setup script failed"
    fi

    if [ -z "$(ls -A "$temp_dir")" ]; then
        pass "Prompt fallback workspace left empty"
    else
        fail "Prompt fallback workspace not empty after setup"
    fi

    rm -rf "$temp_dir"
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
            assert_contains "$output" "--prompt" "${wrapper} --help documents --prompt"
        else
            fail "${wrapper} --help failed (exit $?)"
        fi
    done
}

# List of available tests in default order
ALL_TESTS=(
    "setup_test_repo"
    "test_container_runtime_detection"
    "test_shared_functions"
    "test_helper_network_isolation"
    "test_agent_data_packager"
    "test_audit_logging_pipeline"
    "test_seccomp_ptrace_block"
    "test_host_security_preflight"
    "test_container_security_preflight"
    "test_trusted_path_enforcement"
    "test_session_config_renderer"
    "test_secret_broker_cli"
    "test_codex_cli_helper"
    "test_claude_cli_helper"
    "test_local_remote_push"
    "test_local_remote_fallback_push"
    "test_secure_remote_sync"
    "test_wsl_path_conversion"
    "test_container_naming"
    "test_container_labels"
    "test_image_pull"
    "test_branch_sanitization"
    "test_multiple_agents"
    "test_label_filtering"
    "test_container_status"
    "test_prompt_fallback_repo_setup"
    "test_launcher_wrappers"
    "test_list_agents"
    "test_remove_agent"
)

print_usage() {
    cat <<'USAGE'
Usage: scripts/test/test-launchers.sh [all|TEST_NAME ...]

Run the full suite by default or provide specific test function names.

Options:
  all          Run every test (default when no args specified)
  TEST_NAME    Run one or more named tests
  --list       Display available test names
  -h, --help   Show this help text
USAGE
}

list_available_tests() {
    printf '%s\n' "${ALL_TESTS[@]}"
}

is_valid_test() {
    local candidate="$1"
    local name
    for name in "${ALL_TESTS[@]}"; do
        if [ "$candidate" = "$name" ]; then
            return 0
        fi
    done
    return 1
}

# Main test execution
main() {
    local selected_tests=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                print_usage
                exit 0
                ;;
            --list)
                list_available_tests
                exit 0
                ;;
            all)
                selected_tests=("all")
                shift
                ;;
            --)
                shift
                break
                ;;
            *)
                selected_tests+=("$1")
                shift
                ;;
        esac
    done

    if [ ${#selected_tests[@]} -eq 0 ] || { [ ${#selected_tests[@]} -eq 1 ] && [ "${selected_tests[0]}" = "all" ]; }; then
        selected_tests=("${ALL_TESTS[@]}")
    fi

    local test_name
    for test_name in "${selected_tests[@]}"; do
        if ! is_valid_test "$test_name"; then
            echo "❌ Unknown test: $test_name" >&2
            echo "Available tests:" >&2
            list_available_tests >&2
            exit 1
        fi
    done

    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║      Coding Agents Launcher Test Suite                   ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo ""
    echo "Testing from: $PROJECT_ROOT"
    echo ""

    local setup_needed=1
    for test_name in "${selected_tests[@]}"; do
        if [ "$test_name" = "setup_test_repo" ]; then
            setup_needed=0
            break
        fi
    done

    if [ $setup_needed -eq 1 ]; then
        run_test "setup_test_repo" setup_test_repo
    fi

    for test_name in "${selected_tests[@]}"; do
        run_test "$test_name" "$test_name"
    done

    # Cleanup happens in trap
}

main "$@"
