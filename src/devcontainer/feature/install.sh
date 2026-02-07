#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v cai >/dev/null 2>&1; then
    printf 'ERROR: cai is required but not found on PATH\n' >&2
    exit 1
fi

cai system devcontainer install --feature-dir "$SCRIPT_DIR"
