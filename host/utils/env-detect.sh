#!/usr/bin/env bash
# Detects Coding Agents profile based on signed profile file (no env overrides).
# Emits key=value pairs so callers can eval/export them.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT_DEFAULT="$(cd "$SCRIPT_DIR/../.." && pwd)"

profile_file="${CODING_AGENTS_PROFILE_FILE:-$REPO_ROOT_DEFAULT/profile.env}"
profile=""
image_prefix=""
image_tag=""
registry=""
repo_root="$REPO_ROOT_DEFAULT"
prod_root_default="/opt/coding-agents/current"
prod_root="$prod_root_default"
format="env"

print_help() {
    cat <<'EOF'
Usage: env-detect.sh [--format env|json] [--profile-file PATH] [--repo-root PATH] [--prod-root PATH]

Detects Coding Agents profile using profile.env:
  PROFILE=dev|prod
  IMAGE_PREFIX=<docker image prefix>
  IMAGE_TAG=<docker tag>
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --format)
            format="$2"
            shift 2
            ;;
        --profile-file)
            profile_file="$2"
            shift 2
            ;;
        --repo-root) repo_root="$2"; shift 2 ;;
        --prod-root) prod_root="$2"; shift 2 ;;
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

load_profile() {
    local file="$1"
    if [ -f "$file" ]; then
        # shellcheck disable=SC1090
        source "$file"
    fi
    profile="${PROFILE:-dev}"
    image_prefix="${IMAGE_PREFIX:-coding-agents-dev}"
    image_tag="${IMAGE_TAG:-devlocal}"
    registry="${REGISTRY:-ghcr.io/novotnyllc}"
}

load_profile "$profile_file"

resolve_path() {
    local path="$1"
    if command -v realpath >/dev/null 2>&1; then
        realpath "$path" 2>/dev/null || echo "$path"
        return
    fi
    (
        cd "$(dirname "$path")" 2>/dev/null && pwd -P
    ) | sed "s|\$|/$(basename "$path")|" || echo "$path"
}

case "$profile" in
    dev|prod) ;;
    *)
        echo "Invalid profile mode in $profile_file: $profile" >&2
        exit 1
        ;;
esac

if [ "$profile" = "prod" ]; then
    root=$(resolve_path "$prod_root")
    config_root="/etc/coding-agents"
    data_root="/var/lib/coding-agents"
    cache_root="/var/cache/coding-agents"
else
    root=$(resolve_path "$repo_root")
    config_root="${HOME}/.config/coding-agents-dev"
    data_root="${HOME}/.local/share/coding-agents-dev"
    cache_root="${HOME}/.cache/coding-agents-dev"
fi

sha_file="${CODING_AGENTS_SHA256_FILE:-${root}/SHA256SUMS}"

emit_env() {
    printf 'CODING_AGENTS_PROFILE=%s\n' "$profile"
    printf 'CODING_AGENTS_ROOT=%s\n' "$root"
    printf 'CODING_AGENTS_CONFIG_ROOT=%s\n' "$config_root"
    printf 'CODING_AGENTS_DATA_ROOT=%s\n' "$data_root"
    printf 'CODING_AGENTS_CACHE_ROOT=%s\n' "$cache_root"
    printf 'CODING_AGENTS_SHA256_FILE=%s\n' "$sha_file"
    printf 'CODING_AGENTS_IMAGE_PREFIX=%s\n' "$image_prefix"
    printf 'CODING_AGENTS_IMAGE_TAG=%s\n' "$image_tag"
    printf 'CODING_AGENTS_REGISTRY=%s\n' "$registry"
}

emit_json() {
    printf '{'
    printf '"profile":"%s",' "$profile"
    printf '"root":"%s",' "$root"
    printf '"configRoot":"%s",' "$config_root"
    printf '"dataRoot":"%s",' "$data_root"
    printf '"cacheRoot":"%s",' "$cache_root"
    printf '"sha256File":"%s",' "$sha_file"
    printf '"imagePrefix":"%s",' "$image_prefix"
    printf '"imageTag":"%s",' "$image_tag"
    printf '"registry":"%s"' "$registry"
    printf '}\n'
}

case "$format" in
    env) emit_env ;;
    json) emit_json ;;
    *)
        echo "Unsupported format: $format" >&2
        exit 1
        ;;
esac
