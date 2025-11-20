#!/usr/bin/env bash
# Detects whether Coding Agents should run in dev (repo) or prod (system install) mode
# Emits key=value pairs so callers can eval/export them.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT_DEFAULT="$(cd "$SCRIPT_DIR/../.." && pwd)"

mode="${CODING_AGENTS_PROFILE:-${CODING_AGENTS_MODE:-}}"
repo_root="${CODING_AGENTS_REPO_ROOT:-$REPO_ROOT_DEFAULT}"
prod_root_default="/opt/coding-agents/current"
prod_root="${CODING_AGENTS_PROD_ROOT:-${CODING_AGENTS_INSTALL_ROOT:-$prod_root_default}}"
format="env"

print_help() {
    cat <<'EOF'
Usage: env-detect.sh [--format env|json] [--repo-root PATH] [--prod-root PATH]

Detects Coding Agents profile:
  - dev  : running from the repo (default when a git checkout is present)
  - prod : system install with versioned/immutable layout

Environment overrides:
  CODING_AGENTS_PROFILE / CODING_AGENTS_MODE : force dev|prod
  CODING_AGENTS_PROD_ROOT / CODING_AGENTS_INSTALL_ROOT : prod root (default /opt/coding-agents/current)
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --format)
            format="$2"
            shift 2
            ;;
        --repo-root)
            repo_root="$2"
            shift 2
            ;;
        --prod-root)
            prod_root="$2"
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

resolve_path() {
    local path="$1"
    if command -v realpath >/dev/null 2>&1; then
        realpath "$path" 2>/dev/null || echo "$path"
    else
        python3 - <<PY
import os, sys
print(os.path.realpath(sys.argv[1]))
PY
    fi
}

if [ -z "$mode" ] && [ -n "${CODING_AGENTS_FORCE_MODE:-}" ]; then
    mode="$CODING_AGENTS_FORCE_MODE"
fi

if [ -z "$mode" ]; then
    if [ -d "$repo_root/.git" ]; then
        mode="dev"
    elif [ -d "$prod_root/host/launchers" ]; then
        mode="prod"
    else
        mode="dev"
    fi
fi

case "$mode" in
    dev|prod) ;;
    *)
        echo "Invalid profile mode: $mode" >&2
        exit 1
        ;;
esac

if [ "$mode" = "prod" ]; then
    root=$(resolve_path "$prod_root")
    config_root="${CODING_AGENTS_CONFIG_ROOT:-/etc/coding-agents}"
    data_root="${CODING_AGENTS_DATA_ROOT:-/var/lib/coding-agents}"
    cache_root="${CODING_AGENTS_CACHE_ROOT:-/var/cache/coding-agents}"
else
    root=$(resolve_path "$repo_root")
    config_root="${CODING_AGENTS_CONFIG_ROOT:-${HOME}/.config/coding-agents-dev}"
    data_root="${CODING_AGENTS_DATA_ROOT:-${HOME}/.local/share/coding-agents-dev}"
    cache_root="${CODING_AGENTS_CACHE_ROOT:-${HOME}/.cache/coding-agents-dev}"
fi

sha_file="${CODING_AGENTS_SHA256_FILE:-${root}/SHA256SUMS}"

emit_env() {
    printf 'CODING_AGENTS_PROFILE=%s\n' "$mode"
    printf 'CODING_AGENTS_ROOT=%s\n' "$root"
    printf 'CODING_AGENTS_CONFIG_ROOT=%s\n' "$config_root"
    printf 'CODING_AGENTS_DATA_ROOT=%s\n' "$data_root"
    printf 'CODING_AGENTS_CACHE_ROOT=%s\n' "$cache_root"
    printf 'CODING_AGENTS_SHA256_FILE=%s\n' "$sha_file"
}

emit_json() {
    python3 - "$mode" "$root" "$config_root" "$data_root" "$cache_root" "$sha_file" <<'PY'
import json, sys
keys = ["profile", "root", "configRoot", "dataRoot", "cacheRoot", "sha256File"]
data = dict(zip(keys, sys.argv[1:1+len(keys)]))
print(json.dumps(data))
PY
}

case "$format" in
    env) emit_env ;;
    json) emit_json ;;
    *)
        echo "Unsupported format: $format" >&2
        exit 1
        ;;
esac
