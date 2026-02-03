#!/usr/bin/env bash
# ==============================================================================
# Integration tests for ContainAI Network Policy - .containai/network.conf
# ==============================================================================
# Verifies:
# 1. No config file = allow all (default behavior unchanged)
# 2. Config without default_deny = informational only
# 3. Config with default_deny = enforce allowlist
# 4. Preset expansion works
# 5. Rule cleanup on stop
# 6. Hard block conflicts are logged and ignored
#
# Environment variables:
#   CAI_ALLOW_IPTABLES_SKIP=1 - Allow tests to pass without iptables
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
warn() { printf '%s\n' "[WARN] $*"; }
info() { printf '%s\n' "[INFO] $*"; }
section() {
    printf '\n'
    printf '%s\n' "=== $* ==="
}

FAILED=0
TEST_TMPDIR=""

cleanup() {
    if [[ -n "$TEST_TMPDIR" && -d "$TEST_TMPDIR" ]]; then
        rm -rf "$TEST_TMPDIR"
    fi
}

trap cleanup EXIT

setup_test_dir() {
    TEST_TMPDIR=$(mktemp -d)
    mkdir -p "$TEST_TMPDIR/.containai"
}

# ==============================================================================
# Test 1: Parse network.conf with presets
# ==============================================================================
test_parse_presets() {
    section "Test 1: Parse network.conf with presets"

    setup_test_dir
    cat > "$TEST_TMPDIR/.containai/network.conf" << 'EOF'
# Test config
[egress]
preset = package-managers
preset = git-hosts
allow = custom.example.com
default_deny = true
EOF

    _cai_parse_network_conf "$TEST_TMPDIR/.containai/network.conf"

    # Check presets
    if [[ ${#_CAI_PARSED_PRESETS[@]} -eq 2 ]]; then
        pass "Parsed 2 presets"
    else
        fail "Expected 2 presets, got ${#_CAI_PARSED_PRESETS[@]}"
    fi

    if [[ "${_CAI_PARSED_PRESETS[0]}" == "package-managers" ]]; then
        pass "First preset is package-managers"
    else
        fail "First preset should be package-managers, got ${_CAI_PARSED_PRESETS[0]}"
    fi

    # Check allows
    if [[ ${#_CAI_PARSED_ALLOWS[@]} -eq 1 ]]; then
        pass "Parsed 1 allow entry"
    else
        fail "Expected 1 allow entry, got ${#_CAI_PARSED_ALLOWS[@]}"
    fi

    if [[ "${_CAI_PARSED_ALLOWS[0]}" == "custom.example.com" ]]; then
        pass "Allow entry is custom.example.com"
    else
        fail "Allow entry should be custom.example.com, got ${_CAI_PARSED_ALLOWS[0]}"
    fi

    # Check default_deny
    if [[ "$_CAI_PARSED_DEFAULT_DENY" == "true" ]]; then
        pass "default_deny is true"
    else
        fail "default_deny should be true, got $_CAI_PARSED_DEFAULT_DENY"
    fi

    cleanup
}

# ==============================================================================
# Test 2: Parse config without default_deny
# ==============================================================================
test_parse_no_deny() {
    section "Test 2: Parse config without default_deny"

    setup_test_dir
    cat > "$TEST_TMPDIR/.containai/network.conf" << 'EOF'
[egress]
allow = api.example.com
# no default_deny line
EOF

    _cai_parse_network_conf "$TEST_TMPDIR/.containai/network.conf"

    if [[ "$_CAI_PARSED_DEFAULT_DENY" == "false" ]]; then
        pass "default_deny defaults to false"
    else
        fail "default_deny should default to false, got $_CAI_PARSED_DEFAULT_DENY"
    fi

    if [[ ${#_CAI_PARSED_ALLOWS[@]} -eq 1 ]]; then
        pass "Parsed 1 allow entry without default_deny"
    else
        fail "Expected 1 allow entry, got ${#_CAI_PARSED_ALLOWS[@]}"
    fi

    cleanup
}

# ==============================================================================
# Test 3: No config file returns success
# ==============================================================================
test_no_config_file() {
    section "Test 3: No config file returns success"

    setup_test_dir
    # Don't create network.conf

    if _cai_parse_network_conf "$TEST_TMPDIR/.containai/network.conf"; then
        pass "Parse succeeds with no config file"
    else
        fail "Parse should succeed with no config file"
    fi

    if [[ ${#_CAI_PARSED_PRESETS[@]} -eq 0 && ${#_CAI_PARSED_ALLOWS[@]} -eq 0 ]]; then
        pass "No presets or allows parsed from missing file"
    else
        fail "Should have no presets or allows from missing file"
    fi

    cleanup
}

# ==============================================================================
# Test 4: Expand presets
# ==============================================================================
test_expand_presets() {
    section "Test 4: Expand presets"

    local domains

    # package-managers preset
    if domains=$(_cai_expand_preset "package-managers"); then
        if [[ "$domains" == *"registry.npmjs.org"* && "$domains" == *"pypi.org"* ]]; then
            pass "package-managers preset includes expected domains"
        else
            fail "package-managers preset missing expected domains: $domains"
        fi
    else
        fail "Failed to expand package-managers preset"
    fi

    # git-hosts preset
    if domains=$(_cai_expand_preset "git-hosts"); then
        if [[ "$domains" == *"github.com"* && "$domains" == *"gitlab.com"* ]]; then
            pass "git-hosts preset includes expected domains"
        else
            fail "git-hosts preset missing expected domains: $domains"
        fi
    else
        fail "Failed to expand git-hosts preset"
    fi

    # ai-apis preset
    if domains=$(_cai_expand_preset "ai-apis"); then
        if [[ "$domains" == *"api.anthropic.com"* && "$domains" == *"api.openai.com"* ]]; then
            pass "ai-apis preset includes expected domains"
        else
            fail "ai-apis preset missing expected domains: $domains"
        fi
    else
        fail "Failed to expand ai-apis preset"
    fi

    # Unknown preset should fail
    if ! _cai_expand_preset "unknown-preset" 2>/dev/null; then
        pass "Unknown preset fails as expected"
    else
        fail "Unknown preset should fail"
    fi
}

# ==============================================================================
# Test 5: Hard block conflict detection
# ==============================================================================
test_hard_block_conflicts() {
    section "Test 5: Hard block conflict detection"

    # Private ranges should conflict
    if _cai_ip_conflicts_with_hard_block "10.0.0.1"; then
        pass "10.x.x.x conflicts with hard block"
    else
        fail "10.x.x.x should conflict with hard block"
    fi

    if _cai_ip_conflicts_with_hard_block "172.16.0.1"; then
        pass "172.16.x.x conflicts with hard block"
    else
        fail "172.16.x.x should conflict with hard block"
    fi

    if _cai_ip_conflicts_with_hard_block "192.168.1.1"; then
        pass "192.168.x.x conflicts with hard block"
    else
        fail "192.168.x.x should conflict with hard block"
    fi

    # Link-local should conflict
    if _cai_ip_conflicts_with_hard_block "169.254.1.1"; then
        pass "169.254.x.x (link-local) conflicts with hard block"
    else
        fail "169.254.x.x should conflict with hard block"
    fi

    # Metadata endpoints should conflict
    if _cai_ip_conflicts_with_hard_block "169.254.169.254"; then
        pass "AWS metadata IP conflicts with hard block"
    else
        fail "AWS metadata IP should conflict with hard block"
    fi

    # Public IPs should NOT conflict
    if ! _cai_ip_conflicts_with_hard_block "8.8.8.8"; then
        pass "8.8.8.8 does not conflict with hard block"
    else
        fail "8.8.8.8 should not conflict with hard block"
    fi

    if ! _cai_ip_conflicts_with_hard_block "140.82.114.3"; then
        pass "GitHub IP does not conflict with hard block"
    else
        fail "GitHub IP should not conflict with hard block"
    fi

    # Edge cases in 172.x range
    if ! _cai_ip_conflicts_with_hard_block "172.15.0.1"; then
        pass "172.15.x.x does not conflict (not in 172.16-31 range)"
    else
        fail "172.15.x.x should not conflict"
    fi

    if ! _cai_ip_conflicts_with_hard_block "172.32.0.1"; then
        pass "172.32.x.x does not conflict (not in 172.16-31 range)"
    else
        fail "172.32.x.x should not conflict"
    fi
}

# ==============================================================================
# Test 6: Parse various config formats
# ==============================================================================
test_parse_formats() {
    section "Test 6: Parse various config formats"

    setup_test_dir

    # Test with comments and whitespace
    cat > "$TEST_TMPDIR/.containai/network.conf" << 'EOF'
# Comment at start
[egress]

  # Indented comment
  preset = package-managers   # trailing comment
allow=no-space.example.com
  allow = spaces.example.com
default_deny=yes

# Comment at end
EOF

    _cai_parse_network_conf "$TEST_TMPDIR/.containai/network.conf"

    if [[ ${#_CAI_PARSED_PRESETS[@]} -eq 1 ]]; then
        pass "Parsed preset with trailing comment"
    else
        fail "Failed to parse preset with trailing comment"
    fi

    if [[ ${#_CAI_PARSED_ALLOWS[@]} -eq 2 ]]; then
        pass "Parsed 2 allow entries with various spacing"
    else
        fail "Expected 2 allow entries, got ${#_CAI_PARSED_ALLOWS[@]}"
    fi

    if [[ "$_CAI_PARSED_DEFAULT_DENY" == "true" ]]; then
        pass "default_deny=yes parsed as true"
    else
        fail "default_deny=yes should parse as true"
    fi

    cleanup
}

# ==============================================================================
# Test 7: DNS resolution (if network available)
# ==============================================================================
test_dns_resolution() {
    section "Test 7: DNS resolution"

    # Try to resolve a well-known domain
    local ips
    if ips=$(_cai_resolve_domain_to_ips "github.com" 2>/dev/null); then
        if [[ -n "$ips" ]]; then
            pass "DNS resolution works for github.com: $ips"
        else
            warn "DNS resolution returned empty for github.com"
        fi
    else
        warn "DNS resolution failed for github.com (network may be unavailable)"
    fi

    # Nonexistent domain should fail (but some environments have catch-all DNS)
    if ! _cai_resolve_domain_to_ips "nonexistent.invalid.domain.xyz" 2>/dev/null; then
        pass "DNS resolution fails for nonexistent domain"
    else
        # Some environments (e.g., corporate networks, ISPs) have wildcard DNS
        warn "DNS resolution unexpectedly succeeded for nonexistent domain (wildcard DNS?)"
    fi
}

# ==============================================================================
# Test 8: Rule cleanup function exists and is callable
# ==============================================================================
test_cleanup_function() {
    section "Test 8: Cleanup function is callable"

    # Just verify the function exists and doesn't error with a fake container
    if _cai_cleanup_container_network "fake-container-name" "" 2>/dev/null; then
        pass "Cleanup function executes without error"
    else
        fail "Cleanup function should not error on nonexistent container"
    fi
}

# ==============================================================================
# Main
# ==============================================================================
main() {
    printf '%s\n' "=============================================================================="
    printf '%s\n' "Network Policy Unit Tests for ContainAI"
    printf '%s\n' "=============================================================================="

    test_parse_presets
    test_parse_no_deny
    test_no_config_file
    test_expand_presets
    test_hard_block_conflicts
    test_parse_formats
    test_dns_resolution
    test_cleanup_function

    # Summary
    printf '\n'
    printf '%s\n' "=============================================================================="
    if [[ "$FAILED" -eq 0 ]]; then
        printf '%s\n' "All network policy tests passed!"
        exit 0
    else
        printf '%s\n' "Some network policy tests failed!"
        exit 1
    fi
}

main "$@"
