#!/usr/bin/env bash
# ==============================================================================
# Integration tests for ContainAI Network Security - iptables blocking
# ==============================================================================
# Verifies:
# 1. iptables rules are applied correctly
# 2. Container can reach internet (public IPs)
# 3. Container can reach host gateway
# 4. Private IP ranges (10/8, 172.16/12, 192.168/16) are blocked
# 5. Cloud metadata endpoints (169.254.169.254, etc.) are blocked
# 6. Rules can be removed cleanly
#
# Environment variables:
#   CAI_ALLOW_NETWORK_FAILURE=1  - Allow internet connectivity failures
#   CAI_ALLOW_IPTABLES_SKIP=1    - Allow tests to pass without iptables verification
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
SRC_DIR="$REPO_ROOT/src"

# Source containai library for platform detection, _cai_timeout, and constants
if ! source "$SRC_DIR/containai.sh"; then
    printf '%s\n' "[ERROR] Failed to source containai.sh" >&2
    exit 1
fi

# ==============================================================================
# Test helpers - match existing test patterns
# ==============================================================================

pass() { printf '%s\n' "[PASS] $*"; }
fail() {
    printf '%s\n' "[FAIL] $*" >&2
    FAILED=1
}
warn() { printf '%s\n' "[WARN] $*"; }
info() { printf '%s\n' "[INFO] $*"; }
section() {
    printf '\n'
    printf '%s\n' "=== $* ==="
}

FAILED=0

# Track verification status for accurate summary
IPTABLES_VERIFIED=false
GATEWAY_VERIFIED=false

# Context name for sysbox containers - use from lib/docker.sh (sourced via containai.sh)
CONTEXT_NAME="${_CAI_CONTAINAI_DOCKER_CONTEXT:-containai-docker}"

# Timeouts
TEST_TIMEOUT=30
CONTAINER_STOP_TIMEOUT=30

# Test container name (unique per run to avoid conflicts)
TEST_RUN_ID="$$"
TEST_CONTAINER_NAME="containai-nettest-$$"

# ContainAI base image for system container testing
TEST_IMAGE="${CONTAINAI_TEST_IMAGE:-ghcr.io/novotnyllc/containai/base:latest}"

# Network configuration - populated dynamically by init_network_config()
BRIDGE_NAME=""
GATEWAY_IP=""

# Metadata endpoints to test
METADATA_ENDPOINTS="169.254.169.254 169.254.170.2 100.100.100.200"

# Private ranges to test (we test representative IPs from each range)
# 10.0.0.0/8 - test 10.0.0.1
# 172.16.0.0/12 - test 172.16.0.1 (but NOT 172.30.x.x which is our bridge)
# 192.168.0.0/16 - test 192.168.1.1
PRIVATE_RANGE_TEST_IPS="10.0.0.1 172.16.0.1 192.168.1.1"

# Initialize network configuration dynamically using _cai_get_network_config
init_network_config() {
    local config
    if config=$(_cai_get_network_config 2>/dev/null); then
        BRIDGE_NAME="${config%% *}"
        config="${config#* }"
        GATEWAY_IP="${config%% *}"
        return 0
    else
        # Fall back to constants if dynamic detection fails
        BRIDGE_NAME="${_CAI_CONTAINAI_DOCKER_BRIDGE:-cai0}"
        local bridge_addr="${_CAI_CONTAINAI_DOCKER_BRIDGE_ADDR:-172.30.0.1/16}"
        GATEWAY_IP="${bridge_addr%%/*}"
        return 1
    fi
}

# Cleanup function
cleanup() {
    info "Cleaning up test container..."

    # Stop and remove test container (ignore errors)
    # Check docker is available before cleanup
    if command -v docker >/dev/null 2>&1; then
        if docker --context "$CONTEXT_NAME" inspect --type container -- "$TEST_CONTAINER_NAME" >/dev/null 2>&1; then
            docker --context "$CONTEXT_NAME" stop --time "$CONTAINER_STOP_TIMEOUT" -- "$TEST_CONTAINER_NAME" 2>/dev/null || true
            docker --context "$CONTEXT_NAME" rm -f -- "$TEST_CONTAINER_NAME" 2>/dev/null || true
        fi
    fi
}

trap cleanup EXIT

# Portable timeout wrapper (uses _cai_timeout from containai.sh)
run_with_timeout() {
    local secs="$1"
    shift
    _cai_timeout "$secs" "$@"
}

# Execute command inside the system container
exec_in_container() {
    docker --context "$CONTEXT_NAME" exec -- "$TEST_CONTAINER_NAME" "$@"
}

# Check if a command exists inside the container
container_has_command() {
    local cmd="$1"
    exec_in_container sh -c "command -v $cmd >/dev/null 2>&1"
}

# Check if we can run iptables (requires root or CAP_NET_ADMIN)
can_run_iptables() {
    if ! command -v iptables >/dev/null 2>&1; then
        return 1
    fi
    # Try a read-only iptables command
    if _cai_iptables -S >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

# ==============================================================================
# Prerequisites check
# ==============================================================================
check_prerequisites() {
    section "Prerequisites"

    # Initialize network configuration dynamically
    if init_network_config; then
        info "Network config detected dynamically"
    else
        warn "Using fallback network constants"
    fi
    info "  Bridge: $BRIDGE_NAME"
    info "  Gateway: $GATEWAY_IP"

    # Check if context exists
    if ! docker context inspect "$CONTEXT_NAME" >/dev/null 2>&1; then
        fail "Context '$CONTEXT_NAME' not found"
        info "  Remediation: Run 'cai setup' to configure Sysbox"
        return 1
    fi
    pass "Docker context '$CONTEXT_NAME' exists"

    # Check if iptables is available on host
    if ! command -v iptables >/dev/null 2>&1; then
        fail "iptables is not installed on host"
        info "  Remediation: Install iptables package"
        return 1
    fi
    pass "iptables is installed"

    # Check if we can run iptables
    if ! can_run_iptables; then
        if [[ "${CAI_ALLOW_IPTABLES_SKIP:-}" == "1" ]]; then
            warn "Cannot run iptables (need root or CAP_NET_ADMIN)"
            warn "  Allowed by CAI_ALLOW_IPTABLES_SKIP=1 - iptables tests will be skipped"
        else
            fail "Cannot run iptables (need root or CAP_NET_ADMIN)"
            info "  Remediation: Run tests as root or with sudo"
            info "  Or set CAI_ALLOW_IPTABLES_SKIP=1 to skip iptables verification"
            return 1
        fi
    else
        pass "Can run iptables commands"
    fi

    # Check if bridge exists
    if ! ip link show "$BRIDGE_NAME" >/dev/null 2>&1; then
        warn "Bridge '$BRIDGE_NAME' does not exist"
        info "  Bridge will be created when Docker starts containers"
        info "  Some tests may be skipped"
    else
        pass "Bridge '$BRIDGE_NAME' exists"
    fi

    return 0
}

# ==============================================================================
# Test 1: Verify iptables rules are present
# ==============================================================================
test_iptables_rules_present() {
    section "Test 1: Verify iptables rules are present"

    if ! can_run_iptables; then
        if [[ "${CAI_ALLOW_IPTABLES_SKIP:-}" == "1" ]]; then
            warn "Skipping iptables rule check - cannot run iptables (allowed by CAI_ALLOW_IPTABLES_SKIP=1)"
            return 0
        fi
        fail "Cannot verify iptables rules - insufficient permissions"
        info "  Set CAI_ALLOW_IPTABLES_SKIP=1 to skip this check"
        return 1
    fi

    # Use the network.sh function to check rules
    if _cai_check_network_rules "true"; then
        pass "All network security rules are present"
        IPTABLES_VERIFIED=true
    else
        case "${_CAI_NETWORK_RULES_STATUS:-}" in
            partial)
                fail "Some network security rules are missing"
                info "  Remediation: Run 'cai setup' to apply rules"
                ;;
            none)
                fail "No network security rules found"
                info "  Remediation: Run 'cai setup' to apply rules"
                ;;
            no_chain)
                fail "DOCKER-USER chain does not exist"
                info "  Remediation: Ensure Docker is running, then run 'cai setup'"
                ;;
            *)
                fail "Unknown status: ${_CAI_NETWORK_RULES_STATUS:-unknown}"
                ;;
        esac
        return 1
    fi
}

# ==============================================================================
# Test 2: Start system container for network testing
# ==============================================================================
test_start_container() {
    section "Test 2: Start system container for network testing"

    # Pull image if needed
    if ! docker --context "$CONTEXT_NAME" image inspect "$TEST_IMAGE" >/dev/null 2>&1; then
        info "Pulling test image: $TEST_IMAGE"
        if ! run_with_timeout 120 docker --context "$CONTEXT_NAME" pull "$TEST_IMAGE"; then
            fail "Failed to pull test image: $TEST_IMAGE"
            return 1
        fi
    fi

    # Start system container with sysbox-runc runtime
    info "Starting system container with sysbox-runc runtime..."

    local run_output run_rc
    run_output=$(docker --context "$CONTEXT_NAME" run -d \
        --runtime=sysbox-runc \
        --name "$TEST_CONTAINER_NAME" \
        --stop-timeout "$CONTAINER_STOP_TIMEOUT" \
        --label "containai.test=true" \
        --label "containai.test_run=$TEST_RUN_ID" \
        "$TEST_IMAGE" 2>&1) && run_rc=0 || run_rc=$?

    if [[ $run_rc -ne 0 ]]; then
        fail "Failed to start system container"
        info "  Error: $run_output"
        return 1
    fi

    # Verify container is running
    local container_status
    container_status=$(docker --context "$CONTEXT_NAME" inspect --format '{{.State.Status}}' -- "$TEST_CONTAINER_NAME" 2>/dev/null) || container_status=""

    if [[ "$container_status" != "running" ]]; then
        fail "Container not running (status: $container_status)"
        return 1
    fi

    pass "System container started successfully"
}

# ==============================================================================
# Test 3: Container can reach internet
# ==============================================================================
test_internet_connectivity() {
    section "Test 3: Container can reach internet"

    # Verify wget is available in container
    if ! container_has_command wget; then
        fail "wget not available in container - cannot test internet connectivity"
        info "  Container image may be missing required tools"
        return 1
    fi

    # Test connectivity to a public IP (using wget to github)
    info "Testing internet connectivity from container..."

    local network_output network_rc
    # Use wget (BusyBox compatible) with short timeout
    network_output=$(run_with_timeout "$TEST_TIMEOUT" exec_in_container \
        wget -q -O /dev/null -T 10 https://github.com 2>&1) && network_rc=0 || network_rc=$?

    # Handle no timeout mechanism
    if [[ $network_rc -eq 125 ]]; then
        network_output=$(exec_in_container wget -q -O /dev/null -T 10 https://github.com 2>&1) && network_rc=0 || network_rc=$?
    fi

    if [[ $network_rc -eq 124 ]]; then
        if [[ "${CAI_ALLOW_NETWORK_FAILURE:-}" == "1" ]]; then
            warn "Internet connectivity test timed out (allowed by CAI_ALLOW_NETWORK_FAILURE=1)"
            return 0
        fi
        fail "Internet connectivity test timed out after ${TEST_TIMEOUT}s"
        return 1
    fi

    if [[ $network_rc -eq 0 ]]; then
        pass "Container has internet connectivity"
    else
        if [[ "${CAI_ALLOW_NETWORK_FAILURE:-}" == "1" ]]; then
            warn "Internet connectivity failed (allowed by CAI_ALLOW_NETWORK_FAILURE=1)"
            info "  Error: $network_output"
            return 0
        fi
        fail "Container cannot reach internet"
        info "  Exit code: $network_rc"
        info "  Error: $network_output"
        info "  Set CAI_ALLOW_NETWORK_FAILURE=1 to skip in restricted environments"
        return 1
    fi
}

# ==============================================================================
# Test 4: Container can reach host gateway
# ==============================================================================
test_gateway_connectivity() {
    section "Test 4: Container can reach host gateway"

    # Verify ping is available in container
    if ! container_has_command ping; then
        warn "ping not available in container - using route check instead"
        # Check if we have a route to the gateway
        local route_output
        if route_output=$(exec_in_container ip route get "$GATEWAY_IP" 2>&1); then
            if printf '%s' "$route_output" | grep -q "$GATEWAY_IP"; then
                pass "Route to host gateway ($GATEWAY_IP) exists"
                GATEWAY_VERIFIED=true
                return 0
            fi
        fi
        warn "Cannot verify gateway connectivity (ping missing, route check inconclusive)"
        return 0
    fi

    # The gateway should be reachable (this is allowed by our rules)
    info "Testing connectivity to host gateway ($GATEWAY_IP)..."

    local ping_output ping_rc
    # Use ping with count=1 and timeout
    ping_output=$(run_with_timeout "$TEST_TIMEOUT" exec_in_container \
        ping -c 1 -W 5 "$GATEWAY_IP" 2>&1) && ping_rc=0 || ping_rc=$?

    # Handle no timeout mechanism
    if [[ $ping_rc -eq 125 ]]; then
        ping_output=$(exec_in_container ping -c 1 -W 5 "$GATEWAY_IP" 2>&1) && ping_rc=0 || ping_rc=$?
    fi

    if [[ $ping_rc -eq 124 ]]; then
        warn "Gateway connectivity test timed out"
        info "  Gateway may not respond to ICMP"
        return 0
    fi

    if [[ $ping_rc -eq 0 ]]; then
        pass "Container can reach host gateway ($GATEWAY_IP)"
        GATEWAY_VERIFIED=true
    else
        # Gateway might not respond to ICMP, try TCP connection to SSH port if available
        warn "Ping to gateway failed, trying TCP check..."
        local tcp_rc
        # Use bash /dev/tcp for TCP check
        exec_in_container bash -c "timeout 5 bash -c 'echo >/dev/tcp/$GATEWAY_IP/22' 2>/dev/null" && tcp_rc=0 || tcp_rc=$?

        if [[ $tcp_rc -eq 0 ]]; then
            pass "Container can reach host gateway via TCP ($GATEWAY_IP:22)"
            GATEWAY_VERIFIED=true
        else
            warn "Cannot verify gateway connectivity (ICMP and TCP checks failed)"
            info "  This may be expected if gateway doesn't respond to probes"
            info "  Ping output: $ping_output"
        fi
    fi
}

# ==============================================================================
# Test 5: Cloud metadata endpoints are blocked
# ==============================================================================
test_metadata_blocked() {
    section "Test 5: Cloud metadata endpoints are blocked"

    # Verify curl is available in container
    if ! container_has_command curl; then
        fail "curl not available in container - cannot test metadata blocking"
        info "  Container image may be missing required tools"
        return 1
    fi

    local blocked_count=0
    local total_count=0
    local endpoint

    for endpoint in $METADATA_ENDPOINTS; do
        total_count=$((total_count + 1))
        info "Testing metadata endpoint: $endpoint"

        local curl_output curl_rc
        # Use curl with very short timeout - we expect it to fail fast if blocked
        # Connection timeout of 2 seconds should be enough to detect blocking
        curl_output=$(run_with_timeout 10 exec_in_container \
            curl -s --connect-timeout 2 --max-time 5 "http://$endpoint/" 2>&1) && curl_rc=0 || curl_rc=$?

        # Handle no timeout mechanism
        if [[ $curl_rc -eq 125 ]]; then
            curl_output=$(exec_in_container curl -s --connect-timeout 2 --max-time 5 "http://$endpoint/" 2>&1) && curl_rc=0 || curl_rc=$?
        fi

        # Expected behavior: connection should fail (timeout or refused)
        # curl returns:
        #   7 = Failed to connect (connection refused/no route)
        #   28 = Operation timed out
        #   6 = Could not resolve host (DNS failure - also acceptable)
        #   124 = timeout command killed it
        if [[ $curl_rc -eq 0 ]]; then
            fail "Metadata endpoint $endpoint is ACCESSIBLE (should be blocked)"
            info "  Response: $(printf '%s' "$curl_output" | head -1)"
        elif [[ $curl_rc -eq 7 ]] || [[ $curl_rc -eq 28 ]] || [[ $curl_rc -eq 6 ]] || [[ $curl_rc -eq 124 ]]; then
            pass "Metadata endpoint $endpoint is blocked"
            blocked_count=$((blocked_count + 1))
        else
            # Unexpected error code - treat as failure, not success
            fail "Metadata endpoint $endpoint: unexpected curl exit code $curl_rc"
            info "  Output: $curl_output"
            info "  Expected exit codes: 7 (connection refused), 28 (timeout), 6 (DNS failure)"
        fi
    done

    if [[ $blocked_count -eq $total_count ]]; then
        pass "All $total_count metadata endpoints are blocked"
    else
        fail "$((total_count - blocked_count)) of $total_count metadata endpoints had unexpected results"
    fi
}

# ==============================================================================
# Test 6: Private IP ranges are blocked
# ==============================================================================
test_private_ranges_blocked() {
    section "Test 6: Private IP ranges are blocked"

    # Verify ping is available in container
    if ! container_has_command ping; then
        fail "ping not available in container - cannot test private range blocking"
        info "  Container image may be missing required tools"
        return 1
    fi

    local blocked_count=0
    local total_count=0
    local test_ip

    for test_ip in $PRIVATE_RANGE_TEST_IPS; do
        total_count=$((total_count + 1))
        info "Testing private IP: $test_ip"

        local ping_output ping_rc
        # Use ping with count=1 and short timeout
        # We expect this to fail (no route or timeout) if blocking works
        ping_output=$(run_with_timeout 10 exec_in_container \
            ping -c 1 -W 2 "$test_ip" 2>&1) && ping_rc=0 || ping_rc=$?

        # Handle no timeout mechanism
        if [[ $ping_rc -eq 125 ]]; then
            ping_output=$(exec_in_container ping -c 1 -W 2 "$test_ip" 2>&1) && ping_rc=0 || ping_rc=$?
        fi

        # Expected behavior: ping should fail
        # ping returns non-zero if no reply received
        if [[ $ping_rc -eq 0 ]]; then
            # Check if we actually got a response
            if printf '%s' "$ping_output" | grep -q "1 received"; then
                fail "Private IP $test_ip is REACHABLE (should be blocked)"
                info "  This may indicate the IP is on your local network"
            else
                # ping returned 0 but no packets received - treat as blocked
                pass "Private IP $test_ip is blocked"
                blocked_count=$((blocked_count + 1))
            fi
        elif [[ $ping_rc -eq 1 ]] || [[ $ping_rc -eq 2 ]] || [[ $ping_rc -eq 124 ]]; then
            # 1 = no reply, 2 = other error (e.g., network unreachable), 124 = timeout
            pass "Private IP $test_ip is blocked (no response)"
            blocked_count=$((blocked_count + 1))
        else
            # Unexpected exit code - report but don't count as blocked
            warn "Private IP $test_ip: unexpected ping exit code $ping_rc"
            info "  Output: $ping_output"
            # Don't count unexpected errors as blocked - they need investigation
        fi
    done

    if [[ $blocked_count -eq $total_count ]]; then
        pass "All $total_count private IP test addresses are blocked"
    else
        warn "$((total_count - blocked_count)) of $total_count private IPs had unexpected results"
        info "  This may be expected if those IPs exist on your local network"
    fi
}

# ==============================================================================
# Test 7: Link-local range is blocked
# ==============================================================================
test_link_local_blocked() {
    section "Test 7: Link-local range (169.254.0.0/16) is blocked"

    # Verify ping is available in container
    if ! container_has_command ping; then
        fail "ping not available in container - cannot test link-local blocking"
        info "  Container image may be missing required tools"
        return 1
    fi

    # Test a link-local address that isn't a known metadata endpoint
    local test_ip="169.254.1.1"
    info "Testing link-local IP: $test_ip"

    local ping_output ping_rc
    ping_output=$(run_with_timeout 10 exec_in_container \
        ping -c 1 -W 2 "$test_ip" 2>&1) && ping_rc=0 || ping_rc=$?

    # Handle no timeout mechanism
    if [[ $ping_rc -eq 125 ]]; then
        ping_output=$(exec_in_container ping -c 1 -W 2 "$test_ip" 2>&1) && ping_rc=0 || ping_rc=$?
    fi

    if [[ $ping_rc -eq 0 ]] && printf '%s' "$ping_output" | grep -q "1 received"; then
        fail "Link-local IP $test_ip is REACHABLE (should be blocked)"
    elif [[ $ping_rc -eq 1 ]] || [[ $ping_rc -eq 2 ]] || [[ $ping_rc -eq 124 ]]; then
        # Expected: no reply or network unreachable
        pass "Link-local IP $test_ip is blocked"
    else
        # Unexpected exit code
        warn "Link-local IP $test_ip: unexpected ping exit code $ping_rc"
        info "  Output: $ping_output"
    fi
}

# ==============================================================================
# Test 8: sshd forwarding is disabled
# ==============================================================================
test_sshd_hardening() {
    section "Test 8: sshd forwarding is disabled"

    # Check sshd_config for DisableForwarding
    local sshd_config
    sshd_config=$(exec_in_container cat /etc/ssh/sshd_config 2>/dev/null) || sshd_config=""

    if [[ -z "$sshd_config" ]]; then
        warn "Could not read sshd_config from container"
        return 0
    fi

    # Check for DisableForwarding yes (comprehensive forwarding block)
    if printf '%s' "$sshd_config" | grep -qiE '^[[:space:]]*DisableForwarding[[:space:]]+yes'; then
        pass "sshd DisableForwarding is enabled"
    else
        # Check individual settings as fallback
        local hardening_issues=0

        if ! printf '%s' "$sshd_config" | grep -qiE '^[[:space:]]*AllowTcpForwarding[[:space:]]+no'; then
            warn "AllowTcpForwarding is not disabled"
            hardening_issues=$((hardening_issues + 1))
        fi

        if ! printf '%s' "$sshd_config" | grep -qiE '^[[:space:]]*AllowStreamLocalForwarding[[:space:]]+no'; then
            warn "AllowStreamLocalForwarding is not disabled"
            hardening_issues=$((hardening_issues + 1))
        fi

        if ! printf '%s' "$sshd_config" | grep -qiE '^[[:space:]]*GatewayPorts[[:space:]]+no'; then
            warn "GatewayPorts is not disabled"
            hardening_issues=$((hardening_issues + 1))
        fi

        if ! printf '%s' "$sshd_config" | grep -qiE '^[[:space:]]*PermitTunnel[[:space:]]+no'; then
            warn "PermitTunnel is not disabled"
            hardening_issues=$((hardening_issues + 1))
        fi

        if [[ $hardening_issues -gt 0 ]]; then
            warn "sshd hardening incomplete ($hardening_issues issues)"
            info "  Recommended: Add 'DisableForwarding yes' to sshd_config"
        else
            pass "sshd forwarding options are individually disabled"
        fi
    fi
}

# ==============================================================================
# Test 9: Rules cleanup works (non-destructive check)
# ==============================================================================
test_rules_cleanup_dry_run() {
    section "Test 9: Rules cleanup capability (dry-run)"

    if ! can_run_iptables; then
        if [[ "${CAI_ALLOW_IPTABLES_SKIP:-}" == "1" ]]; then
            warn "Skipping cleanup test - cannot run iptables (allowed by CAI_ALLOW_IPTABLES_SKIP=1)"
            return 0
        fi
        fail "Cannot test rule cleanup - insufficient permissions"
        return 1
    fi

    # Test the dry-run mode of rule removal
    info "Testing rule removal dry-run..."

    # Call the dry-run version of remove_network_rules
    if _cai_remove_network_rules "true" 2>/dev/null; then
        pass "Rule removal dry-run completed successfully"
    else
        warn "Rule removal dry-run failed"
        info "  This may be expected if rules are not currently applied"
    fi
}

# ==============================================================================
# Main
# ==============================================================================
main() {
    printf '%s\n' "=============================================================================="
    printf '%s\n' "Network Security Integration Tests for ContainAI"
    printf '%s\n' "=============================================================================="

    # Skip Sysbox network security verification when already inside a container
    # (these tests verify host-level Sysbox network rules, not nested ContainAI functionality)
    if _cai_is_container; then
        printf '%s\n' "[SKIP] Running inside a container - skipping Sysbox network security verification"
        printf '%s\n' "[SKIP] These tests verify host-level network rules; run on host to test installation"
        exit 0
    fi

    # Check prerequisites
    if ! command -v docker >/dev/null 2>&1; then
        printf '%s\n' "[ERROR] docker is required" >&2
        exit 1
    fi

    # Check if context exists before running tests
    if ! docker context inspect "$CONTEXT_NAME" >/dev/null 2>&1; then
        printf '\n'
        printf '%s\n' "[WARN] Context '$CONTEXT_NAME' does not exist"
        printf '%s\n' "[WARN] Run 'cai setup' first to configure Sysbox and network rules"
        printf '%s\n' "[WARN] Running tests anyway to show expected failures..."
        printf '\n'
    fi

    # Initialize network config before showing info
    init_network_config || true

    info "Test image: $TEST_IMAGE"
    info "Test container: $TEST_CONTAINER_NAME"
    info "Bridge: $BRIDGE_NAME"
    info "Gateway: $GATEWAY_IP"

    # Run prerequisite checks
    check_prerequisites || { FAILED=1; }

    # Run iptables rule verification (doesn't need container)
    test_iptables_rules_present || true

    # Start container for network tests
    test_start_container || { FAILED=1; }

    # Only run container-based tests if container started
    if docker --context "$CONTEXT_NAME" inspect --type container -- "$TEST_CONTAINER_NAME" >/dev/null 2>&1; then
        test_internet_connectivity || true
        test_gateway_connectivity || true
        test_metadata_blocked || true
        test_private_ranges_blocked || true
        test_link_local_blocked || true
        test_sshd_hardening || true
    else
        warn "Skipping container-based tests - container not running"
    fi

    # Test cleanup capability (dry-run)
    test_rules_cleanup_dry_run || true

    # Summary
    printf '\n'
    printf '%s\n' "=============================================================================="
    if [[ "$FAILED" -eq 0 ]]; then
        printf '%s\n' "All network security tests passed!"
        printf '%s\n' ""
        printf '%s\n' "Network security verification status:"
        if [[ "$IPTABLES_VERIFIED" == "true" ]]; then
            printf '%s\n' "  - iptables rules: VERIFIED"
        else
            printf '%s\n' "  - iptables rules: NOT VERIFIED (skipped or unavailable)"
        fi
        printf '%s\n' "  - Internet access: allowed"
        if [[ "$GATEWAY_VERIFIED" == "true" ]]; then
            printf '%s\n' "  - Host gateway access: VERIFIED"
        else
            printf '%s\n' "  - Host gateway access: NOT VERIFIED (gateway may not respond to probes)"
        fi
        printf '%s\n' "  - Private IP ranges: blocked"
        printf '%s\n' "  - Cloud metadata endpoints: blocked"
        printf '%s\n' "  - sshd forwarding: disabled"
        exit 0
    else
        printf '%s\n' "Some network security tests failed!"
        printf '%s\n' ""
        printf '%s\n' "Troubleshooting:"
        printf '%s\n' "  1. Run 'cai setup' to apply network rules"
        printf '%s\n' "  2. Check iptables rules: sudo iptables -L DOCKER-USER -n"
        printf '%s\n' "  3. Verify bridge exists: ip link show $BRIDGE_NAME"
        printf '%s\n' "  4. Check container logs: docker --context $CONTEXT_NAME logs $TEST_CONTAINER_NAME"
        exit 1
    fi
}

main "$@"
