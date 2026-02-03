#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════
# Unit tests for src/devcontainer/cai-docker
# Tests JSONC parsing, label extraction, and port allocation logic
# ══════════════════════════════════════════════════════════════════════
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CAI_DOCKER="$PROJECT_ROOT/src/devcontainer/cai-docker"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# ──────────────────────────────────────────────────────────────────────
# Test utilities
# ──────────────────────────────────────────────────────────────────────
log_pass() {
    printf "${GREEN}✓${NC} %s\n" "$1"
    ((TESTS_PASSED++)) || true
}

log_fail() {
    printf "${RED}✗${NC} %s\n" "$1"
    ((TESTS_FAILED++)) || true
}

log_section() {
    printf "\n${YELLOW}━━━ %s ━━━${NC}\n" "$1"
}

run_test() {
    local name="$1"
    local func="$2"
    ((TESTS_RUN++)) || true
    local result=0
    $func || result=$?
    if [[ $result -eq 0 ]]; then
        log_pass "$name"
    else
        log_fail "$name"
    fi
}

# ──────────────────────────────────────────────────────────────────────
# Source the cai-docker script functions for testing
# We source it but override main() to prevent execution
# ──────────────────────────────────────────────────────────────────────
source_cai_docker() {
    # Create a temp file with main() stubbed out
    local temp_script
    temp_script=$(mktemp)
    # Copy everything except main() call
    sed '/^main "\$@"$/d' "$CAI_DOCKER" > "$temp_script"
    # shellcheck source=/dev/null
    source "$temp_script"
    rm -f "$temp_script"
}

# ──────────────────────────────────────────────────────────────────────
# JSONC Parsing Tests
# ──────────────────────────────────────────────────────────────────────

test_jsonc_line_comments() {
    # Line comment should be stripped (newline preserved)
    local input=$'{"key": "value"} // comment\n{"key2": "value2"}'
    local actual
    actual=$(printf '%s' "$input" | _cai_strip_jsonc_comments)
    # Check: contains key, does NOT contain comment text, contains key2
    [[ "$actual" == *'"key"'* ]] || return 1
    [[ "$actual" != *'// comment'* ]] || return 1
    [[ "$actual" == *'"key2"'* ]] || return 1
    return 0
}

test_jsonc_block_comments() {
    local input='{"key": /* block */ "value"}'
    local actual
    actual=$(printf '%s' "$input" | _cai_strip_jsonc_comments)
    [[ "$actual" == *'"key"'* ]] || return 1
    [[ "$actual" == *'"value"'* ]] || return 1
    [[ "$actual" != *'/* block */'* ]] || return 1
    return 0
}

test_jsonc_comment_in_string_preserved() {
    # This is the critical edge case: // inside a string should NOT be stripped
    local input='{"url": "https://example.com"}'
    local actual
    actual=$(printf '%s' "$input" | _cai_strip_jsonc_comments)
    [[ "$actual" == *'https://example.com'* ]]
}

test_jsonc_multiline_block_comment() {
    local input='{"key":
/* multi
line
comment */ "value"}'
    local actual
    actual=$(printf '%s' "$input" | _cai_strip_jsonc_comments)
    [[ "$actual" == *'"key"'* ]] || return 1
    [[ "$actual" == *'"value"'* ]] || return 1
    [[ "$actual" != *'multi'* ]] || return 1
    return 0
}

# ──────────────────────────────────────────────────────────────────────
# Label Extraction Tests
# ──────────────────────────────────────────────────────────────────────

test_extract_devcontainer_labels() {
    local result
    result=$(_cai_extract_devcontainer_labels \
        docker run \
        --label "devcontainer.config_file=/path/to/.devcontainer/devcontainer.json" \
        --label "devcontainer.local_folder=/path/to/myproject" \
        --name test-container \
        ubuntu)

    local config_file local_folder
    config_file=$(printf '%s' "$result" | head -1)
    local_folder=$(printf '%s' "$result" | tail -1)

    [[ "$config_file" == "/path/to/.devcontainer/devcontainer.json" ]] &&
    [[ "$local_folder" == "/path/to/myproject" ]]
}

test_extract_labels_with_equals_in_path() {
    local result
    result=$(_cai_extract_devcontainer_labels \
        docker run \
        --label "devcontainer.config_file=/path/with=equals/.devcontainer/devcontainer.json" \
        --label "devcontainer.local_folder=/path/with=equals/project" \
        ubuntu)

    local config_file
    config_file=$(printf '%s' "$result" | head -1)

    # The path after the first = should be preserved
    [[ "$config_file" == "/path/with=equals/.devcontainer/devcontainer.json" ]]
}

test_extract_labels_missing() {
    local result
    result=$(_cai_extract_devcontainer_labels docker run --name test ubuntu)

    local config_file local_folder
    config_file=$(printf '%s' "$result" | head -1)
    local_folder=$(printf '%s' "$result" | tail -1)

    [[ -z "$config_file" ]] && [[ -z "$local_folder" ]]
}

# ──────────────────────────────────────────────────────────────────────
# ContainAI Feature Detection Tests
# ──────────────────────────────────────────────────────────────────────

test_has_containai_feature_ghcr() {
    local temp_file
    temp_file=$(mktemp)
    cat > "$temp_file" << 'EOF'
{
    "image": "mcr.microsoft.com/devcontainers/python:3.11",
    "features": {
        "ghcr.io/novotnyllc/containai/feature:latest": {}
    }
}
EOF
    local result=0
    _cai_has_containai_feature "$temp_file" || result=$?
    rm -f "$temp_file"
    [[ $result -eq 0 ]]
}

test_has_containai_feature_with_comments() {
    local temp_file
    temp_file=$(mktemp)
    cat > "$temp_file" << 'EOF'
{
    // This is a devcontainer with ContainAI
    "image": "mcr.microsoft.com/devcontainers/python:3.11",
    "features": {
        /* Enable ContainAI sandbox */
        "ghcr.io/novotnyllc/containai/feature:latest": {
            "enableCredentials": false
        }
    }
}
EOF
    local result=0
    _cai_has_containai_feature "$temp_file" || result=$?
    rm -f "$temp_file"
    [[ $result -eq 0 ]]
}

test_has_containai_feature_not_present() {
    local temp_file
    temp_file=$(mktemp)
    cat > "$temp_file" << 'EOF'
{
    "image": "mcr.microsoft.com/devcontainers/python:3.11",
    "features": {
        "ghcr.io/devcontainers/features/git:1": {}
    }
}
EOF
    local result=0
    _cai_has_containai_feature "$temp_file" || result=$?
    rm -f "$temp_file"
    [[ $result -ne 0 ]]
}

# ──────────────────────────────────────────────────────────────────────
# Data Volume Extraction Tests
# ──────────────────────────────────────────────────────────────────────

test_get_data_volume_custom() {
    local temp_file
    temp_file=$(mktemp)
    cat > "$temp_file" << 'EOF'
{
    "features": {
        "ghcr.io/novotnyllc/containai/feature:latest": {
            "dataVolume": "my-custom-volume"
        }
    }
}
EOF
    local result
    result=$(_cai_get_data_volume "$temp_file")
    rm -f "$temp_file"
    [[ "$result" == "my-custom-volume" ]]
}

test_get_data_volume_default() {
    local temp_file
    temp_file=$(mktemp)
    cat > "$temp_file" << 'EOF'
{
    "features": {
        "ghcr.io/novotnyllc/containai/feature:latest": {}
    }
}
EOF
    local result
    result=$(_cai_get_data_volume "$temp_file")
    rm -f "$temp_file"
    [[ "$result" == "containai-data" ]]
}

test_get_data_volume_rejects_path() {
    # SECURITY: dataVolume must be a Docker volume name, not a host path
    local temp_file
    temp_file=$(mktemp)
    cat > "$temp_file" << 'EOF'
{
    "features": {
        "ghcr.io/novotnyllc/containai/feature:latest": {
            "dataVolume": "/etc/passwd"
        }
    }
}
EOF
    local result
    result=$(_cai_get_data_volume "$temp_file" 2>/dev/null)
    rm -f "$temp_file"
    # Should return default, not the path
    [[ "$result" == "containai-data" ]]
}

test_get_data_volume_rejects_bind_mount() {
    # SECURITY: Reject bind mount syntax
    local temp_file
    temp_file=$(mktemp)
    cat > "$temp_file" << 'EOF'
{
    "features": {
        "ghcr.io/novotnyllc/containai/feature:latest": {
            "dataVolume": "host:container"
        }
    }
}
EOF
    local result
    result=$(_cai_get_data_volume "$temp_file" 2>/dev/null)
    rm -f "$temp_file"
    # Should return default, not the bind mount
    [[ "$result" == "containai-data" ]]
}

test_get_data_volume_rejects_home() {
    # SECURITY: Reject home directory
    local temp_file
    temp_file=$(mktemp)
    cat > "$temp_file" << 'EOF'
{
    "features": {
        "ghcr.io/novotnyllc/containai/feature:latest": {
            "dataVolume": "~"
        }
    }
}
EOF
    local result
    result=$(_cai_get_data_volume "$temp_file" 2>/dev/null)
    rm -f "$temp_file"
    [[ "$result" == "containai-data" ]]
}

# ──────────────────────────────────────────────────────────────────────
# Workspace Name Sanitization Tests
# ──────────────────────────────────────────────────────────────────────

test_sanitize_workspace_name_normal() {
    local result
    result=$(_cai_sanitize_workspace_name "my-project")
    [[ "$result" == "my-project" ]]
}

test_sanitize_workspace_name_spaces() {
    local result
    result=$(_cai_sanitize_workspace_name "my project name")
    [[ "$result" == "my-project-name" ]]
}

test_sanitize_workspace_name_special_chars() {
    local result
    result=$(_cai_sanitize_workspace_name "project@2024!test")
    [[ "$result" == "project-2024-test" ]]
}

# ──────────────────────────────────────────────────────────────────────
# Credentials Extraction Tests
# ──────────────────────────────────────────────────────────────────────

test_get_enable_credentials_true() {
    local temp_file
    temp_file=$(mktemp)
    cat > "$temp_file" << 'EOF'
{
    "features": {
        "ghcr.io/novotnyllc/containai/feature:latest": {
            "enableCredentials": true
        }
    }
}
EOF
    local result
    result=$(_cai_get_enable_credentials "$temp_file")
    rm -f "$temp_file"
    [[ "$result" == "true" ]]
}

test_get_enable_credentials_default_false() {
    local temp_file
    temp_file=$(mktemp)
    cat > "$temp_file" << 'EOF'
{
    "features": {
        "ghcr.io/novotnyllc/containai/feature:latest": {}
    }
}
EOF
    local result
    result=$(_cai_get_enable_credentials "$temp_file")
    rm -f "$temp_file"
    [[ "$result" == "false" ]]
}

# ──────────────────────────────────────────────────────────────────────
# Container Command Detection Tests
# ──────────────────────────────────────────────────────────────────────

# As a dockerPath wrapper, argv starts with the subcommand (no "docker" prefix)
test_is_container_create_command_run() {
    _cai_is_container_create_command run --name test ubuntu
}

test_is_container_create_command_create() {
    _cai_is_container_create_command create --name test ubuntu
}

test_is_container_create_command_container_run() {
    _cai_is_container_create_command container run --name test ubuntu
}

test_is_container_create_command_container_create() {
    _cai_is_container_create_command container create --name test ubuntu
}

test_is_container_create_command_ps() {
    ! _cai_is_container_create_command ps
}

test_is_container_create_command_exec() {
    ! _cai_is_container_create_command exec -it container bash
}

test_is_container_create_command_inspect() {
    ! _cai_is_container_create_command inspect container
}

# ──────────────────────────────────────────────────────────────────────
# Main test runner
# ──────────────────────────────────────────────────────────────────────

main() {
    printf "Testing cai-docker wrapper\n"
    printf "══════════════════════════════════════════════════════════════\n"

    # Check requirements
    if ! command -v python3 &>/dev/null; then
        printf '%sError: python3 required for tests%s\n' "$RED" "$NC"
        exit 1
    fi

    if [[ ! -f "$CAI_DOCKER" ]]; then
        printf '%sError: cai-docker not found at %s%s\n' "$RED" "$CAI_DOCKER" "$NC"
        exit 1
    fi

    # Source the script
    source_cai_docker

    log_section "JSONC Parsing"
    run_test "Line comments stripped" test_jsonc_line_comments
    run_test "Block comments stripped" test_jsonc_block_comments
    run_test "Comment-like sequences in strings preserved" test_jsonc_comment_in_string_preserved
    run_test "Multiline block comments stripped" test_jsonc_multiline_block_comment

    log_section "Label Extraction"
    run_test "Extract devcontainer labels" test_extract_devcontainer_labels
    run_test "Handle equals in path" test_extract_labels_with_equals_in_path
    run_test "Handle missing labels" test_extract_labels_missing

    log_section "ContainAI Feature Detection"
    run_test "Detect ghcr.io containai feature" test_has_containai_feature_ghcr
    run_test "Detect feature with JSONC comments" test_has_containai_feature_with_comments
    run_test "Return false when feature not present" test_has_containai_feature_not_present

    log_section "Data Volume Extraction"
    run_test "Extract custom data volume" test_get_data_volume_custom
    run_test "Use default data volume" test_get_data_volume_default
    run_test "Reject path as data volume" test_get_data_volume_rejects_path
    run_test "Reject bind mount syntax" test_get_data_volume_rejects_bind_mount
    run_test "Reject home directory" test_get_data_volume_rejects_home

    log_section "Workspace Name Sanitization"
    run_test "Normal workspace name" test_sanitize_workspace_name_normal
    run_test "Sanitize spaces" test_sanitize_workspace_name_spaces
    run_test "Sanitize special chars" test_sanitize_workspace_name_special_chars

    log_section "Credentials Extraction"
    run_test "Extract enableCredentials=true" test_get_enable_credentials_true
    run_test "Default to false when not set" test_get_enable_credentials_default_false

    log_section "Container Command Detection"
    run_test "Detect run subcommand" test_is_container_create_command_run
    run_test "Detect create subcommand" test_is_container_create_command_create
    run_test "Detect container run" test_is_container_create_command_container_run
    run_test "Detect container create" test_is_container_create_command_container_create
    run_test "Ignore ps subcommand" test_is_container_create_command_ps
    run_test "Ignore exec subcommand" test_is_container_create_command_exec
    run_test "Ignore inspect subcommand" test_is_container_create_command_inspect

    # Summary
    printf "\n══════════════════════════════════════════════════════════════\n"
    printf "Tests: %d | Passed: ${GREEN}%d${NC} | Failed: ${RED}%d${NC}\n" \
        "$TESTS_RUN" "$TESTS_PASSED" "$TESTS_FAILED"

    if [[ $TESTS_FAILED -gt 0 ]]; then
        exit 1
    fi
    exit 0
}

main "$@"
