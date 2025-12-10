#!/usr/bin/env bash
# Label helpers for test resources
set -euo pipefail

TEST_LABEL_PREFIX="${TEST_LABEL_PREFIX:-containai.test}"

generate_session_id() {
    if [[ -n "${GITHUB_RUN_ID:-}" ]]; then
        echo "gh-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT:-1}"
    elif [[ -n "${CI_JOB_ID:-}" ]]; then
        echo "ci-${CI_JOB_ID}"
    elif [[ -n "${BUILD_ID:-}" ]]; then
        echo "jenkins-${BUILD_ID}"
    else
        echo "local-$$-$(date +%s)"
    fi
}

current_timestamp() {
    date +%s
}
