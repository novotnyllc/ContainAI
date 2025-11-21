#!/usr/bin/env bash
# Verifies SHA256SUMS for ContainAI installs.
# shellcheck source-path=SCRIPTDIR source=common-functions.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common-functions.sh"

mode="${CONTAINAI_PROFILE:-${CONTAINAI_MODE:-dev}}"
root="${CONTAINAI_ROOT:-${CONTAINAI_REPO_ROOT_DEFAULT}}"
sums_path="${CONTAINAI_SHA256_FILE:-${root}/SHA256SUMS}"
allow_dev_missing="${CONTAINAI_ALLOW_DEV_INTEGRITY_MISSING:-1}"
format="text"

print_help() {
    cat <<'EOF'
Usage: integrity-check.sh [--mode dev|prod] [--root PATH] [--sums PATH] [--format text|json]

Behavior:
  - dev: warns and continues when SHA256SUMS is missing or mismatched (exit 0)
  - prod: fails hard when SHA256SUMS is missing or mismatched (exit 1)

Environment:
  CONTAINAI_PROFILE / CONTAINAI_MODE  : force profile
  CONTAINAI_SHA256_FILE                   : override sums path
  CONTAINAI_ALLOW_DEV_INTEGRITY_MISSING   : set 0 to fail dev missing sums
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --mode)
            mode="$2"
            shift 2
            ;;
        --root)
            root="$2"
            shift 2
            ;;
        --sums|--sums-path)
            sums_path="$2"
            shift 2
            ;;
        --format)
            format="$2"
            shift 2
            ;;
        -h|--help)
            print_help
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            print_help >&2
            exit 1
            ;;
    esac
done

case "$mode" in
    dev|prod) ;;
    *)
        echo "Invalid mode: $mode" >&2
        exit 1
        ;;
esac

emit_result() {
    local status="$1"
    local message="$2"
    case "$format" in
        json)
            python3 - "$mode" "$status" "$message" "$sums_path" "$root" <<'PY'
import json, sys
keys = ["mode", "status", "message", "sumsPath", "root"]
print(json.dumps(dict(zip(keys, sys.argv[1:1+len(keys)]))))
PY
            ;;
        *)
            echo "$message"
            ;;
    esac
}

log_integrity_event() {
    local status="$1"
    local message="$2"
    local payload
    payload=$(printf '{"mode":"%s","status":"%s","sumsPath":"%s","root":"%s","message":"%s"}' \
        "$(json_escape_string "$mode")" \
        "$(json_escape_string "$status")" \
        "$(json_escape_string "$sums_path")" \
        "$(json_escape_string "$root")" \
        "$(json_escape_string "$message")")
    log_security_event "integrity-check" "$payload" >/dev/null 2>&1 || true
}

run_check() {
    if ! command -v sha256sum >/dev/null 2>&1; then
        emit_result "error" "sha256sum not available"
        if [ "$mode" = "prod" ]; then
            log_integrity_event "error" "sha256sum unavailable"
            return 1
        fi
        return 0
    fi

    if [ ! -f "$sums_path" ]; then
        local miss_msg="No SHA256SUMS found at $sums_path"
        if [ "$mode" = "prod" ]; then
            emit_result "fail" "$miss_msg"
            log_integrity_event "fail" "$miss_msg"
            return 1
        fi
        if [ "$allow_dev_missing" = "0" ]; then
            emit_result "fail" "$miss_msg"
            log_integrity_event "fail" "$miss_msg"
            return 1
        fi
        emit_result "warn" "Dev mode: $miss_msg (skipping)"
        log_integrity_event "warn" "$miss_msg"
        return 0
    fi

    local sums_dir
    sums_dir=$(cd "$(dirname "$sums_path")" && pwd)
    local sums_file
    sums_file=$(basename "$sums_path")

    if (cd "$sums_dir" && sha256sum -c "$sums_file"); then
        emit_result "ok" "Integrity check passed for $sums_path"
        log_integrity_event "ok" "Integrity check passed"
        return 0
    fi

    emit_result "fail" "Integrity check failed for $sums_path"
    log_integrity_event "fail" "Integrity mismatch"
    if [ "$mode" = "prod" ]; then
        return 1
    fi
    return 0
}

run_check
