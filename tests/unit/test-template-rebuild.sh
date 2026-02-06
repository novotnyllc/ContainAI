#!/usr/bin/env bash
# Unit tests for template rebuild prompting behavior
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=../../src/containai.sh
source "$REPO_ROOT/src/containai.sh"

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TEST_TMPDIR=""

MOCK_CONTAINER_TEMPLATE_LABEL="default"
MOCK_CONTAINER_TEMPLATE_HASH=""
PROMPT_CALLS=0
PROMPT_RESULT=1

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
    _CAI_TEMPLATE_DIR="$TEST_TMPDIR/templates"
    mkdir -p "$TEST_TMPDIR/templates/default"
    cat > "$TEST_TMPDIR/templates/default/Dockerfile" <<'DOCKERFILE'
FROM ghcr.io/novotnyllc/containai:latest
USER agent
DOCKERFILE
}

teardown_tmpdir() {
    if [[ -n "$TEST_TMPDIR" ]] && [[ -d "$TEST_TMPDIR" ]]; then
        rm -rf "$TEST_TMPDIR"
    fi
}

# Mock docker inspect label reads used by _cai_maybe_prompt_template_rebuild
docker() {
    local -a args=("$@")

    if [[ "${args[0]:-}" == "--context" ]]; then
        args=("${args[@]:2}")
    fi

    if [[ "${args[0]:-}" == "inspect" && "${args[1]:-}" == "--format" ]]; then
        local fmt="${args[2]:-}"
        case "$fmt" in
            *"ai.containai.template-hash"*)
                printf '%s' "$MOCK_CONTAINER_TEMPLATE_HASH"
                return 0
                ;;
            *"ai.containai.template"*)
                printf '%s' "$MOCK_CONTAINER_TEMPLATE_LABEL"
                return 0
                ;;
        esac
    fi

    return 1
}

# Mock prompt helper to avoid interactive input in unit tests
_cai_prompt_confirm() {
    PROMPT_CALLS=$((PROMPT_CALLS + 1))
    return "$PROMPT_RESULT"
}

test_start "_cai_maybe_prompt_template_rebuild skips prompt when hash unchanged"
setup_tmpdir
current_hash="$(_cai_template_fingerprint "default")"
MOCK_CONTAINER_TEMPLATE_LABEL="default"
MOCK_CONTAINER_TEMPLATE_HASH="$current_hash"
PROMPT_CALLS=0
PROMPT_RESULT=0
if _cai_maybe_prompt_template_rebuild "containai-docker" "test-container" "default" "true"; then
    if [[ "$PROMPT_CALLS" -eq 0 ]]; then
        test_pass
    else
        test_fail "expected 0 prompts, got $PROMPT_CALLS"
    fi
else
    test_fail "expected success return when unchanged"
fi
teardown_tmpdir

test_start "_cai_maybe_prompt_template_rebuild returns 10 when user confirms rebuild"
setup_tmpdir
MOCK_CONTAINER_TEMPLATE_LABEL="default"
MOCK_CONTAINER_TEMPLATE_HASH="different-hash"
PROMPT_CALLS=0
PROMPT_RESULT=0
if _cai_maybe_prompt_template_rebuild "containai-docker" "test-container" "default" "true"; then
    rc=0
else
    rc=$?
fi
if [[ "$rc" -eq 10 && "$PROMPT_CALLS" -eq 1 ]]; then
    test_pass
else
    test_fail "expected rc=10 and one prompt, got rc=$rc prompts=$PROMPT_CALLS"
fi
teardown_tmpdir

test_start "_cai_maybe_prompt_template_rebuild continues when user declines"
setup_tmpdir
MOCK_CONTAINER_TEMPLATE_LABEL="default"
MOCK_CONTAINER_TEMPLATE_HASH="different-hash"
PROMPT_CALLS=0
PROMPT_RESULT=1
if _cai_maybe_prompt_template_rebuild "containai-docker" "test-container" "default" "true"; then
    rc=0
else
    rc=$?
fi
if [[ "$rc" -eq 0 && "$PROMPT_CALLS" -eq 1 ]]; then
    test_pass
else
    test_fail "expected rc=0 and one prompt, got rc=$rc prompts=$PROMPT_CALLS"
fi
teardown_tmpdir

test_start "_cai_maybe_prompt_template_rebuild returns 2 without prompting when prompt disabled"
setup_tmpdir
MOCK_CONTAINER_TEMPLATE_LABEL="default"
MOCK_CONTAINER_TEMPLATE_HASH="different-hash"
PROMPT_CALLS=0
PROMPT_RESULT=0
if _cai_maybe_prompt_template_rebuild "containai-docker" "test-container" "default" "false"; then
    rc=0
else
    rc=$?
fi
if [[ "$rc" -eq 2 && "$PROMPT_CALLS" -eq 0 ]]; then
    test_pass
else
    test_fail "expected rc=2 and zero prompts, got rc=$rc prompts=$PROMPT_CALLS"
fi
teardown_tmpdir

test_start "_cai_maybe_prompt_template_rebuild skips when container template label mismatches"
setup_tmpdir
MOCK_CONTAINER_TEMPLATE_LABEL="custom-template"
MOCK_CONTAINER_TEMPLATE_HASH="different-hash"
PROMPT_CALLS=0
PROMPT_RESULT=0
if _cai_maybe_prompt_template_rebuild "containai-docker" "test-container" "default" "true"; then
    rc=0
else
    rc=$?
fi
if [[ "$rc" -eq 0 && "$PROMPT_CALLS" -eq 0 ]]; then
    test_pass
else
    test_fail "expected rc=0 and zero prompts on mismatch, got rc=$rc prompts=$PROMPT_CALLS"
fi
teardown_tmpdir

printf '\n==========================================\n'
printf 'Tests run: %s\n' "$TESTS_RUN"
printf 'Passed:    %s\n' "$TESTS_PASSED"
printf 'Failed:    %s\n' "$TESTS_FAILED"
printf '==========================================\n'

if [[ "$TESTS_FAILED" -gt 0 ]]; then
    exit 1
fi
