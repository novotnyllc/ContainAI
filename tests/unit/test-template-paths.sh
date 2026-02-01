#!/usr/bin/env bash
# Unit tests for template path functions
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source full CLI to ensure _CAI_CONFIG_DIR is available before template.sh
# shellcheck source=../../src/containai.sh
source "$REPO_ROOT/src/containai.sh"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

TEST_TMPDIR=""
ORIGINAL_HOME=""

test_start() {
    printf 'Testing: %s\n' "$1"
    TESTS_RUN=$((TESTS_RUN + 1))
}

test_pass() {
    printf '  PASS\n'
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

test_fail() {
    printf '  FAIL: %s\n' "$1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

setup_tmpdir() {
    TEST_TMPDIR="$(mktemp -d)"
    ORIGINAL_HOME="$HOME"
}

teardown_tmpdir() {
    if [[ -n "$TEST_TMPDIR" ]] && [[ -d "$TEST_TMPDIR" ]]; then
        rm -rf "$TEST_TMPDIR"
    fi
    if [[ -n "$ORIGINAL_HOME" ]]; then
        HOME="$ORIGINAL_HOME"
    fi
}

assert_equal() {
    local expected="$1"
    local actual="$2"
    local label="$3"
    if [[ "$actual" == "$expected" ]]; then
        test_pass
    else
        test_fail "$label: expected '$expected', got '$actual'"
    fi
}

assert_success() {
    local result="$1"
    local label="$2"
    if [[ "$result" -eq 0 ]]; then
        test_pass
    else
        test_fail "$label: expected success (0), got $result"
    fi
}

assert_failure() {
    local result="$1"
    local label="$2"
    if [[ "$result" -ne 0 ]]; then
        test_pass
    else
        test_fail "$label: expected failure (non-zero), got 0"
    fi
}

# ==============================================================================
# Test: _cai_get_template_dir returns correct path
# ==============================================================================

test_start "_cai_get_template_dir returns templates directory"
result=$(_cai_get_template_dir)
expected="$HOME/.config/containai/templates"
assert_equal "$expected" "$result" "template dir path"

# ==============================================================================
# Test: _cai_get_template_path with default template
# ==============================================================================

test_start "_cai_get_template_path returns default template path"
result=$(_cai_get_template_path)
expected="$HOME/.config/containai/templates/default/Dockerfile"
assert_equal "$expected" "$result" "default template path"

# ==============================================================================
# Test: _cai_get_template_path with custom template name
# ==============================================================================

test_start "_cai_get_template_path returns custom template path"
result=$(_cai_get_template_path "my-custom-template")
expected="$HOME/.config/containai/templates/my-custom-template/Dockerfile"
assert_equal "$expected" "$result" "custom template path"

# ==============================================================================
# Test: _cai_validate_template_name accepts valid names
# ==============================================================================

test_start "_cai_validate_template_name accepts valid names (lowercase only)"
valid_names=("default" "my-template" "template_v1" "template.1" "a1b2c3")
all_passed=true
for name in "${valid_names[@]}"; do
    if ! _cai_validate_template_name "$name"; then
        test_fail "rejected valid name: $name"
        all_passed=false
        break
    fi
done
if [[ "$all_passed" == "true" ]]; then
    test_pass
fi

# ==============================================================================
# Test: _cai_validate_template_name rejects path traversal
# ==============================================================================

test_start "_cai_validate_template_name rejects path traversal"
invalid_names=("../etc" "a/b" ".." "." "/etc" "foo/bar/baz")
all_rejected=true
for name in "${invalid_names[@]}"; do
    if _cai_validate_template_name "$name" 2>/dev/null; then
        test_fail "accepted invalid name: $name"
        all_rejected=false
        break
    fi
done
if [[ "$all_rejected" == "true" ]]; then
    test_pass
fi

# ==============================================================================
# Test: _cai_validate_template_name rejects empty and invalid patterns
# ==============================================================================

test_start "_cai_validate_template_name rejects invalid patterns"
invalid_patterns=("" "_invalid" "-invalid" ".invalid" "in valid" "name@123" "Template" "UPPER" "mixedCase")
all_rejected=true
for name in "${invalid_patterns[@]}"; do
    if _cai_validate_template_name "$name" 2>/dev/null; then
        test_fail "accepted invalid pattern: '$name'"
        all_rejected=false
        break
    fi
done
if [[ "$all_rejected" == "true" ]]; then
    test_pass
fi

# ==============================================================================
# Test: _cai_get_template_path rejects invalid names
# ==============================================================================

test_start "_cai_get_template_path rejects invalid names"
if _cai_get_template_path "../etc" 2>/dev/null; then
    test_fail "accepted path traversal"
else
    test_pass
fi

# ==============================================================================
# Test: _cai_ensure_template_dir creates base directory
# ==============================================================================

test_start "_cai_ensure_template_dir creates base directory"
setup_tmpdir
# Override _CAI_TEMPLATE_DIR for this test
_CAI_TEMPLATE_DIR="$TEST_TMPDIR/templates"
_cai_ensure_template_dir
if [[ -d "$TEST_TMPDIR/templates" ]]; then
    test_pass
else
    test_fail "directory not created"
fi
teardown_tmpdir

# ==============================================================================
# Test: _cai_ensure_template_dir creates named template directory
# ==============================================================================

test_start "_cai_ensure_template_dir creates named template directory"
setup_tmpdir
_CAI_TEMPLATE_DIR="$TEST_TMPDIR/templates"
_cai_ensure_template_dir "mytest"
if [[ -d "$TEST_TMPDIR/templates/mytest" ]]; then
    test_pass
else
    test_fail "named directory not created"
fi
teardown_tmpdir

# ==============================================================================
# Test: _cai_ensure_template_dir rejects invalid names
# ==============================================================================

test_start "_cai_ensure_template_dir rejects invalid names"
setup_tmpdir
_CAI_TEMPLATE_DIR="$TEST_TMPDIR/templates"
if _cai_ensure_template_dir "../escape" 2>/dev/null; then
    test_fail "accepted path traversal"
else
    test_pass
fi
teardown_tmpdir

# ==============================================================================
# Test: _cai_template_exists returns false for non-existent template
# ==============================================================================

test_start "_cai_template_exists returns false for non-existent"
setup_tmpdir
_CAI_TEMPLATE_DIR="$TEST_TMPDIR/templates"
if _cai_template_exists "nonexistent"; then
    test_fail "returned true for non-existent"
else
    test_pass
fi
teardown_tmpdir

# ==============================================================================
# Test: _cai_template_exists returns true for existing template
# ==============================================================================

test_start "_cai_template_exists returns true for existing template"
setup_tmpdir
_CAI_TEMPLATE_DIR="$TEST_TMPDIR/templates"
mkdir -p "$TEST_TMPDIR/templates/existing"
printf '%s\n' "FROM scratch" > "$TEST_TMPDIR/templates/existing/Dockerfile"
if _cai_template_exists "existing"; then
    test_pass
else
    test_fail "returned false for existing template"
fi
teardown_tmpdir

# ==============================================================================
# Test: _cai_template_exists rejects invalid names
# ==============================================================================

test_start "_cai_template_exists rejects invalid names"
if _cai_template_exists "../etc" 2>/dev/null; then
    test_fail "accepted path traversal"
else
    test_pass
fi

# ==============================================================================
# Test: _cai_get_repo_templates_dir returns valid path
# ==============================================================================

test_start "_cai_get_repo_templates_dir returns repo templates directory"
result=$(_cai_get_repo_templates_dir)
if [[ -d "$result" ]]; then
    test_pass
else
    test_fail "directory does not exist: $result"
fi

# ==============================================================================
# Test: _cai_get_repo_templates_dir contains expected files
# ==============================================================================

test_start "_cai_get_repo_templates_dir contains default.Dockerfile"
repo_dir=$(_cai_get_repo_templates_dir)
if [[ -f "$repo_dir/default.Dockerfile" ]]; then
    test_pass
else
    test_fail "default.Dockerfile not found in $repo_dir"
fi

test_start "_cai_get_repo_templates_dir contains example-ml.Dockerfile"
repo_dir=$(_cai_get_repo_templates_dir)
if [[ -f "$repo_dir/example-ml.Dockerfile" ]]; then
    test_pass
else
    test_fail "example-ml.Dockerfile not found in $repo_dir"
fi

# ==============================================================================
# Test: _cai_install_template installs to correct location
# ==============================================================================

test_start "_cai_install_template installs default template"
setup_tmpdir
_CAI_TEMPLATE_DIR="$TEST_TMPDIR/templates"
if _cai_install_template "default" "false" >/dev/null 2>&1; then
    if [[ -f "$TEST_TMPDIR/templates/default/Dockerfile" ]]; then
        test_pass
    else
        test_fail "template file not created"
    fi
else
    test_fail "install returned failure"
fi
teardown_tmpdir

# ==============================================================================
# Test: _cai_install_template skips existing template
# ==============================================================================

test_start "_cai_install_template skips existing template"
setup_tmpdir
_CAI_TEMPLATE_DIR="$TEST_TMPDIR/templates"
mkdir -p "$TEST_TMPDIR/templates/default"
printf '%s\n' "USER CUSTOMIZED CONTENT" > "$TEST_TMPDIR/templates/default/Dockerfile"
_cai_install_template "default" "false" >/dev/null 2>&1
# Verify content was NOT overwritten
if grep -q "USER CUSTOMIZED CONTENT" "$TEST_TMPDIR/templates/default/Dockerfile"; then
    test_pass
else
    test_fail "existing template was overwritten"
fi
teardown_tmpdir

# ==============================================================================
# Test: _cai_install_template rejects non-repo template
# ==============================================================================

test_start "_cai_install_template rejects non-repo template"
setup_tmpdir
_CAI_TEMPLATE_DIR="$TEST_TMPDIR/templates"
if _cai_install_template "not-a-repo-template" "false" 2>/dev/null; then
    test_fail "accepted non-repo template name"
else
    test_pass
fi
teardown_tmpdir

# ==============================================================================
# Test: _cai_install_template dry-run does not create file
# ==============================================================================

test_start "_cai_install_template dry-run does not create file"
setup_tmpdir
_CAI_TEMPLATE_DIR="$TEST_TMPDIR/templates"
_cai_install_template "default" "true" >/dev/null 2>&1
if [[ -f "$TEST_TMPDIR/templates/default/Dockerfile" ]]; then
    test_fail "file created during dry-run"
else
    test_pass
fi
teardown_tmpdir

# ==============================================================================
# Test: _cai_install_all_templates installs both templates
# ==============================================================================

test_start "_cai_install_all_templates installs all repo templates"
setup_tmpdir
_CAI_TEMPLATE_DIR="$TEST_TMPDIR/templates"
if _cai_install_all_templates "false" >/dev/null 2>&1; then
    if [[ -f "$TEST_TMPDIR/templates/default/Dockerfile" ]] && \
       [[ -f "$TEST_TMPDIR/templates/example-ml/Dockerfile" ]]; then
        test_pass
    else
        test_fail "not all templates installed"
    fi
else
    test_fail "install_all returned failure"
fi
teardown_tmpdir

# ==============================================================================
# Test: _cai_ensure_default_templates installs missing templates
# ==============================================================================

test_start "_cai_ensure_default_templates installs missing templates"
setup_tmpdir
_CAI_TEMPLATE_DIR="$TEST_TMPDIR/templates"
_cai_ensure_default_templates "false" >/dev/null 2>&1
if [[ -f "$TEST_TMPDIR/templates/default/Dockerfile" ]] && \
   [[ -f "$TEST_TMPDIR/templates/example-ml/Dockerfile" ]]; then
    test_pass
else
    test_fail "templates not installed"
fi
teardown_tmpdir

# ==============================================================================
# Test: _cai_ensure_default_templates skips existing templates
# ==============================================================================

test_start "_cai_ensure_default_templates skips existing templates"
setup_tmpdir
_CAI_TEMPLATE_DIR="$TEST_TMPDIR/templates"
mkdir -p "$TEST_TMPDIR/templates/default"
printf '%s\n' "CUSTOM CONTENT" > "$TEST_TMPDIR/templates/default/Dockerfile"
_cai_ensure_default_templates "false" >/dev/null 2>&1
# Verify default was NOT overwritten
if grep -q "CUSTOM CONTENT" "$TEST_TMPDIR/templates/default/Dockerfile"; then
    # And example-ml should be installed
    if [[ -f "$TEST_TMPDIR/templates/example-ml/Dockerfile" ]]; then
        test_pass
    else
        test_fail "example-ml template not installed"
    fi
else
    test_fail "existing template was overwritten"
fi
teardown_tmpdir

# ==============================================================================
# Test: _cai_ensure_default_templates returns non-zero on failure
# ==============================================================================

test_start "_cai_ensure_default_templates returns non-zero when templates cannot be installed"
setup_tmpdir
# Point _CAI_TEMPLATE_DIR at a regular file (not directory) to force mkdir -p failure
printf '%s\n' "not a directory" > "$TEST_TMPDIR/templates"
_CAI_TEMPLATE_DIR="$TEST_TMPDIR/templates"
if _cai_ensure_default_templates "false" 2>/dev/null; then
    test_fail "returned success when install should fail"
else
    test_pass
fi
teardown_tmpdir

# ==============================================================================
# Test: _cai_template_exists_or_install auto-installs repo templates
# ==============================================================================

test_start "_cai_template_exists_or_install auto-installs missing default template"
setup_tmpdir
_CAI_TEMPLATE_DIR="$TEST_TMPDIR/templates"
if _cai_template_exists_or_install "default" 2>/dev/null; then
    if [[ -f "$TEST_TMPDIR/templates/default/Dockerfile" ]]; then
        test_pass
    else
        test_fail "template file not created"
    fi
else
    test_fail "returned failure"
fi
teardown_tmpdir

test_start "_cai_template_exists_or_install auto-installs missing example-ml template"
setup_tmpdir
_CAI_TEMPLATE_DIR="$TEST_TMPDIR/templates"
if _cai_template_exists_or_install "example-ml" 2>/dev/null; then
    if [[ -f "$TEST_TMPDIR/templates/example-ml/Dockerfile" ]]; then
        test_pass
    else
        test_fail "template file not created"
    fi
else
    test_fail "returned failure"
fi
teardown_tmpdir

test_start "_cai_template_exists_or_install returns false for non-repo template"
setup_tmpdir
_CAI_TEMPLATE_DIR="$TEST_TMPDIR/templates"
if _cai_template_exists_or_install "custom-not-repo" 2>/dev/null; then
    test_fail "should have failed for non-repo template"
else
    test_pass
fi
teardown_tmpdir

# ==============================================================================
# Test: _cai_require_template installs missing repo template
# ==============================================================================

test_start "_cai_require_template auto-installs missing repo template"
setup_tmpdir
_CAI_TEMPLATE_DIR="$TEST_TMPDIR/templates"
result=$(_cai_require_template "default" "false" 2>/dev/null)
if [[ -f "$TEST_TMPDIR/templates/default/Dockerfile" ]]; then
    if [[ "$result" == "$TEST_TMPDIR/templates/default/Dockerfile" ]]; then
        test_pass
    else
        test_fail "returned wrong path: $result"
    fi
else
    test_fail "template not installed"
fi
teardown_tmpdir

# ==============================================================================
# Test: _cai_require_template returns existing template path
# ==============================================================================

test_start "_cai_require_template returns path for existing template"
setup_tmpdir
_CAI_TEMPLATE_DIR="$TEST_TMPDIR/templates"
mkdir -p "$TEST_TMPDIR/templates/default"
printf '%s\n' "FROM scratch" > "$TEST_TMPDIR/templates/default/Dockerfile"
result=$(_cai_require_template "default" "false" 2>/dev/null)
if [[ "$result" == "$TEST_TMPDIR/templates/default/Dockerfile" ]]; then
    test_pass
else
    test_fail "wrong path: $result"
fi
teardown_tmpdir

# ==============================================================================
# Test: _cai_require_template fails for non-repo template that doesn't exist
# ==============================================================================

test_start "_cai_require_template fails for unknown template"
setup_tmpdir
_CAI_TEMPLATE_DIR="$TEST_TMPDIR/templates"
if _cai_require_template "unknown-custom-template" "false" 2>/dev/null; then
    test_fail "should have failed for unknown template"
else
    test_pass
fi
teardown_tmpdir

# ==============================================================================
# Test: _cai_validate_template_base validates ContainAI base images
# ==============================================================================

test_start "_cai_validate_template_base accepts ghcr.io/novotnyllc/containai:latest"
setup_tmpdir
cat > "$TEST_TMPDIR/Dockerfile" <<'EOF'
FROM ghcr.io/novotnyllc/containai:latest
RUN echo "test"
EOF
if _cai_validate_template_base "$TEST_TMPDIR/Dockerfile" "false" 2>/dev/null; then
    test_pass
else
    test_fail "rejected valid ContainAI base"
fi
teardown_tmpdir

test_start "_cai_validate_template_base accepts containai:latest"
setup_tmpdir
cat > "$TEST_TMPDIR/Dockerfile" <<'EOF'
FROM containai:latest
EOF
if _cai_validate_template_base "$TEST_TMPDIR/Dockerfile" "false" 2>/dev/null; then
    test_pass
else
    test_fail "rejected valid containai base"
fi
teardown_tmpdir

test_start "_cai_validate_template_base accepts containai-template-custom:local"
setup_tmpdir
cat > "$TEST_TMPDIR/Dockerfile" <<'EOF'
FROM containai-template-custom:local
EOF
if _cai_validate_template_base "$TEST_TMPDIR/Dockerfile" "false" 2>/dev/null; then
    test_pass
else
    test_fail "rejected valid chained template base"
fi
teardown_tmpdir

test_start "_cai_validate_template_base rejects ubuntu:latest"
setup_tmpdir
cat > "$TEST_TMPDIR/Dockerfile" <<'EOF'
FROM ubuntu:latest
EOF
if _cai_validate_template_base "$TEST_TMPDIR/Dockerfile" "true" 2>/dev/null; then
    test_fail "accepted invalid base image"
else
    test_pass
fi
teardown_tmpdir

test_start "_cai_validate_template_base emits warning for invalid base"
setup_tmpdir
cat > "$TEST_TMPDIR/Dockerfile" <<'EOF'
FROM debian:bookworm
EOF
output=$(_cai_validate_template_base "$TEST_TMPDIR/Dockerfile" "false" 2>&1) || true
if [[ "$output" == *"not based on ContainAI"* ]]; then
    test_pass
else
    test_fail "warning not emitted"
fi
teardown_tmpdir

test_start "_cai_validate_template_base suppresses warning when asked"
setup_tmpdir
cat > "$TEST_TMPDIR/Dockerfile" <<'EOF'
FROM ubuntu:latest
EOF
output=$(_cai_validate_template_base "$TEST_TMPDIR/Dockerfile" "true" 2>&1) || true
if [[ "$output" == "" ]]; then
    test_pass
else
    test_fail "warning should be suppressed but got: $output"
fi
teardown_tmpdir

test_start "_cai_validate_template_base handles ARG substitution"
setup_tmpdir
cat > "$TEST_TMPDIR/Dockerfile" <<'EOF'
ARG BASE_IMAGE=ghcr.io/novotnyllc/containai:latest
FROM $BASE_IMAGE
EOF
if _cai_validate_template_base "$TEST_TMPDIR/Dockerfile" "false" 2>/dev/null; then
    test_pass
else
    test_fail "failed to substitute ARG variable"
fi
teardown_tmpdir

test_start "_cai_validate_template_base handles \${VAR} syntax"
setup_tmpdir
cat > "$TEST_TMPDIR/Dockerfile" <<'EOF'
ARG IMAGE=ghcr.io/novotnyllc/containai
ARG TAG=latest
FROM ${IMAGE}:${TAG}
EOF
if _cai_validate_template_base "$TEST_TMPDIR/Dockerfile" "false" 2>/dev/null; then
    test_pass
else
    test_fail "failed to substitute \${VAR} syntax"
fi
teardown_tmpdir

test_start "_cai_validate_template_base warns on unresolved variable"
setup_tmpdir
cat > "$TEST_TMPDIR/Dockerfile" <<'EOF'
FROM $UNDEFINED_VAR
EOF
output=$(_cai_validate_template_base "$TEST_TMPDIR/Dockerfile" "false" 2>&1) || true
if [[ "$output" == *"unresolved variable"* ]]; then
    test_pass
else
    test_fail "should warn about unresolved variable, got: $output"
fi
teardown_tmpdir

test_start "_cai_validate_template_base handles \${VAR:-default} syntax"
setup_tmpdir
cat > "$TEST_TMPDIR/Dockerfile" <<'EOF'
FROM ${IMAGE:-ghcr.io/novotnyllc/containai:latest}
EOF
if _cai_validate_template_base "$TEST_TMPDIR/Dockerfile" "false" 2>/dev/null; then
    test_pass
else
    test_fail "failed to handle \${VAR:-default} syntax"
fi
teardown_tmpdir

test_start "_cai_validate_template_base handles ARG override of \${VAR:-default}"
setup_tmpdir
cat > "$TEST_TMPDIR/Dockerfile" <<'EOF'
ARG IMAGE=containai:v2
FROM ${IMAGE:-ghcr.io/novotnyllc/containai:latest}
EOF
if _cai_validate_template_base "$TEST_TMPDIR/Dockerfile" "false" 2>/dev/null; then
    test_pass
else
    test_fail "failed to override default with ARG"
fi
teardown_tmpdir

test_start "_cai_validate_template_base returns error for missing file"
if _cai_validate_template_base "/nonexistent/path/Dockerfile" "false" 2>/dev/null; then
    test_fail "should fail for missing file"
else
    test_pass
fi

test_start "_cai_validate_template_base returns error for missing FROM"
setup_tmpdir
cat > "$TEST_TMPDIR/Dockerfile" <<'EOF'
# No FROM line in this file
RUN echo "test"
EOF
if _cai_validate_template_base "$TEST_TMPDIR/Dockerfile" "false" 2>/dev/null; then
    test_fail "should fail for missing FROM"
else
    test_pass
fi
teardown_tmpdir

test_start "_cai_validate_template_base warning includes entrypoint note"
setup_tmpdir
cat > "$TEST_TMPDIR/Dockerfile" <<'EOF'
FROM alpine:latest
EOF
output=$(_cai_validate_template_base "$TEST_TMPDIR/Dockerfile" "false" 2>&1) || true
if [[ "$output" == *"ENTRYPOINT must not be overridden"* ]]; then
    test_pass
else
    test_fail "warning should mention entrypoint, got: $output"
fi
teardown_tmpdir

test_start "_cai_validate_template_base warning includes suppression hint"
setup_tmpdir
cat > "$TEST_TMPDIR/Dockerfile" <<'EOF'
FROM nginx:latest
EOF
output=$(_cai_validate_template_base "$TEST_TMPDIR/Dockerfile" "false" 2>&1) || true
if [[ "$output" == *"suppress_base_warning"* ]]; then
    test_pass
else
    test_fail "warning should include suppression hint, got: $output"
fi
teardown_tmpdir

test_start "_cai_validate_template_base handles --platform flag"
setup_tmpdir
cat > "$TEST_TMPDIR/Dockerfile" <<'EOF'
FROM --platform=linux/amd64 ghcr.io/novotnyllc/containai:latest
EOF
if _cai_validate_template_base "$TEST_TMPDIR/Dockerfile" "false" 2>/dev/null; then
    test_pass
else
    test_fail "failed to handle --platform flag"
fi
teardown_tmpdir

test_start "_cai_validate_template_base handles FROM ... AS stage"
setup_tmpdir
cat > "$TEST_TMPDIR/Dockerfile" <<'EOF'
FROM ghcr.io/novotnyllc/containai:latest AS builder
EOF
if _cai_validate_template_base "$TEST_TMPDIR/Dockerfile" "false" 2>/dev/null; then
    test_pass
else
    test_fail "failed to handle AS stage"
fi
teardown_tmpdir

test_start "_cai_validate_template_base handles --platform and AS together"
setup_tmpdir
cat > "$TEST_TMPDIR/Dockerfile" <<'EOF'
FROM --platform=linux/arm64 containai:v2 AS runtime
EOF
if _cai_validate_template_base "$TEST_TMPDIR/Dockerfile" "false" 2>/dev/null; then
    test_pass
else
    test_fail "failed to handle --platform with AS"
fi
teardown_tmpdir

# ==============================================================================
# Test: _containai_parse_config extracts [template].suppress_base_warning
# ==============================================================================

test_start "_containai_parse_config parses [template].suppress_base_warning = true"
setup_tmpdir
mkdir -p "$TEST_TMPDIR/workspace"
cat > "$TEST_TMPDIR/config.toml" <<'EOF'
[template]
suppress_base_warning = true
EOF
_CAI_TEMPLATE_SUPPRESS_BASE_WARNING=""
if _containai_parse_config "$TEST_TMPDIR/config.toml" "$TEST_TMPDIR/workspace" 2>/dev/null; then
    if [[ "$_CAI_TEMPLATE_SUPPRESS_BASE_WARNING" == "true" ]]; then
        test_pass
    else
        test_fail "expected 'true', got '$_CAI_TEMPLATE_SUPPRESS_BASE_WARNING'"
    fi
else
    test_fail "parse_config failed"
fi
teardown_tmpdir

test_start "_containai_parse_config parses [template].suppress_base_warning = false"
setup_tmpdir
mkdir -p "$TEST_TMPDIR/workspace"
cat > "$TEST_TMPDIR/config.toml" <<'EOF'
[template]
suppress_base_warning = false
EOF
_CAI_TEMPLATE_SUPPRESS_BASE_WARNING=""
if _containai_parse_config "$TEST_TMPDIR/config.toml" "$TEST_TMPDIR/workspace" 2>/dev/null; then
    if [[ "$_CAI_TEMPLATE_SUPPRESS_BASE_WARNING" == "" ]]; then
        test_pass
    else
        test_fail "expected empty, got '$_CAI_TEMPLATE_SUPPRESS_BASE_WARNING'"
    fi
else
    test_fail "parse_config failed"
fi
teardown_tmpdir

test_start "_containai_parse_config handles [template].suppress_base_warning = 1"
setup_tmpdir
mkdir -p "$TEST_TMPDIR/workspace"
cat > "$TEST_TMPDIR/config.toml" <<'EOF'
[template]
suppress_base_warning = 1
EOF
_CAI_TEMPLATE_SUPPRESS_BASE_WARNING=""
if _containai_parse_config "$TEST_TMPDIR/config.toml" "$TEST_TMPDIR/workspace" 2>/dev/null; then
    if [[ "$_CAI_TEMPLATE_SUPPRESS_BASE_WARNING" == "true" ]]; then
        test_pass
    else
        test_fail "expected 'true' for value 1, got '$_CAI_TEMPLATE_SUPPRESS_BASE_WARNING'"
    fi
else
    test_fail "parse_config failed"
fi
teardown_tmpdir

test_start "_containai_parse_config handles [template].suppress_base_warning = 0"
setup_tmpdir
mkdir -p "$TEST_TMPDIR/workspace"
cat > "$TEST_TMPDIR/config.toml" <<'EOF'
[template]
suppress_base_warning = 0
EOF
_CAI_TEMPLATE_SUPPRESS_BASE_WARNING=""
if _containai_parse_config "$TEST_TMPDIR/config.toml" "$TEST_TMPDIR/workspace" 2>/dev/null; then
    if [[ "$_CAI_TEMPLATE_SUPPRESS_BASE_WARNING" == "" ]]; then
        test_pass
    else
        test_fail "expected empty for value 0, got '$_CAI_TEMPLATE_SUPPRESS_BASE_WARNING'"
    fi
else
    test_fail "parse_config failed"
fi
teardown_tmpdir

test_start "_containai_parse_config handles missing [template] section"
setup_tmpdir
mkdir -p "$TEST_TMPDIR/workspace"
cat > "$TEST_TMPDIR/config.toml" <<'EOF'
[agent]
default = "claude"
EOF
_CAI_TEMPLATE_SUPPRESS_BASE_WARNING=""
if _containai_parse_config "$TEST_TMPDIR/config.toml" "$TEST_TMPDIR/workspace" 2>/dev/null; then
    if [[ "$_CAI_TEMPLATE_SUPPRESS_BASE_WARNING" == "" ]]; then
        test_pass
    else
        test_fail "expected empty for missing section, got '$_CAI_TEMPLATE_SUPPRESS_BASE_WARNING'"
    fi
else
    test_fail "parse_config failed"
fi
teardown_tmpdir

# ==============================================================================
# Summary
# ==============================================================================

printf '\n==========================================\n'
printf 'Tests run: %s\n' "$TESTS_RUN"
printf 'Passed:    %s\n' "$TESTS_PASSED"
printf 'Failed:    %s\n' "$TESTS_FAILED"
printf '==========================================\n'

if [[ "$TESTS_FAILED" -gt 0 ]]; then
    exit 1
fi
