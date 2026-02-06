#!/usr/bin/env bash
# Unit tests for install.sh behavior
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
INSTALLER="$REPO_ROOT/install.sh"

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

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

source_installer() {
    local temp_script
    temp_script="$(mktemp)"
    sed '/^main "\$@"$/d' "$INSTALLER" >"$temp_script"
    # shellcheck source=/dev/null
    source "$temp_script"
    rm -f "$temp_script"
}

test_detect_local_mode_source_checkout() {
    test_start "detect_local_mode recognizes source checkout layout"
    local tmpdir
    tmpdir="$(mktemp -d)"
    mkdir -p "$tmpdir/src/lib"
    : >"$tmpdir/src/containai.sh"
    : >"$tmpdir/src/lib/core.sh"

    SCRIPT_DIR="$tmpdir"
    if detect_local_mode; then
        test_pass
    else
        test_fail "expected local mode for source checkout layout"
    fi

    rm -rf "$tmpdir"
}

test_detect_os_ubuntu_mapping() {
    test_start "detect_os maps Ubuntu ID to ubuntu"
    local tmpdir os_release_path result
    tmpdir="$(mktemp -d)"
    os_release_path="$tmpdir/os-release"

    cat >"$os_release_path" <<'EOF'
ID=ubuntu
EOF

    CAI_OS_RELEASE_FILE="$os_release_path"
    uname() {
        if [[ "${1:-}" == "-s" ]]; then
            printf '%s\n' "Linux"
        else
            command uname "$@"
        fi
    }

    result="$(detect_os)"

    unset -f uname
    unset CAI_OS_RELEASE_FILE
    rm -rf "$tmpdir"

    if [[ "$result" == "ubuntu" ]]; then
        test_pass
    else
        test_fail "expected ubuntu, got '$result'"
    fi
}

test_check_docker_context_fallback() {
    test_start "check_docker accepts containai-docker context when default daemon is unavailable"
    local tmpdir orig_path output
    tmpdir="$(mktemp -d)"
    orig_path="$PATH"
    mkdir -p "$tmpdir/bin"

    cat >"$tmpdir/bin/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "--version" ]]; then
    printf '%s\n' "Docker version 29.0.0, build test"
    exit 0
fi

if [[ "${1:-}" == "info" ]]; then
    # check_docker should not probe the default/current context
    printf 'called\n' >> "__DEFAULT_INFO_PROBE__"
    exit 1
fi

if [[ "${1:-}" == "context" && "${2:-}" == "inspect" && "${3:-}" == "containai-docker" ]]; then
    # containai-docker context exists
    exit 0
fi

if [[ "${1:-}" == "--context" && "${2:-}" == "containai-docker" && "${3:-}" == "info" ]]; then
    # containai-docker context daemon is reachable
    exit 0
fi

exit 1
EOF
    chmod +x "$tmpdir/bin/docker"
    sed -i "s|__DEFAULT_INFO_PROBE__|$tmpdir/default-info-probe.log|g" "$tmpdir/bin/docker"

    PATH="$tmpdir/bin:$orig_path"
    output="$(check_docker 2>&1 || true)"
    PATH="$orig_path"
    local probed_default="false"
    if [[ -f "$tmpdir/default-info-probe.log" ]]; then
        probed_default="true"
    fi

    if [[ "$probed_default" == "true" ]]; then
        test_fail "unexpected probe of default/current docker context"
    elif printf '%s' "$output" | grep -q "daemon is not running"; then
        test_fail "unexpected daemon warning when containai-docker context is reachable"
    else
        test_pass
    fi
    rm -rf "$tmpdir"
}

test_check_docker_no_containai_context_no_warning() {
    test_start "check_docker does not warn when containai-docker context is absent"
    local tmpdir orig_path output
    tmpdir="$(mktemp -d)"
    orig_path="$PATH"
    mkdir -p "$tmpdir/bin"

    cat >"$tmpdir/bin/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "--version" ]]; then
    printf '%s\n' "Docker version 29.0.0, build test"
    exit 0
fi

if [[ "${1:-}" == "context" && "${2:-}" == "inspect" && "${3:-}" == "containai-docker" ]]; then
    # containai-docker context does not exist yet
    exit 1
fi

if [[ "${1:-}" == "info" ]]; then
    # Should not be called by check_docker in this case
    printf 'called\n' >> "__DEFAULT_INFO_PROBE__"
    exit 1
fi

exit 1
EOF
    chmod +x "$tmpdir/bin/docker"
    sed -i "s|__DEFAULT_INFO_PROBE__|$tmpdir/default-info-probe.log|g" "$tmpdir/bin/docker"

    PATH="$tmpdir/bin:$orig_path"
    output="$(check_docker 2>&1 || true)"
    PATH="$orig_path"

    local probed_default="false"
    if [[ -f "$tmpdir/default-info-probe.log" ]]; then
        probed_default="true"
    fi

    if [[ "$probed_default" == "true" ]]; then
        test_fail "unexpected probe of default/current docker context"
    elif printf '%s' "$output" | grep -q "daemon is not running"; then
        test_fail "unexpected daemon warning when containai-docker context is absent"
    else
        test_pass
    fi
    rm -rf "$tmpdir"
}

test_build_local_native_artifacts_source_checkout_uses_debug() {
    test_start "source checkout native build uses --debug --install"
    local tmpdir orig_path source_dir marker_file
    tmpdir="$(mktemp -d)"
    orig_path="$PATH"
    source_dir="$tmpdir/src"
    marker_file="$tmpdir/build-args.log"

    mkdir -p "$source_dir/acp-proxy"
    cat >"$source_dir/acp-proxy/build.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" > "__MARKER_FILE__"
mkdir -p ../bin
printf '%s\n' "dummy" > ../bin/acp-proxy
chmod +x ../bin/acp-proxy
EOF
    chmod +x "$source_dir/acp-proxy/build.sh"
    sed -i "s|__MARKER_FILE__|$marker_file|g" "$source_dir/acp-proxy/build.sh"

    mkdir -p "$tmpdir/bin"
    cat >"$tmpdir/bin/dotnet" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "10.0.101"
EOF
    chmod +x "$tmpdir/bin/dotnet"

    PATH="$tmpdir/bin:$orig_path"
    if build_local_native_artifacts "$source_dir" "source_checkout"; then
        :
    else
        PATH="$orig_path"
        rm -rf "$tmpdir"
        test_fail "build_local_native_artifacts returned non-zero"
        return
    fi
    PATH="$orig_path"

    if [[ -f "$marker_file" ]] && [[ "$(cat "$marker_file")" == "--debug --install" ]]; then
        test_pass
    else
        test_fail "expected '--debug --install', got '$(cat "$marker_file" 2>/dev/null || printf 'missing')'"
    fi
    rm -rf "$tmpdir"
}

source_installer
test_detect_local_mode_source_checkout
test_detect_os_ubuntu_mapping
test_check_docker_context_fallback
test_check_docker_no_containai_context_no_warning
test_build_local_native_artifacts_source_checkout_uses_debug

printf '\nSummary: %s run, %s passed, %s failed\n' "$TESTS_RUN" "$TESTS_PASSED" "$TESTS_FAILED"
if [[ "$TESTS_FAILED" -ne 0 ]]; then
    exit 1
fi
