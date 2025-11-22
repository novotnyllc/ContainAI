#!/usr/bin/env bash
# Detects ContainAI profile based on signed profile file (no env overrides).
# Emits key=value pairs so callers can eval/export them.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT_DEFAULT="$(cd "$SCRIPT_DIR/../.." && pwd)"

profile_file="${CONTAINAI_PROFILE_FILE:-$REPO_ROOT_DEFAULT/profile.env}"
profile_default="dev"
image_prefix_default="containai-dev"
image_tag_default="devlocal"
registry_default="ghcr.io/novotnyllc"
image_digest_default=""
image_digest_copilot_default=""
image_digest_codex_default=""
image_digest_claude_default=""
image_digest_proxy_default=""
image_digest_log_fwd_default=""
profile="$profile_default"
image_prefix="$image_prefix_default"
image_tag="$image_tag_default"
registry="$registry_default"
image_digest="$image_digest_default"
image_digest_copilot="$image_digest_copilot_default"
image_digest_codex="$image_digest_codex_default"
image_digest_claude="$image_digest_claude_default"
image_digest_proxy="$image_digest_proxy_default"
image_digest_log_fwd="$image_digest_log_fwd_default"
profile_loaded=0
profile_env_set=0
image_prefix_env_set=0
image_tag_env_set=0
registry_env_set=0
image_digest_env_set=0
image_digest_copilot_env_set=0
image_digest_codex_env_set=0
image_digest_claude_env_set=0
image_digest_proxy_env_set=0
image_digest_log_fwd_env_set=0
repo_root="$REPO_ROOT_DEFAULT"
prod_root_default="/opt/containai/current"
prod_root="$prod_root_default"
format="env"

print_help() {
    cat <<'EOF'
Usage: env-detect.sh [--format env|json] [--profile-file PATH] [--repo-root PATH] [--prod-root PATH]

Detects ContainAI profile using profile.env:
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

[[ -n "${PROFILE:-}" ]] && profile_env_set=1
[[ -n "${IMAGE_PREFIX:-}" ]] && image_prefix_env_set=1
[[ -n "${IMAGE_TAG:-}" ]] && image_tag_env_set=1
[[ -n "${REGISTRY:-}" ]] && registry_env_set=1
[[ -n "${IMAGE_DIGEST:-}" ]] && image_digest_env_set=1
[[ -n "${IMAGE_DIGEST_COPILOT:-}" ]] && image_digest_copilot_env_set=1
[[ -n "${IMAGE_DIGEST_CODEX:-}" ]] && image_digest_codex_env_set=1
[[ -n "${IMAGE_DIGEST_CLAUDE:-}" ]] && image_digest_claude_env_set=1
[[ -n "${IMAGE_DIGEST_PROXY:-}" ]] && image_digest_proxy_env_set=1
[[ -n "${IMAGE_DIGEST_LOG_FORWARDER:-}" ]] && image_digest_log_fwd_env_set=1

load_profile() {
    local file="$1"
    if [ -f "$file" ]; then
        # shellcheck disable=SC1090
        source "$file"
        profile_loaded=1
        [[ -n "${PROFILE:-}" ]] && profile_env_set=1
        [[ -n "${IMAGE_PREFIX:-}" ]] && image_prefix_env_set=1
        [[ -n "${IMAGE_TAG:-}" ]] && image_tag_env_set=1
        [[ -n "${REGISTRY:-}" ]] && registry_env_set=1
        [[ -n "${IMAGE_DIGEST:-}" ]] && image_digest_env_set=1
        [[ -n "${IMAGE_DIGEST_COPILOT:-}" ]] && image_digest_copilot_env_set=1
        [[ -n "${IMAGE_DIGEST_CODEX:-}" ]] && image_digest_codex_env_set=1
        [[ -n "${IMAGE_DIGEST_CLAUDE:-}" ]] && image_digest_claude_env_set=1
        [[ -n "${IMAGE_DIGEST_PROXY:-}" ]] && image_digest_proxy_env_set=1
        [[ -n "${IMAGE_DIGEST_LOG_FORWARDER:-}" ]] && image_digest_log_fwd_env_set=1
    fi
    profile="${PROFILE:-$profile}"
    image_prefix="${IMAGE_PREFIX:-$image_prefix}"
    image_tag="${IMAGE_TAG:-$image_tag}"
    registry="${REGISTRY:-$registry}"
    image_digest="${IMAGE_DIGEST:-$image_digest}"
    image_digest_copilot="${IMAGE_DIGEST_COPILOT:-$image_digest_copilot}"
    image_digest_codex="${IMAGE_DIGEST_CODEX:-$image_digest_codex}"
    image_digest_claude="${IMAGE_DIGEST_CLAUDE:-$image_digest_claude}"
    image_digest_proxy="${IMAGE_DIGEST_PROXY:-$image_digest_proxy}"
    image_digest_log_fwd="${IMAGE_DIGEST_LOG_FORWARDER:-$image_digest_log_fwd}"
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

detect_prod_install() {
    local candidate="$1"
    local meta="$candidate/install.meta"
    if [ ! -f "$meta" ]; then
        return 1
    fi
    local version
    version=$(awk -F= '/^version=/ {print $2; exit}' "$meta" 2>/dev/null || true)
    profile="prod"
    prod_root="$candidate"
    if [ $image_prefix_env_set -eq 0 ]; then
        image_prefix="containai"
    fi
    if [ $image_tag_env_set -eq 0 ]; then
        image_tag="${version:-$image_tag_default}"
    fi
    if [ $registry_env_set -eq 0 ]; then
        registry="$registry_default"
    fi
    if [ $image_digest_env_set -eq 0 ]; then
        image_digest="$image_digest_default"
    fi
    if [ $image_digest_copilot_env_set -eq 0 ]; then
        image_digest_copilot="$image_digest_copilot_default"
    fi
    if [ $image_digest_codex_env_set -eq 0 ]; then
        image_digest_codex="$image_digest_codex_default"
    fi
    if [ $image_digest_claude_env_set -eq 0 ]; then
        image_digest_claude="$image_digest_claude_default"
    fi
    if [ $image_digest_proxy_env_set -eq 0 ]; then
        image_digest_proxy="$image_digest_proxy_default"
    fi
    if [ $image_digest_log_fwd_env_set -eq 0 ]; then
        image_digest_log_fwd="$image_digest_log_fwd_default"
    fi
    return 0
}

if [ $profile_loaded -eq 0 ] && [ $profile_env_set -eq 0 ]; then
    for candidate in "$prod_root" "$REPO_ROOT_DEFAULT"; do
        if detect_prod_install "$candidate"; then
            break
        fi
    done
fi

case "$profile" in
    dev|prod) ;;
    *)
        echo "Invalid profile mode in $profile_file: $profile" >&2
        exit 1
        ;;
esac

if [ "$profile" = "prod" ]; then
    if [ -z "$image_digest" ]; then
        echo "Prod profile requires IMAGE_DIGEST in $profile_file (pin images by digest)" >&2
        exit 1
    fi
    if [ -z "$image_digest_copilot" ] || [ -z "$image_digest_codex" ] || [ -z "$image_digest_claude" ]; then
        echo "Prod profile requires IMAGE_DIGEST_COPILOT/CODEX/CLAUDE in $profile_file" >&2
        exit 1
    fi
    if [ -z "$image_digest_proxy" ] || [ -z "$image_digest_log_fwd" ]; then
        echo "Prod profile requires IMAGE_DIGEST_PROXY and IMAGE_DIGEST_LOG_FORWARDER in $profile_file" >&2
        exit 1
    fi
    if [ -z "$image_tag" ] || [ -z "$image_prefix" ] || [ -z "$registry" ]; then
        echo "Prod profile requires IMAGE_PREFIX, IMAGE_TAG, and REGISTRY in $profile_file" >&2
        exit 1
    fi
fi

if [ "$profile" = "prod" ]; then
    root=$(resolve_path "$prod_root")
    config_root="/etc/containai"
    data_root="/var/lib/containai"
    cache_root="/var/cache/containai"
else
    root=$(resolve_path "$repo_root")
    config_root="${HOME}/.config/containai-dev"
    data_root="${HOME}/.local/share/containai-dev"
    cache_root="${HOME}/.cache/containai-dev"
fi

sha_file="${CONTAINAI_SHA256_FILE:-${root}/SHA256SUMS}"

emit_env() {
    printf 'CONTAINAI_PROFILE=%s\n' "$profile"
    printf 'CONTAINAI_ROOT=%s\n' "$root"
    printf 'CONTAINAI_CONFIG_ROOT=%s\n' "$config_root"
    printf 'CONTAINAI_DATA_ROOT=%s\n' "$data_root"
    printf 'CONTAINAI_CACHE_ROOT=%s\n' "$cache_root"
    printf 'CONTAINAI_SHA256_FILE=%s\n' "$sha_file"
    printf 'CONTAINAI_IMAGE_PREFIX=%s\n' "$image_prefix"
    printf 'CONTAINAI_IMAGE_TAG=%s\n' "$image_tag"
    printf 'CONTAINAI_REGISTRY=%s\n' "$registry"
    printf 'CONTAINAI_IMAGE_DIGEST=%s\n' "$image_digest"
    printf 'CONTAINAI_IMAGE_DIGEST_COPILOT=%s\n' "$image_digest_copilot"
    printf 'CONTAINAI_IMAGE_DIGEST_CODEX=%s\n' "$image_digest_codex"
    printf 'CONTAINAI_IMAGE_DIGEST_CLAUDE=%s\n' "$image_digest_claude"
    printf 'CONTAINAI_IMAGE_DIGEST_PROXY=%s\n' "$image_digest_proxy"
    printf 'CONTAINAI_IMAGE_DIGEST_LOG_FORWARDER=%s\n' "$image_digest_log_fwd"
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
    printf '"registry":"%s",' "$registry"
    printf '"imageDigest":"%s",' "$image_digest"
    printf '"imageDigestCopilot":"%s",' "$image_digest_copilot"
    printf '"imageDigestCodex":"%s",' "$image_digest_codex"
    printf '"imageDigestClaude":"%s",' "$image_digest_claude"
    printf '"imageDigestProxy":"%s",' "$image_digest_proxy"
    printf '"imageDigestLogForwarder":"%s"' "$image_digest_log_fwd"
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
