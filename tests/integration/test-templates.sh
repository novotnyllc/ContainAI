#!/usr/bin/env bash
# ==============================================================================
# Integration tests for ContainAI User Templates
# ==============================================================================
# Verifies:
# 1. Template files exist in repo (src/templates/)
# 2. Template installation during setup
# 3. First-use auto-installation of missing templates
# 4. Template validation (basic existence and syntax)
# 5. Template directory structure at ~/.config/containai/templates/
#
# Prerequisites:
# - Docker daemon running (for build tests)
# - containai.sh sourced
#
# Usage:
#   ./tests/integration/test-templates.sh
#
# Environment Variables:
#   SKIP_DOCKER_TESTS - Set to "1" to skip tests requiring Docker daemon
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
SRC_DIR="$REPO_ROOT/src"

# Check if Docker is available (used for Docker-dependent tests)
DOCKER_AVAILABLE=0
if command -v docker >/dev/null 2>&1; then
    DOCKER_AVAILABLE=1
fi

# Source containai library for template functions and constants
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
skip() { printf '%s\n' "[SKIP] $*"; }
warn() { printf '%s\n' "[WARN] $*"; }
info() { printf '%s\n' "[INFO] $*"; }
section() {
    printf '\n'
    printf '%s\n' "=== $* ==="
}

FAILED=0

# Context name for sysbox containers - use from lib/docker.sh (sourced via containai.sh)
CONTEXT_NAME="${_CAI_CONTAINAI_DOCKER_CONTEXT:-containai-docker}"

# Test run ID for unique resource names
TEST_RUN_ID="template-test-$$-$(date +%s)"

# Original template directory for backup/restore
ORIGINAL_TEMPLATE_DIR="$_CAI_TEMPLATE_DIR"

# Test template directory (isolated from real user config)
TEST_TEMPLATE_DIR="/tmp/$TEST_RUN_ID/templates"

# Track if we should restore template dir
TEMPLATE_DIR_OVERRIDDEN=0

# Cleanup function
cleanup() {
    info "Cleaning up test resources..."

    # Restore original template directory
    if [[ $TEMPLATE_DIR_OVERRIDDEN -eq 1 ]]; then
        _CAI_TEMPLATE_DIR="$ORIGINAL_TEMPLATE_DIR"
    fi

    # Remove test directories
    if [[ -d "/tmp/$TEST_RUN_ID" ]]; then
        rm -rf "/tmp/$TEST_RUN_ID" 2>/dev/null || true
    fi
}

trap cleanup EXIT

# ==============================================================================
# Test 1: Template files exist in repo
# ==============================================================================
test_repo_template_files() {
    section "Test 1: Template files exist in repo"

    local templates_dir="$SRC_DIR/templates"

    # Check templates directory exists
    if [[ ! -d "$templates_dir" ]]; then
        fail "Templates directory not found: $templates_dir"
        return
    fi
    pass "Templates directory exists: $templates_dir"

    # Check default.Dockerfile
    if [[ ! -f "$templates_dir/default.Dockerfile" ]]; then
        fail "Default template not found: $templates_dir/default.Dockerfile"
    else
        pass "Default template exists: default.Dockerfile"

        # Verify FROM line exists
        if grep -q "^FROM" "$templates_dir/default.Dockerfile"; then
            pass "Default template has FROM line"
        else
            fail "Default template missing FROM line"
        fi

        # Verify ContainAI base image reference
        if grep -q "ghcr.io/novotnyllc/containai" "$templates_dir/default.Dockerfile"; then
            pass "Default template references ContainAI image"
        else
            fail "Default template does not reference ContainAI image"
        fi

        # Check for required warnings about ENTRYPOINT
        if grep -qi "ENTRYPOINT" "$templates_dir/default.Dockerfile"; then
            pass "Default template mentions ENTRYPOINT warning"
        else
            fail "Default template missing ENTRYPOINT warning"
        fi
    fi

    # Check example-ml.Dockerfile
    if [[ ! -f "$templates_dir/example-ml.Dockerfile" ]]; then
        fail "Example ML template not found: $templates_dir/example-ml.Dockerfile"
    else
        pass "Example ML template exists: example-ml.Dockerfile"

        # Verify FROM line exists
        if grep -q "^FROM" "$templates_dir/example-ml.Dockerfile"; then
            pass "Example ML template has FROM line"
        else
            fail "Example ML template missing FROM line"
        fi
    fi
}

# ==============================================================================
# Test 2: Template directory structure helpers
# ==============================================================================
test_template_directory_helpers() {
    section "Test 2: Template directory structure helpers"

    # Override template dir for testing
    _CAI_TEMPLATE_DIR="$TEST_TEMPLATE_DIR"
    TEMPLATE_DIR_OVERRIDDEN=1

    # Test _cai_get_template_dir
    local template_dir
    template_dir=$(_cai_get_template_dir)
    if [[ "$template_dir" == "$TEST_TEMPLATE_DIR" ]]; then
        pass "_cai_get_template_dir returns correct path"
    else
        fail "_cai_get_template_dir returned: $template_dir (expected: $TEST_TEMPLATE_DIR)"
    fi

    # Test _cai_ensure_template_dir creates directory
    if _cai_ensure_template_dir; then
        if [[ -d "$TEST_TEMPLATE_DIR" ]]; then
            pass "_cai_ensure_template_dir creates base directory"
        else
            fail "_cai_ensure_template_dir did not create directory"
        fi
    else
        fail "_cai_ensure_template_dir failed"
    fi

    # Test _cai_ensure_template_dir with template name
    if _cai_ensure_template_dir "test-template"; then
        if [[ -d "$TEST_TEMPLATE_DIR/test-template" ]]; then
            pass "_cai_ensure_template_dir creates template subdirectory"
        else
            fail "_cai_ensure_template_dir did not create template subdirectory"
        fi
    else
        fail "_cai_ensure_template_dir with name failed"
    fi

    # Test _cai_get_template_path
    local template_path
    template_path=$(_cai_get_template_path "default")
    if [[ "$template_path" == "$TEST_TEMPLATE_DIR/default/Dockerfile" ]]; then
        pass "_cai_get_template_path returns correct path"
    else
        fail "_cai_get_template_path returned: $template_path"
    fi
}

# ==============================================================================
# Test 3: Template name validation
# ==============================================================================
test_template_name_validation() {
    section "Test 3: Template name validation"

    # Valid names
    local valid_names=("default" "my-template" "template123" "My.Template" "template_v2")
    local name
    for name in "${valid_names[@]}"; do
        if _cai_validate_template_name "$name"; then
            pass "Valid name accepted: $name"
        else
            fail "Valid name rejected: $name"
        fi
    done

    # Invalid names (path traversal attempts)
    local invalid_names=("../escape" "path/with/slash" ".." "." "" "-starts-with-dash")
    for name in "${invalid_names[@]}"; do
        if _cai_validate_template_name "$name" 2>/dev/null; then
            fail "Invalid name accepted: '$name'"
        else
            pass "Invalid name rejected: '$name'"
        fi
    done
}

# ==============================================================================
# Test 4: Template installation from repo
# ==============================================================================
test_template_installation() {
    section "Test 4: Template installation from repo"

    # Use fresh test directory
    rm -rf "$TEST_TEMPLATE_DIR"
    mkdir -p "$TEST_TEMPLATE_DIR"
    _CAI_TEMPLATE_DIR="$TEST_TEMPLATE_DIR"
    TEMPLATE_DIR_OVERRIDDEN=1

    # Test _cai_install_template for default
    if _cai_install_template "default"; then
        if [[ -f "$TEST_TEMPLATE_DIR/default/Dockerfile" ]]; then
            pass "Default template installed successfully"

            # Verify content matches repo
            if diff -q "$SRC_DIR/templates/default.Dockerfile" "$TEST_TEMPLATE_DIR/default/Dockerfile" >/dev/null 2>&1; then
                pass "Installed template matches repo source"
            else
                fail "Installed template differs from repo source"
            fi
        else
            fail "Default template file not created"
        fi
    else
        fail "_cai_install_template default failed"
    fi

    # Test _cai_install_template for example-ml
    if _cai_install_template "example-ml"; then
        if [[ -f "$TEST_TEMPLATE_DIR/example-ml/Dockerfile" ]]; then
            pass "Example-ml template installed successfully"
        else
            fail "Example-ml template file not created"
        fi
    else
        fail "_cai_install_template example-ml failed"
    fi

    # Test that re-installation skips existing (preserves customizations)
    printf '%s\n' "# User customization" >> "$TEST_TEMPLATE_DIR/default/Dockerfile"
    if _cai_install_template "default"; then
        if grep -q "User customization" "$TEST_TEMPLATE_DIR/default/Dockerfile"; then
            pass "Re-installation preserves existing template"
        else
            fail "Re-installation overwrote existing template"
        fi
    else
        fail "_cai_install_template re-run failed"
    fi

    # Test _cai_install_template for non-repo template fails
    local install_output
    if install_output=$(_cai_install_template "user-custom" 2>&1); then
        fail "Non-repo template installation should fail"
    else
        pass "Non-repo template installation correctly rejected"
    fi
}

# ==============================================================================
# Test 5: Template existence checks
# ==============================================================================
test_template_existence() {
    section "Test 5: Template existence checks"

    # Use fresh test directory with default installed
    rm -rf "$TEST_TEMPLATE_DIR"
    mkdir -p "$TEST_TEMPLATE_DIR/default"
    cp "$SRC_DIR/templates/default.Dockerfile" "$TEST_TEMPLATE_DIR/default/Dockerfile"
    _CAI_TEMPLATE_DIR="$TEST_TEMPLATE_DIR"
    TEMPLATE_DIR_OVERRIDDEN=1

    # Test _cai_template_exists for existing template
    if _cai_template_exists "default"; then
        pass "_cai_template_exists returns true for existing template"
    else
        fail "_cai_template_exists returns false for existing template"
    fi

    # Test _cai_template_exists for non-existing template
    if _cai_template_exists "nonexistent" 2>/dev/null; then
        fail "_cai_template_exists returns true for non-existing template"
    else
        pass "_cai_template_exists returns false for non-existing template"
    fi
}

# ==============================================================================
# Test 6: First-use auto-installation
# ==============================================================================
test_first_use_auto_install() {
    section "Test 6: First-use auto-installation"

    # Use fresh empty test directory
    rm -rf "$TEST_TEMPLATE_DIR"
    mkdir -p "$TEST_TEMPLATE_DIR"
    _CAI_TEMPLATE_DIR="$TEST_TEMPLATE_DIR"
    TEMPLATE_DIR_OVERRIDDEN=1

    # Verify template doesn't exist yet
    if [[ -f "$TEST_TEMPLATE_DIR/default/Dockerfile" ]]; then
        fail "Test setup error: default template already exists"
        return
    fi
    pass "Verified default template does not exist initially"

    # Test _cai_template_exists_or_install triggers auto-install for repo template
    if _cai_template_exists_or_install "default"; then
        if [[ -f "$TEST_TEMPLATE_DIR/default/Dockerfile" ]]; then
            pass "First-use auto-installed default template"
        else
            fail "First-use returned success but template not installed"
        fi
    else
        fail "_cai_template_exists_or_install failed for default"
    fi

    # Test _cai_template_exists_or_install fails for non-repo template
    if _cai_template_exists_or_install "user-custom" 2>/dev/null; then
        fail "_cai_template_exists_or_install should fail for non-repo template"
    else
        pass "_cai_template_exists_or_install correctly fails for non-repo template"
    fi
}

# ==============================================================================
# Test 7: _cai_require_template with auto-install
# ==============================================================================
test_require_template() {
    section "Test 7: _cai_require_template with auto-install"

    # Use fresh empty test directory
    rm -rf "$TEST_TEMPLATE_DIR"
    mkdir -p "$TEST_TEMPLATE_DIR"
    _CAI_TEMPLATE_DIR="$TEST_TEMPLATE_DIR"
    TEMPLATE_DIR_OVERRIDDEN=1

    # Test _cai_require_template auto-installs and returns path
    local template_path
    if template_path=$(_cai_require_template "default"); then
        if [[ "$template_path" == "$TEST_TEMPLATE_DIR/default/Dockerfile" ]]; then
            pass "_cai_require_template returns correct path"
        else
            fail "_cai_require_template returned wrong path: $template_path"
        fi

        if [[ -f "$template_path" ]]; then
            pass "_cai_require_template auto-installed template"
        else
            fail "_cai_require_template returned path but file doesn't exist"
        fi
    else
        fail "_cai_require_template failed"
    fi

    # Test _cai_require_template fails for invalid name
    if _cai_require_template "../escape" 2>/dev/null; then
        fail "_cai_require_template should fail for invalid name"
    else
        pass "_cai_require_template correctly rejects invalid name"
    fi

    # Test _cai_require_template fails for non-repo, non-existent template
    if _cai_require_template "user-custom" 2>/dev/null; then
        fail "_cai_require_template should fail for non-repo template"
    else
        pass "_cai_require_template correctly fails for non-repo template"
    fi
}

# ==============================================================================
# Test 8: Install all templates
# ==============================================================================
test_install_all_templates() {
    section "Test 8: Install all templates"

    # Use fresh empty test directory
    rm -rf "$TEST_TEMPLATE_DIR"
    mkdir -p "$TEST_TEMPLATE_DIR"
    _CAI_TEMPLATE_DIR="$TEST_TEMPLATE_DIR"
    TEMPLATE_DIR_OVERRIDDEN=1

    # Test _cai_install_all_templates
    if _cai_install_all_templates; then
        # Check all repo templates were installed
        if [[ -f "$TEST_TEMPLATE_DIR/default/Dockerfile" ]]; then
            pass "Default template installed by install_all"
        else
            fail "Default template not installed by install_all"
        fi

        if [[ -f "$TEST_TEMPLATE_DIR/example-ml/Dockerfile" ]]; then
            pass "Example-ml template installed by install_all"
        else
            fail "Example-ml template not installed by install_all"
        fi
    else
        fail "_cai_install_all_templates failed"
    fi
}

# ==============================================================================
# Test 9: Ensure default templates
# ==============================================================================
test_ensure_default_templates() {
    section "Test 9: Ensure default templates"

    # Use fresh directory with only one template
    rm -rf "$TEST_TEMPLATE_DIR"
    mkdir -p "$TEST_TEMPLATE_DIR/default"
    cp "$SRC_DIR/templates/default.Dockerfile" "$TEST_TEMPLATE_DIR/default/Dockerfile"
    _CAI_TEMPLATE_DIR="$TEST_TEMPLATE_DIR"
    TEMPLATE_DIR_OVERRIDDEN=1

    # Test _cai_ensure_default_templates fills in missing
    if _cai_ensure_default_templates; then
        # Default should still exist (not overwritten)
        if [[ -f "$TEST_TEMPLATE_DIR/default/Dockerfile" ]]; then
            pass "Default template preserved"
        else
            fail "Default template was removed"
        fi

        # example-ml should now exist
        if [[ -f "$TEST_TEMPLATE_DIR/example-ml/Dockerfile" ]]; then
            pass "Missing example-ml template was installed"
        else
            fail "Missing example-ml template was not installed"
        fi
    else
        fail "_cai_ensure_default_templates failed"
    fi
}

# ==============================================================================
# Test 10: Dry-run mode
# ==============================================================================
test_dry_run_mode() {
    section "Test 10: Dry-run mode"

    # Use fresh empty test directory
    rm -rf "$TEST_TEMPLATE_DIR"
    mkdir -p "$TEST_TEMPLATE_DIR"
    _CAI_TEMPLATE_DIR="$TEST_TEMPLATE_DIR"
    TEMPLATE_DIR_OVERRIDDEN=1

    # Test _cai_install_template with dry-run
    if _cai_install_template "default" "true"; then
        if [[ -f "$TEST_TEMPLATE_DIR/default/Dockerfile" ]]; then
            fail "Dry-run mode should not create files"
        else
            pass "Dry-run mode did not create files"
        fi
    else
        fail "_cai_install_template dry-run failed"
    fi
}

# ==============================================================================
# Test 11: Template installation via setup
# ==============================================================================
test_setup_installs_templates() {
    section "Test 11: Template installation via setup"

    # cai setup --dry-run calls docker context inspect, so skip if Docker unavailable
    if [[ "$DOCKER_AVAILABLE" -ne 1 ]]; then
        skip "Docker not available (required for setup commands)"
        return
    fi

    # This test verifies that `cai setup --dry-run` mentions template installation
    # Uses hermetic HOME to avoid polluting user config

    local test_home="/tmp/$TEST_RUN_ID/setup-test-home"
    rm -rf "$test_home"
    mkdir -p "$test_home"

    # First verify --skip-templates option exists in help (required)
    local help_output
    help_output=$(HOME="$test_home" bash -c "source '$SRC_DIR/containai.sh' && cai setup --help" 2>&1) || true
    if ! printf '%s' "$help_output" | grep -q "\-\-skip-templates"; then
        fail "Setup missing --skip-templates option in help"
        rm -rf "$test_home"
        return
    fi
    pass "Setup has --skip-templates option"

    # Run cai setup --dry-run in a subshell with overridden HOME
    # This shows what setup would do without making changes
    local setup_output setup_rc
    setup_output=$(HOME="$test_home" bash -c "source '$SRC_DIR/containai.sh' && cai setup --dry-run" 2>&1) && setup_rc=0 || setup_rc=$?

    # Check if setup mentions template installation in dry-run output
    # Use -E for extended regex (portable across BSD/GNU grep)
    if printf '%s' "$setup_output" | grep -qiE "template|Would install"; then
        pass "Setup dry-run mentions template installation"
    else
        # Dry-run may fail on platforms without Sysbox support
        # but template messages should still appear if templates are wired in
        if printf '%s' "$setup_output" | grep -qiE "skip.*template|Installed template"; then
            pass "Setup mentions templates (may have skipped or already installed)"
        else
            # Check if dry-run failed for platform-specific reasons
            if [[ $setup_rc -ne 0 ]] && printf '%s' "$setup_output" | grep -qiE "unsupported|platform|sysbox"; then
                skip "Setup dry-run failed on this platform (expected for non-Linux)"
            else
                fail "Setup dry-run did not mention templates (exit=$setup_rc)"
            fi
        fi
    fi

    # Cleanup
    rm -rf "$test_home"
}

# ==============================================================================
# Test 12: Template build (requires fn-33-lp4.4)
# ==============================================================================
test_template_build() {
    section "Test 12: Template build produces correct image tag"

    # Check if _cai_build_template exists (fn-33-lp4.4)
    if ! declare -f _cai_build_template >/dev/null 2>&1; then
        skip "Template build not implemented (fn-33-lp4.4 pending)"
        return
    fi

    # Skip if Docker not available
    if [[ "$DOCKER_AVAILABLE" -ne 1 ]]; then
        skip "Docker not available"
        return
    fi

    # Skip if Docker daemon not available
    if [[ "${SKIP_DOCKER_TESTS:-}" == "1" ]]; then
        skip "Docker tests disabled via SKIP_DOCKER_TESTS"
        return
    fi

    # Check containai-docker context exists
    if ! docker context inspect "$CONTEXT_NAME" >/dev/null 2>&1; then
        skip "Context '$CONTEXT_NAME' not found - run 'cai setup'"
        return
    fi

    # Use fresh test directory with default template
    rm -rf "$TEST_TEMPLATE_DIR"
    mkdir -p "$TEST_TEMPLATE_DIR/default"
    cp "$SRC_DIR/templates/default.Dockerfile" "$TEST_TEMPLATE_DIR/default/Dockerfile"
    _CAI_TEMPLATE_DIR="$TEST_TEMPLATE_DIR"
    TEMPLATE_DIR_OVERRIDDEN=1

    # Test template build with correct context (context name only, not --context flag)
    local build_output build_rc
    build_output=$(_cai_build_template "default" "$CONTEXT_NAME" 2>&1) && build_rc=0 || build_rc=$?

    if [[ $build_rc -eq 0 ]]; then
        pass "Template build succeeded"

        # Verify image exists with correct tag (use same context as build)
        if DOCKER_CONTEXT= DOCKER_HOST= docker --context "$CONTEXT_NAME" image inspect "containai-template-default:local" >/dev/null 2>&1; then
            pass "Template image tagged correctly: containai-template-default:local"

            # Cleanup test image
            DOCKER_CONTEXT= DOCKER_HOST= docker --context "$CONTEXT_NAME" rmi "containai-template-default:local" >/dev/null 2>&1 || true
        else
            fail "Template image not found with expected tag"
        fi
    else
        fail "Template build failed: $build_output"
    fi
}

# ==============================================================================
# Test 12b: Template build dry-run (requires fn-33-lp4.4)
# ==============================================================================
test_template_build_dry_run() {
    section "Test 12b: Template build dry-run outputs TEMPLATE_BUILD_CMD"

    # Check if _cai_build_template exists (fn-33-lp4.4)
    if ! declare -f _cai_build_template >/dev/null 2>&1; then
        skip "Template build not implemented (fn-33-lp4.4 pending)"
        return
    fi

    # Use fresh test directory with default template
    rm -rf "$TEST_TEMPLATE_DIR"
    mkdir -p "$TEST_TEMPLATE_DIR/default"
    cp "$SRC_DIR/templates/default.Dockerfile" "$TEST_TEMPLATE_DIR/default/Dockerfile"
    _CAI_TEMPLATE_DIR="$TEST_TEMPLATE_DIR"
    TEMPLATE_DIR_OVERRIDDEN=1

    # Test dry-run output format (no Docker required - just shows what would run)
    local dry_run_output dry_run_rc
    dry_run_output=$(_cai_build_template "default" "" "true" 2>&1) && dry_run_rc=0 || dry_run_rc=$?

    if [[ $dry_run_rc -eq 0 ]]; then
        pass "Template build dry-run succeeded"

        # Verify TEMPLATE_BUILD_CMD is in output
        if printf '%s' "$dry_run_output" | grep -q "^TEMPLATE_BUILD_CMD="; then
            pass "Dry-run outputs TEMPLATE_BUILD_CMD"
        else
            fail "Dry-run missing TEMPLATE_BUILD_CMD"
        fi

        # Verify TEMPLATE_IMAGE is in output
        if printf '%s' "$dry_run_output" | grep -q "^TEMPLATE_IMAGE=containai-template-default:local"; then
            pass "Dry-run outputs correct TEMPLATE_IMAGE"
        else
            fail "Dry-run missing or incorrect TEMPLATE_IMAGE"
        fi

        # Verify TEMPLATE_NAME is in output
        if printf '%s' "$dry_run_output" | grep -q "^TEMPLATE_NAME=default"; then
            pass "Dry-run outputs correct TEMPLATE_NAME"
        else
            fail "Dry-run missing or incorrect TEMPLATE_NAME"
        fi

        # Verify build command includes docker build
        if printf '%s' "$dry_run_output" | grep -q "docker build"; then
            pass "Dry-run build command includes 'docker build'"
        else
            fail "Dry-run build command missing 'docker build'"
        fi

        # Verify env var clearing prefix is included (matches actual execution)
        if printf '%s' "$dry_run_output" | grep -q "^TEMPLATE_BUILD_CMD=DOCKER_CONTEXT= DOCKER_HOST="; then
            pass "Dry-run command includes env var clearing prefix"
        else
            fail "Dry-run command missing env var clearing prefix"
        fi
    else
        fail "Template build dry-run failed: $dry_run_output"
    fi
}

# ==============================================================================
# Test 12d: Template build dry-run with context (requires fn-33-lp4.4)
# ==============================================================================
test_template_build_dry_run_with_context() {
    section "Test 12d: Template build dry-run with context"

    # Check if _cai_build_template exists (fn-33-lp4.4)
    if ! declare -f _cai_build_template >/dev/null 2>&1; then
        skip "Template build not implemented (fn-33-lp4.4 pending)"
        return
    fi

    # Use fresh test directory with default template
    rm -rf "$TEST_TEMPLATE_DIR"
    mkdir -p "$TEST_TEMPLATE_DIR/default"
    cp "$SRC_DIR/templates/default.Dockerfile" "$TEST_TEMPLATE_DIR/default/Dockerfile"
    _CAI_TEMPLATE_DIR="$TEST_TEMPLATE_DIR"
    TEMPLATE_DIR_OVERRIDDEN=1

    # Test dry-run with a context specified
    local dry_run_output dry_run_rc
    dry_run_output=$(_cai_build_template "default" "my-context" "true" 2>&1) && dry_run_rc=0 || dry_run_rc=$?

    if [[ $dry_run_rc -eq 0 ]]; then
        pass "Template build dry-run with context succeeded"

        # Verify --context flag is included in the command
        if printf '%s' "$dry_run_output" | grep -q "\-\-context.*my-context"; then
            pass "Dry-run command includes --context flag"
        else
            fail "Dry-run command missing --context flag"
        fi
    else
        fail "Template build dry-run with context failed: $dry_run_output"
    fi
}

# ==============================================================================
# Test 12c: Template image name helper (requires fn-33-lp4.4)
# ==============================================================================
test_template_image_name() {
    section "Test 12c: Template image name helper"

    # Check if _cai_get_template_image_name exists (fn-33-lp4.4)
    if ! declare -f _cai_get_template_image_name >/dev/null 2>&1; then
        skip "Template image name helper not implemented (fn-33-lp4.4 pending)"
        return
    fi

    # Test default template image name
    local image_name
    image_name=$(_cai_get_template_image_name "default")
    if [[ "$image_name" == "containai-template-default:local" ]]; then
        pass "Default template image name correct"
    else
        fail "Default template image name incorrect: $image_name"
    fi

    # Test custom template image name
    image_name=$(_cai_get_template_image_name "my-custom")
    if [[ "$image_name" == "containai-template-my-custom:local" ]]; then
        pass "Custom template image name correct"
    else
        fail "Custom template image name incorrect: $image_name"
    fi

    # Test invalid template name is rejected
    if _cai_get_template_image_name "../escape" 2>/dev/null; then
        fail "Invalid template name accepted for image name"
    else
        pass "Invalid template name rejected for image name"
    fi
}

# ==============================================================================
# Test 13: Layer validation (requires fn-33-lp4.5)
# ==============================================================================
test_layer_validation() {
    section "Test 13: Layer validation warning for non-ContainAI base"

    # Check if _cai_validate_template_base exists (fn-33-lp4.5)
    if ! declare -f _cai_validate_template_base >/dev/null 2>&1; then
        skip "Layer validation not implemented (fn-33-lp4.5 pending)"
        return
    fi

    # Use fresh test directory
    rm -rf "$TEST_TEMPLATE_DIR"
    mkdir -p "$TEST_TEMPLATE_DIR/test-ubuntu"
    _CAI_TEMPLATE_DIR="$TEST_TEMPLATE_DIR"
    TEMPLATE_DIR_OVERRIDDEN=1

    # Create template with non-ContainAI base
    cat > "$TEST_TEMPLATE_DIR/test-ubuntu/Dockerfile" << 'EOF'
FROM ubuntu:latest
RUN apt-get update
EOF

    # Test that validation emits warning (function expects Dockerfile path, not template name)
    local validation_output dockerfile_path
    dockerfile_path="$TEST_TEMPLATE_DIR/test-ubuntu/Dockerfile"
    validation_output=$(_cai_validate_template_base "$dockerfile_path" 2>&1) || true

    if printf '%s' "$validation_output" | grep -qi "not based on ContainAI"; then
        pass "Layer validation warns for non-ContainAI base"
    else
        fail "Layer validation did not warn for non-ContainAI base"
    fi

    # Test that ContainAI base passes
    mkdir -p "$TEST_TEMPLATE_DIR/test-containai"
    cat > "$TEST_TEMPLATE_DIR/test-containai/Dockerfile" << 'EOF'
FROM ghcr.io/novotnyllc/containai:latest
RUN echo "test"
EOF

    dockerfile_path="$TEST_TEMPLATE_DIR/test-containai/Dockerfile"
    validation_output=$(_cai_validate_template_base "$dockerfile_path" 2>&1) || true

    if printf '%s' "$validation_output" | grep -qi "not based on ContainAI"; then
        fail "Layer validation incorrectly warns for ContainAI base"
    else
        pass "Layer validation accepts ContainAI base"
    fi
}

# ==============================================================================
# Test 13: Doctor template detection (requires fn-33-lp4.7)
# ==============================================================================
test_doctor_template_detection() {
    section "Test 14: Doctor detection of missing template"

    # Doctor template checks are in fn-33-lp4.7
    # This test verifies doctor detects missing templates via CLI

    # Use fresh test directory with empty templates
    local test_home="/tmp/$TEST_RUN_ID/doctor-test-home"
    rm -rf "$test_home"
    mkdir -p "$test_home/.config/containai/templates"

    # Verify no default template exists in test home
    if [[ -f "$test_home/.config/containai/templates/default/Dockerfile" ]]; then
        fail "Test setup error: default template exists"
        return
    fi
    pass "Verified default template is missing for test"

    # Check if doctor has template checks implemented (fn-33-lp4.7)
    # Run cai doctor in a subshell with overridden HOME to check template detection
    local doctor_output doctor_rc
    doctor_output=$(HOME="$test_home" bash -c "source '$SRC_DIR/containai.sh' && cai doctor" 2>&1) && doctor_rc=0 || doctor_rc=$?

    # Look for template-related output in doctor (use -E for portable extended regex)
    if printf '%s' "$doctor_output" | grep -qiE "Template.*missing|Template.*not found"; then
        pass "Doctor detects missing template"
    else
        # fn-33-lp4.7 may not be implemented yet - skip if no template section
        if printf '%s' "$doctor_output" | grep -qi "template"; then
            fail "Doctor has template section but did not detect missing template"
        else
            skip "Doctor template checks not implemented (fn-33-lp4.7 pending)"
        fi
    fi

    # Cleanup
    rm -rf "$test_home"
}

# ==============================================================================
# Test 15: Doctor fix template recovery (requires fn-33-lp4.8)
# ==============================================================================
test_doctor_fix_template() {
    section "Test 15: Doctor fix template recovery"

    # This test verifies doctor fix template via CLI (fn-33-lp4.8)
    # Per spec: `cai doctor fix template` recovers default, or `cai doctor fix template <name>`
    # Use fresh test home with corrupted template
    local test_home="/tmp/$TEST_RUN_ID/doctor-fix-home"
    rm -rf "$test_home"
    mkdir -p "$test_home/.config/containai/templates/default"
    printf '%s\n' "INVALID DOCKERFILE" > "$test_home/.config/containai/templates/default/Dockerfile"

    # Try to run doctor fix template via CLI
    # Try with template name first (spec says: `cai doctor fix template [--all | <name>]`)
    local fix_output fix_rc
    fix_output=$(HOME="$test_home" bash -c "source '$SRC_DIR/containai.sh' && cai doctor fix template default" 2>&1) && fix_rc=0 || fix_rc=$?

    # Check if doctor fix template is implemented (use -E for portable extended regex)
    if printf '%s' "$fix_output" | grep -qiE "unknown.*template|not.*implemented|invalid.*argument|usage:"; then
        # Try without template name as fallback
        fix_output=$(HOME="$test_home" bash -c "source '$SRC_DIR/containai.sh' && cai doctor fix template" 2>&1) && fix_rc=0 || fix_rc=$?
        if printf '%s' "$fix_output" | grep -qiE "unknown.*template|not.*implemented|invalid.*argument|usage:"; then
            skip "Doctor fix template not implemented (fn-33-lp4.8 pending)"
            rm -rf "$test_home"
            return
        fi
    fi

    if [[ $fix_rc -eq 0 ]]; then
        # Check backup was created
        if ls "$test_home/.config/containai/templates/default/Dockerfile.backup."* >/dev/null 2>&1; then
            pass "Doctor fix created backup"
        else
            fail "Doctor fix did not create backup"
        fi

        # Check template was restored with valid FROM line
        if grep -q "^FROM" "$test_home/.config/containai/templates/default/Dockerfile"; then
            pass "Doctor fix restored valid template"
        else
            fail "Doctor fix did not restore valid template"
        fi
    else
        # Check for specific error vs not implemented (use -E for portable extended regex)
        if printf '%s' "$fix_output" | grep -qiE "fix.*template|recover"; then
            fail "Doctor fix template failed: $fix_output"
        else
            skip "Doctor fix template not implemented (fn-33-lp4.8 pending)"
        fi
    fi

    # Cleanup
    rm -rf "$test_home"
}

# ==============================================================================
# Run all tests
# ==============================================================================

printf '%s\n' "ContainAI Template Integration Tests"
printf '%s\n' "====================================="
printf '%s\n' "Test Run ID: $TEST_RUN_ID"
printf '\n'

# Run tests - implemented features
test_repo_template_files
test_template_directory_helpers
test_template_name_validation
test_template_installation
test_template_existence
test_first_use_auto_install
test_require_template
test_install_all_templates
test_ensure_default_templates
test_dry_run_mode
test_setup_installs_templates

# Run tests - pending features (will skip if not implemented)
test_template_build
test_template_build_dry_run
test_template_build_dry_run_with_context
test_template_image_name
test_layer_validation
test_doctor_template_detection
test_doctor_fix_template

# Summary
printf '\n'
printf '%s\n' "====================================="
if [[ $FAILED -eq 0 ]]; then
    printf '%s\n' "[OK] All template tests passed"
    exit 0
else
    printf '%s\n' "[FAIL] Some template tests failed"
    exit 1
fi
