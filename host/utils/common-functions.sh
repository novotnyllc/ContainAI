#!/usr/bin/env bash
# Common functions for agent management scripts
set -euo pipefail

COMMON_FUNCTIONS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CONTAINAI_REPO_ROOT_DEFAULT=$(cd "$COMMON_FUNCTIONS_DIR/../.." && pwd)

CONTAINAI_PROFILE_FILE="${CONTAINAI_PROFILE_FILE:-$CONTAINAI_REPO_ROOT_DEFAULT/profile.env}"
CONTAINAI_PROFILE="dev"
CONTAINAI_ROOT="$CONTAINAI_REPO_ROOT_DEFAULT"
# Defaults for dev; overridden by env-detect profile file.
CONTAINAI_CONFIG_DIR="${HOME}/.config/containai-dev"
CONTAINAI_DATA_ROOT="${HOME}/.local/share/containai-dev"
CONTAINAI_CACHE_ROOT="${HOME}/.cache/containai-dev"
CONTAINAI_SHA256_FILE="${CONTAINAI_ROOT}/SHA256SUMS"
CONTAINAI_IMAGE_PREFIX="containai-dev"
CONTAINAI_IMAGE_TAG="devlocal"
CONTAINAI_REGISTRY="ghcr.io/novotnyllc"
CONTAINAI_IMAGE_DIGEST=""
CONTAINAI_IMAGE_DIGEST_COPILOT=""
CONTAINAI_IMAGE_DIGEST_CODEX=""
CONTAINAI_IMAGE_DIGEST_CLAUDE=""
CONTAINAI_IMAGE_DIGEST_PROXY=""
CONTAINAI_IMAGE_DIGEST_LOG_FORWARDER=""
CONTAINAI_HOST_CONFIG_FILE="${CONTAINAI_HOST_CONFIG:-${CONTAINAI_CONFIG_DIR}/host-config.env}"
CONTAINAI_OVERRIDE_DIR="${CONTAINAI_OVERRIDE_DIR:-${CONTAINAI_CONFIG_DIR}/overrides}"
CONTAINAI_DIRTY_OVERRIDE_TOKEN="${CONTAINAI_DIRTY_OVERRIDE_TOKEN:-${CONTAINAI_OVERRIDE_DIR}/allow-dirty}"
CONTAINAI_CACHE_DIR="${CONTAINAI_CACHE_DIR:-${CONTAINAI_CONFIG_DIR}/cache}"
CONTAINAI_PREREQ_CACHE_FILE="${CONTAINAI_PREREQ_CACHE_FILE:-${CONTAINAI_CACHE_DIR}/prereq-check}"
CONTAINAI_SECURITY_ASSET_DIR="${CONTAINAI_ROOT:-$CONTAINAI_REPO_ROOT_DEFAULT}/profiles"
CONTAINAI_BROKER_SCRIPT="${CONTAINAI_BROKER_SCRIPT:-${CONTAINAI_REPO_ROOT_DEFAULT}/host/utils/secret-broker.py}"
CONTAINAI_AUDIT_LOG="${CONTAINAI_AUDIT_LOG:-${CONTAINAI_CONFIG_DIR}/security-events.log}"
CONTAINAI_HELPER_NETWORK_POLICY="${CONTAINAI_HELPER_NETWORK_POLICY:-loopback}"
CONTAINAI_HELPER_PIDS_LIMIT="${CONTAINAI_HELPER_PIDS_LIMIT:-64}"
CONTAINAI_HELPER_MEMORY="${CONTAINAI_HELPER_MEMORY:-512m}"
DEFAULT_LAUNCHER_UPDATE_POLICY="prompt"

get_profile_suffix() {
    if [ "${CONTAINAI_PROFILE:-dev}" = "dev" ]; then
        printf '%s' "-dev"
    else
        printf ''
    fi
}

_sha256_stream() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 | awk '{print $1}'
    else
        python3 - <<'PY'
import hashlib, sys
print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest())
PY
    fi
}

_sha256_file() {
    local file="$1"
    [ -f "$file" ] || return 1
    _sha256_stream < "$file"
}

_collect_prereq_fingerprint() {
    local repo_root="$1"
    local script_path="$repo_root/host/utils/verify-prerequisites.sh"
    local entries=()
    if [ -f "$script_path" ]; then
        local script_hash
        script_hash=$(_sha256_file "$script_path" 2>/dev/null || echo "missing")
        entries+=("script=$script_hash")
    else
        entries+=("script=missing")
    fi

    if command -v docker >/dev/null 2>&1; then
        entries+=("docker=$(docker --version 2>/dev/null | tr -d '\r')")
    else
        entries+=("docker=missing")
    fi

    if command -v socat >/dev/null 2>&1; then
        entries+=("socat=$(socat -V 2>/dev/null | head -1 | tr -d '\r')")
    else
        entries+=("socat=missing")
    fi

    if command -v git >/dev/null 2>&1; then
        entries+=("git=$(git --version 2>/dev/null | tr -d '\r')")
    else
        entries+=("git=missing")
    fi

    if command -v gh >/dev/null 2>&1; then
        entries+=("gh=$(gh --version 2>/dev/null | head -1 | tr -d '\r')")
    else
        entries+=("gh=missing")
    fi

    entries+=("uname=$(uname -s 2>/dev/null || echo unknown)-$(uname -m 2>/dev/null || echo unknown)")

    if [ ${#entries[@]} -eq 0 ]; then
        return 1
    fi

    printf '%s\n' "${entries[@]}" | _sha256_stream
}

ensure_prerequisites_verified() {
    local repo_root="${1:-${CONTAINAI_REPO_ROOT:-$CONTAINAI_REPO_ROOT_DEFAULT}}"
    if [ "${CONTAINAI_DISABLE_AUTO_PREREQ_CHECK:-0}" = "1" ]; then
        return 0
    fi
    local script_path="$repo_root/host/utils/verify-prerequisites.sh"
    if [ ! -x "$script_path" ]; then
        return 0
    fi
    local fingerprint
    fingerprint=$(_collect_prereq_fingerprint "$repo_root" 2>/dev/null || echo "")
    if [ -z "$fingerprint" ]; then
        return 0
    fi
    local cache_file="$CONTAINAI_PREREQ_CACHE_FILE"
    local cached=""
    if [ -f "$cache_file" ]; then
        read -r cached < "$cache_file"
    fi
    if [ -n "$cached" ] && [ "$cached" = "$fingerprint" ]; then
        return 0
    fi

    echo "🔍 Running prerequisite verification (first launch or dependency change detected)..."
    if "$script_path"; then
        local cache_dir
        cache_dir=$(dirname "$cache_file")
        mkdir -p "$cache_dir"
        local tmp_file
        tmp_file="${cache_file}.tmp"
        {
            echo "$fingerprint"
            date -u +"%Y-%m-%dT%H:%M:%SZ"
        } > "$tmp_file"
        mv "$tmp_file" "$cache_file"
        echo "✅ Prerequisites verified. Results cached for future launches."
        return 0
    fi

    echo "❌ Automatic prerequisite check failed. Resolve the issues above or run $script_path manually." >&2
    return 1
}

_resolve_git_binary() {
    if command -v git >/dev/null 2>&1; then
        echo "git"
        return 0
    fi
    echo ""
    return 1
}

get_git_head_hash() {
    local repo_root="$1"
    local git_bin
    git_bin=$(_resolve_git_binary) || return 1
    if [ -z "$repo_root" ] || [ ! -d "$repo_root/.git" ]; then
        return 1
    fi
    "$git_bin" -C "$repo_root" rev-parse HEAD 2>/dev/null
}

_trusted_path_exists() {
    local repo_root="$1"
    local path="$2"
    local git_bin
    git_bin=$(_resolve_git_binary) || return 1
    if [ -z "$path" ]; then
        return 1
    fi
    if [ -e "$repo_root/$path" ]; then
        return 0
    fi
    "$git_bin" -C "$repo_root" rev-parse --verify --quiet "HEAD:$path" >/dev/null 2>&1
}

collect_trusted_tree_hashes() {
    local repo_root="$1"
    shift || true
    local git_bin
    git_bin=$(_resolve_git_binary) || return 1
    if [ -z "$repo_root" ] || [ ! -d "$repo_root/.git" ]; then
        return 1
    fi

    local path hash
    for path in "$@"; do
        if [ -z "$path" ]; then
            continue
        fi
        if "$git_bin" -C "$repo_root" rev-parse --verify --quiet "HEAD:$path" >/dev/null 2>&1; then
            hash=$("$git_bin" -C "$repo_root" rev-parse "HEAD:$path")
            printf '%s=%s\n' "$path" "$hash"
        fi
    done
}

_list_dirty_entries() {
    local repo_root="$1"
    shift || true
    local git_bin
    git_bin=$(_resolve_git_binary) || return 1
    local dirty=()
    local status_output path
    for path in "$@"; do
        if [ -z "$path" ]; then
            continue
        fi
        if ! _trusted_path_exists "$repo_root" "$path"; then
            continue
        fi
        status_output=$("$git_bin" -C "$repo_root" status --short -- "$path" 2>/dev/null || true)
        if [ -n "$status_output" ]; then
            dirty+=("$path")
        fi
    done
    printf '%s\n' "${dirty[@]}"
}

json_escape_string() {
    local input="${1:-}"
    input=${input//\\/\\\\}
    input=${input//\"/\\\"}
    input=${input//$'\n'/\\n}
    input=${input//$'\r'/\\r}
    input=${input//$'\t'/\\t}
    printf '%s' "$input"
}

json_array_from_list() {
    if [ "$#" -eq 0 ]; then
        printf '[]'
        return
    fi
    local entries=()
    while [ "$#" -gt 0 ]; do
        entries+=("\"$(json_escape_string "$1")\"")
        shift
    done
    local joined
    joined=$(IFS=,; echo "${entries[*]}")
    printf '[%s]' "$joined"
}

trusted_tree_hashes_to_json() {
    local raw="$1"
    local entries=()
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        local path="${line%%=*}"
        local hash="${line#*=}"
        entries+=("{\"path\":\"$(json_escape_string "$path")\",\"hash\":\"$(json_escape_string "$hash")\"}")
    done <<< "$raw"
    local joined
    joined=$(IFS=,; echo "${entries[*]}")
    printf '[%s]' "$joined"
}

collect_capability_metadata() {
    local root="$1"
    if [ -z "$root" ] || [ ! -d "$root" ]; then
        printf '[]'
        return
    fi
    local entries=()
    while IFS= read -r -d '' file; do
        local stub
        stub=$(basename "$(dirname "$file")")
        local cap
        cap=$(basename "$file")
        cap=${cap%.json}
        entries+=("{\"stub\":\"$(json_escape_string "$stub")\",\"capabilityId\":\"$(json_escape_string "$cap")\"}")
    done < <(find "$root" -mindepth 2 -maxdepth 2 -type f -name '*.json' -print0 2>/dev/null)
    local joined
    joined=$(IFS=,; echo "${entries[*]}")
    printf '[%s]' "$joined"
}

log_security_event() {
    if [ "${CONTAINAI_DISABLE_AUDIT_LOG:-0}" = "1" ]; then
        return
    fi
    local event_name="$1"
    local payload="${2:-{}}"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local record
    record=$(printf '{"ts":"%s","event":"%s","payload":%s}\n' "$timestamp" "$(json_escape_string "$event_name")" "$payload")
    local log_file="$CONTAINAI_AUDIT_LOG"
    local log_dir
    log_dir=$(dirname "$log_file")
    mkdir -p "$log_dir"
    local previous_umask
    previous_umask=$(umask)
    umask 077
    printf '%s' "$record" >> "$log_file"
    umask "$previous_umask"
    if command -v systemd-cat >/dev/null 2>&1; then
        printf '%s' "$record" | systemd-cat -t containai-launcher >/dev/null 2>&1 || true
    fi
}

log_session_config_manifest() {
    local session_id="$1"
    local manifest_sha="$2"
    local repo_root="$3"
    local tree_hashes="$4"
    local git_head
    git_head=$(get_git_head_hash "$repo_root" 2>/dev/null || echo "")
    local tree_json
    tree_json=$(trusted_tree_hashes_to_json "$tree_hashes")
    local payload
    payload=$(printf '{"session":"%s","manifestSha":"%s","gitHead":"%s","trustedTrees":%s}' \
        "$(json_escape_string "$session_id")" \
        "$(json_escape_string "${manifest_sha:-unknown}")" \
        "$(json_escape_string "$git_head")" \
        "$tree_json")
    log_security_event "session-config" "$payload"
}

log_capability_issuance_event() {
    local session_id="$1"
    local output_dir="$2"
    shift 2 || true
    local stubs=("$@")
    local repo_root="${CONTAINAI_REPO_ROOT:-$CONTAINAI_REPO_ROOT_DEFAULT}"
    local git_head
    git_head=$(get_git_head_hash "$repo_root" 2>/dev/null || echo "")
    local manifest_sha="${CONTAINAI_SESSION_CONFIG_SHA256:-}"
    local stub_json
    stub_json=$(json_array_from_list "${stubs[@]}")
    local capabilities_json
    capabilities_json=$(collect_capability_metadata "$output_dir")
    local payload
    payload=$(printf '{"session":"%s","gitHead":"%s","manifestSha":"%s","stubs":%s,"capabilities":%s}' \
        "$(json_escape_string "$session_id")" \
        "$(json_escape_string "$git_head")" \
        "$(json_escape_string "${manifest_sha:-unknown}")" \
        "$stub_json" \
        "$capabilities_json")
    log_security_event "capabilities-issued" "$payload"
}

log_override_usage() {
    local repo_root="$1"
    local label="$2"
    local dirty_list="$3"
    if [ -z "$dirty_list" ]; then
        return
    fi
    local paths=()
    while IFS= read -r entry; do
        [ -z "$entry" ] && continue
        paths+=("$entry")
    done <<< "$dirty_list"
    local dirty_json
    dirty_json=$(json_array_from_list "${paths[@]}")
    local payload
    payload=$(printf '{"repo":"%s","label":"%s","dirtyPaths":%s}' \
        "$(json_escape_string "$repo_root")" \
        "$(json_escape_string "$label")" \
        "$dirty_json")
    log_security_event "override-used" "$payload"
}

detect_environment_profile() {
    local env_detect_script="$COMMON_FUNCTIONS_DIR/env-detect.sh"
    if [ ! -x "$env_detect_script" ]; then
        echo "⚠️  Unable to detect environment profile (missing env-detect.sh)" >&2
        return 1
    fi
    local output
    if ! output=$("$env_detect_script" --format env --profile-file "$CONTAINAI_PROFILE_FILE"); then
        echo "❌ Environment detection failed" >&2
        return 1
    fi
    while IFS='=' read -r key value; do
        [ -z "$key" ] && continue
        case "$key" in
            CONTAINAI_PROFILE) CONTAINAI_PROFILE="$value" ;;
            CONTAINAI_ROOT) CONTAINAI_ROOT="$value" ;;
            CONTAINAI_CONFIG_ROOT) CONTAINAI_CONFIG_DIR="$value" ;;
            CONTAINAI_DATA_ROOT) CONTAINAI_DATA_ROOT="$value" ;;
            CONTAINAI_CACHE_ROOT)
                CONTAINAI_CACHE_ROOT="$value"
                CONTAINAI_CACHE_DIR="$value"
                ;;
            CONTAINAI_SHA256_FILE) CONTAINAI_SHA256_FILE="$value" ;;
            CONTAINAI_IMAGE_PREFIX) CONTAINAI_IMAGE_PREFIX="$value" ;;
            CONTAINAI_IMAGE_TAG) CONTAINAI_IMAGE_TAG="$value" ;;
            CONTAINAI_REGISTRY) CONTAINAI_REGISTRY="$value" ;;
            CONTAINAI_IMAGE_DIGEST) CONTAINAI_IMAGE_DIGEST="$value" ;;
            CONTAINAI_IMAGE_DIGEST_COPILOT) CONTAINAI_IMAGE_DIGEST_COPILOT="$value" ;;
            CONTAINAI_IMAGE_DIGEST_CODEX) CONTAINAI_IMAGE_DIGEST_CODEX="$value" ;;
            CONTAINAI_IMAGE_DIGEST_CLAUDE) CONTAINAI_IMAGE_DIGEST_CLAUDE="$value" ;;
            CONTAINAI_IMAGE_DIGEST_PROXY) CONTAINAI_IMAGE_DIGEST_PROXY="$value" ;;
            CONTAINAI_IMAGE_DIGEST_LOG_FORWARDER) CONTAINAI_IMAGE_DIGEST_LOG_FORWARDER="$value" ;;
        esac
    done <<< "$output"
    export CONTAINAI_PROFILE CONTAINAI_ROOT CONTAINAI_CONFIG_DIR CONTAINAI_DATA_ROOT CONTAINAI_CACHE_ROOT CONTAINAI_SHA256_FILE CONTAINAI_IMAGE_PREFIX CONTAINAI_IMAGE_TAG CONTAINAI_REGISTRY CONTAINAI_IMAGE_DIGEST CONTAINAI_IMAGE_DIGEST_COPILOT CONTAINAI_IMAGE_DIGEST_CODEX CONTAINAI_IMAGE_DIGEST_CLAUDE CONTAINAI_IMAGE_DIGEST_PROXY CONTAINAI_IMAGE_DIGEST_LOG_FORWARDER
    return 0
}

run_integrity_check_if_needed() {
    local integrity_script="$COMMON_FUNCTIONS_DIR/integrity-check.sh"
    if [ ! -x "$integrity_script" ]; then
        echo "⚠️  Missing integrity-check.sh; skipping integrity validation" >&2
        return 0
    fi
    if "$integrity_script" --mode "$CONTAINAI_PROFILE" --root "$CONTAINAI_ROOT" --sums "$CONTAINAI_SHA256_FILE"; then
        return 0
    fi
    return 1
}

enforce_prod_install_root() {
    if [ "${CONTAINAI_PROFILE:-dev}" != "prod" ]; then
        return 0
    fi
    local root="${CONTAINAI_ROOT:-}"
    if [ -z "$root" ] || [ ! -d "$root" ]; then
        echo "❌ Prod profile requires an installed root. Run host/utils/install-release.sh first." >&2
        log_security_event "enforcement" '{"reason":"missing-prod-root"}' >/dev/null 2>&1 || true
        return 1
    fi
    local parent owner
    parent=$(dirname "$root")
    owner=$(stat -c "%U" "$parent" 2>/dev/null || echo "")
    if [ "$(id -u)" -ne 0 ] && [ "$owner" != "root" ]; then
        echo "❌ Prod root must be system-owned (parent owner: $owner). Rejecting $root" >&2
        log_security_event "enforcement" '{"reason":"non-system-root","root":"'"$(json_escape_string "$root")"'"}' >/dev/null 2>&1 || true
        return 1
    fi
    if [[ "$root" =~ ^$HOME ]]; then
        echo "❌ Prod root cannot reside under user home ($root)" >&2
        log_security_event "enforcement" '{"reason":"user-writable-root","root":"'"$(json_escape_string "$root")"'"}' >/dev/null 2>&1 || true
        return 1
    fi
    return 0
}

ensure_trusted_paths_clean() {
    local repo_root="$1"
    shift || true
    local label="${1:-trusted files}"
    shift || true
    local override_token="${CONTAINAI_DIRTY_OVERRIDE_TOKEN}"
    local dirty

    if [ -z "$repo_root" ] || [ ! -d "$repo_root/.git" ]; then
        echo "⚠️  Unable to verify ${label}; repository root missing" >&2
        return 1
    fi

    dirty=$(_list_dirty_entries "$repo_root" "$@")
    if [ -z "$dirty" ]; then
        return 0
    fi

    if [ -f "$override_token" ]; then
        echo "⚠️  Override token detected at $override_token; launching with dirty ${label}: $dirty" >&2
        log_override_usage "$repo_root" "$label" "$dirty"
        return 0
    fi

    echo "❌ Trusted ${label} have uncommitted changes: $dirty" >&2
    echo "   Clean or commit these files, or create an override token at $override_token (usage logged)." >&2
    return 1
}

_read_host_config_value() {
    local key="$1"
    local file="$CONTAINAI_HOST_CONFIG_FILE"

    if [ ! -f "$file" ] || [ -z "$key" ]; then
        return 0
    fi

    # shellcheck disable=SC2002
    local line
    line=$(cat "$file" 2>/dev/null | grep -E "^\s*${key}\s*=" | tail -n 1) || true
    if [ -z "$line" ]; then
        return 0
    fi

    local value
    value=${line#*=}
    value=$(echo "$value" | sed -e 's/^\s*//' -e 's/\s*$//' -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//")
    printf '%s' "$value"
}

get_launcher_update_policy() {
    local env_value="${CONTAINAI_LAUNCHER_UPDATE_POLICY:-}"
    local value="$env_value"

    if [ -z "$value" ]; then
        value=$(_read_host_config_value "LAUNCHER_UPDATE_POLICY")
    fi

    case "$value" in
        always|prompt|never)
            echo "$value"
            ;;
        "")
            echo "$DEFAULT_LAUNCHER_UPDATE_POLICY"
            ;;
        *)
            echo "$DEFAULT_LAUNCHER_UPDATE_POLICY"
            ;;
    esac
}

maybe_check_launcher_updates() {
    local repo_root="$1"
    local context="$2"
    local policy

    if [ "${CONTAINAI_SKIP_UPDATE_CHECK:-0}" = "1" ]; then
        return 0
    fi

    policy=$(get_launcher_update_policy)
    if [ "$policy" = "never" ]; then
        return 0
    fi

    if [ -z "$repo_root" ] || [ ! -d "$repo_root/.git" ]; then
        return 0
    fi

    if ! command -v git >/dev/null 2>&1; then
        echo "⚠️  Skipping launcher update check (git not available)"
        return 0
    fi

    if ! git -C "$repo_root" rev-parse HEAD >/dev/null 2>&1; then
        return 0
    fi

    local upstream
    upstream=$(git -C "$repo_root" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null) || return 0

    if ! git -C "$repo_root" fetch --quiet --tags >/dev/null 2>&1; then
        echo "⚠️  Unable to check launcher updates (git fetch failed)"
        return 0
    fi

    local local_head remote_head base
    local_head=$(git -C "$repo_root" rev-parse HEAD)
    remote_head=$(git -C "$repo_root" rev-parse '@{u}')
    base=$(git -C "$repo_root" merge-base HEAD '@{u}')

    if [ "$local_head" = "$remote_head" ]; then
        return 0
    fi

    if [ "$local_head" != "$base" ] && [ "$remote_head" != "$base" ]; then
        echo "⚠️  Launcher repository has diverged from $upstream. Please sync manually."
        return 0
    fi

    local clean=true
    if ! git -C "$repo_root" diff --quiet || ! git -C "$repo_root" diff --quiet --cached; then
        clean=false
    fi

    if [ "$policy" = "always" ]; then
        if [ "$clean" = false ]; then
            echo "⚠️  Launcher repository has local changes; cannot auto-update."
            return 0
        fi
        if git -C "$repo_root" pull --ff-only >/dev/null 2>&1; then
            echo "✅ Launcher scripts updated to match $upstream"
        else
            echo "⚠️  Failed to auto-update launcher scripts. Please update manually."
        fi
        return 0
    fi

    if [ ! -t 0 ]; then
        echo "⚠️  Launcher scripts are behind $upstream. Update the repository when convenient."
        return 0
    fi

    local suffix=""
    if [ -n "$context" ]; then
        suffix=" ($context)"
    fi
    echo "ℹ️  Launcher scripts are behind $upstream.$suffix"
    if [ "$clean" = false ]; then
        echo "   Local changes detected; please update manually."
        return 0
    fi

    read -p "Update ContainAI launchers now? [Y/n]: " -r response
    response=${response:-Y}
    if [[ $response =~ ^[Yy]$ ]]; then
        if git -C "$repo_root" pull --ff-only >/dev/null 2>&1; then
            echo "✅ Launcher scripts updated."
        else
            echo "⚠️  Failed to update launchers. Please update manually."
        fi
    else
        echo "⏭️  Skipped launcher update."
    fi
}

# Detect container runtime (Docker only)
get_container_runtime() {
    if [ -n "${CONTAINER_RUNTIME:-}" ]; then
        if [ "$CONTAINER_RUNTIME" = "docker" ] && command -v docker &> /dev/null; then
            echo "docker"
            return 0
        fi
        echo "docker"
        return 0
    fi

    if command -v docker &> /dev/null; then
        echo "docker"
        return 0
    fi

    return 1
}

get_secret_broker_script() {
    local candidate
    candidate="${CONTAINAI_BROKER_SCRIPT}"
    if [ -x "$candidate" ]; then
        echo "$candidate"
        return 0
    fi
    candidate="${CONTAINAI_REPO_ROOT_DEFAULT}/host/utils/secret-broker.py"
    if [ -x "$candidate" ]; then
        echo "$candidate"
        return 0
    fi
    echo ""
    return 1
}

ensure_broker_ready() {
    local broker
    broker=$(get_secret_broker_script) || {
        echo "⚠️  Secret broker script not found" >&2
        return 1
    }
    if ! run_python_tool "$broker" -- health >/dev/null 2>&1; then
        echo "❌ Secret broker health check failed" >&2
        return 1
    fi
}

issue_session_capabilities() {
    local session_id="$1"
    local output_dir="$2"
    shift 2 || true
    local stubs=("$@")
    local broker
    broker=$(get_secret_broker_script) || return 1
    if [ ${#stubs[@]} -eq 0 ]; then
        return 0
    fi
    mkdir -p "$output_dir"
    if run_python_tool "$broker" --mount "$output_dir" -- issue --session-id "$session_id" --output "$output_dir" --stubs "${stubs[@]}"; then
        log_capability_issuance_event "$session_id" "$output_dir" "${stubs[@]}"
        return 0
    fi
    return 1
}

# Cache the active container CLI (docker only) so downstream helpers can reuse it
get_active_container_cmd() {
    if [ -n "${CONTAINAI_CONTAINER_CMD:-}" ]; then
        echo "$CONTAINAI_CONTAINER_CMD"
        return 0
    fi

    local runtime
    runtime=$(get_container_runtime 2>/dev/null || true)
    if [ -z "$runtime" ]; then
        runtime="docker"
    fi

    CONTAINAI_CONTAINER_CMD="$runtime"
    echo "$runtime"
}

# Wrapper that dispatches to the detected container CLI
container_cli() {
    local cmd
    cmd=$(get_active_container_cmd)
    "$cmd" "$@"
}

is_linux_host() {
    local kernel
    kernel=$(uname -s 2>/dev/null || echo "")
    [ "$kernel" = "Linux" ]
}

is_wsl_environment() {
    if [ -n "${WSL_DISTRO_NAME:-}" ]; then
        return 0
    fi
    if ! is_linux_host; then
        return 1
    fi
    if [ -r /proc/version ] && grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null; then
        return 0
    fi
    return 1
}

wsl_security_helper_path() {
    local repo_root="${1:-${CONTAINAI_REPO_ROOT:-$CONTAINAI_REPO_ROOT_DEFAULT}}"
    echo "$repo_root/host/utils/fix-wsl-security.sh"
}

resolve_seccomp_profile_path() {
    local repo_root="$1"
    local default_candidate="$repo_root/host/profiles/seccomp-containai-agent.json"
    local asset_candidate=""

    asset_candidate="${CONTAINAI_SECURITY_ASSET_DIR%/}/seccomp-containai-agent.json"

    if [ -f "$default_candidate" ]; then
        echo "$default_candidate"
        return 0
    fi

    if [ -n "$asset_candidate" ] && [ -f "$asset_candidate" ]; then
        echo "$asset_candidate"
        return 0
    fi

    echo "❌ Seccomp profile not found at $default_candidate. Run scripts/install.sh to reinstall the host security assets." >&2
    if [ -n "$asset_candidate" ] && [ "$asset_candidate" != "$default_candidate" ]; then
        echo "   Looked for installed copy at $asset_candidate but it was missing." >&2
    fi
    return 1
}

ensure_security_assets_current() {
    local repo_root="$1"
    local seccomp_repo="$repo_root/host/profiles/seccomp-containai-agent.json"
    local apparmor_repo="$repo_root/host/profiles/apparmor-containai-agent.profile"
    local manifest_path="${CONTAINAI_SECURITY_ASSET_DIR%/}/containai-profiles.sha256"
    local manifest_repo="$repo_root/host/profiles/containai-profiles.sha256"
    if [ ! -f "$manifest_path" ] && [ -f "$manifest_repo" ]; then
        manifest_path="$manifest_repo"
    fi

    local seccomp_path
    if ! seccomp_path=$(resolve_seccomp_profile_path "$repo_root"); then
        return 1
    fi

    local manifest_seccomp_hash=""
    local manifest_apparmor_hash=""
    if [ -f "$manifest_path" ]; then
        manifest_seccomp_hash=$(awk '/seccomp-containai-agent.json/ {print $2}' "$manifest_path" 2>/dev/null | head -1)
        manifest_apparmor_hash=$(awk '/apparmor-containai-agent.profile/ {print $2}' "$manifest_path" 2>/dev/null | head -1)
    fi

    local hash_repo hash_active
    hash_repo=$(_sha256_file "$seccomp_repo" 2>/dev/null || echo "")
    if [ -z "$hash_repo" ]; then
        hash_repo="$manifest_seccomp_hash"
    fi
    hash_active=$(_sha256_file "$seccomp_path" 2>/div/null || echo "")

    if [ -n "$hash_repo" ] && [ -n "$hash_active" ]; then
        if [ "$hash_repo" != "$hash_active" ]; then
            echo "❌ Seccomp profile is outdated. Run 'sudo ./scripts/install.sh' to refresh host security assets." >&2
            return 1
        fi
    else
        echo "❌ Unable to verify seccomp profile freshness (missing reference hash). Run 'sudo ./scripts/install.sh' to reinstall host security assets." >&2
        return 1
    fi

    local apparmor_path=""
    if apparmor_path=$(resolve_apparmor_profile_name "$repo_root"); then
        if [ -f "$apparmor_path" ]; then
            local aa_repo_hash aa_active_hash
            aa_repo_hash=$(_sha256_file "$apparmor_repo" 2>/dev/null || echo "")
            if [ -z "$aa_repo_hash" ]; then
                aa_repo_hash="$manifest_apparmor_hash"
            fi
            aa_active_hash=$(_sha256_file "$apparmor_path" 2>/dev/null || echo "")
            if [ -n "$aa_repo_hash" ] && [ -n "$aa_active_hash" ] && [ "$aa_repo_hash" != "$aa_active_hash" ]; then
                echo "❌ AppArmor profile is outdated. Run 'sudo ./scripts/install.sh' to refresh host security assets." >&2
                return 1
            elif [ -z "$aa_repo_hash" ] || [ -z "$aa_active_hash" ]; then
                echo "❌ Unable to verify AppArmor profile freshness (missing reference hash). Run 'sudo ./scripts/install.sh' to reinstall host security assets." >&2
                return 1
            fi
        fi
    fi

    return 0
}

is_apparmor_supported() {
    if ! is_linux_host; then
        return 1
    fi

    local enabled_flag="/sys/module/apparmor/parameters/enabled"
    if [ ! -r "$enabled_flag" ]; then
        return 1
    fi

    local status
    status=$(cat "$enabled_flag" 2>/dev/null || true)
    if echo "$status" | grep -qi '^y'; then
        return 0
    fi
    return 1
}

apparmor_profiles_file() {
    echo "/sys/kernel/security/apparmor/profiles"
}

apparmor_profiles_readable() {
    local profiles_file
    profiles_file=$(apparmor_profiles_file)
    [ -r "$profiles_file" ]
}

apparmor_profile_loaded() {
    local profile="$1"
    local profiles_file
    profiles_file=$(apparmor_profiles_file)

    if [ -z "$profile" ] || [ ! -r "$profiles_file" ]; then
        return 1
    fi

    if grep -q "^${profile} " "$profiles_file" 2>/dev/null; then
        return 0
    fi
    return 1
}

resolve_apparmor_profile_name() {
    local repo_root="$1"
    local profile="containai-agent"
    local profile_file="$repo_root/host/profiles/apparmor-containai-agent.profile"
    local asset_candidate=""

    asset_candidate="${CONTAINAI_SECURITY_ASSET_DIR%/}/apparmor-containai-agent.profile"
    if [ ! -f "$profile_file" ] && [ -n "$asset_candidate" ] && [ -f "$asset_candidate" ]; then
        profile_file="$asset_candidate"
    fi

    if ! is_apparmor_supported; then
        return 1
    fi

    if apparmor_profile_loaded "$profile"; then
        echo "$profile"
        return 0
    fi

    if [ ! -f "$profile_file" ]; then
        echo "⚠️  AppArmor profile file not found at $profile_file. Run scripts/install.sh to restore the host security profiles." >&2
        return 1
    fi

    if [ "$(id -u 2>/dev/null || echo 1)" = "0" ] && command -v apparmor_parser >/dev/null 2>&1; then
        if apparmor_parser -r -T -W "$profile_file" >/dev/null 2>&1 && apparmor_profile_loaded "$profile"; then
            echo "$profile"
            return 0
        fi
    fi

    echo "⚠️  AppArmor profile '$profile' is not loaded. Run: sudo apparmor_parser -r '$profile_file'" >&2
    return 1
}

verify_host_security_prereqs() {
    local repo_root="${1:-${CONTAINAI_REPO_ROOT:-$CONTAINAI_REPO_ROOT_DEFAULT}}"
    local errors=()
    local warnings=()
    local current_uid
    current_uid=$(id -u 2>/dev/null || echo 1)
    local profiles_file
    profiles_file=$(apparmor_profiles_file)
    local profiles_file_readable=0
    if [ -r "$profiles_file" ]; then
        profiles_file_readable=1
    fi

    local default_seccomp_profile="$repo_root/host/profiles/seccomp-containai-agent.json"
    local installed_seccomp_profile="${CONTAINAI_SECURITY_ASSET_DIR%/}/seccomp-containai-agent.json"

    if ! resolve_seccomp_profile_path "$repo_root" >/dev/null 2>&1; then
        if [ -n "$installed_seccomp_profile" ]; then
            errors+=("Seccomp profile not found at $default_seccomp_profile (or $installed_seccomp_profile). Run scripts/install.sh to reinstall the host security assets before launching agents.")
        else
            errors+=("Seccomp profile not found at $default_seccomp_profile. Run scripts/install.sh to reinstall the host security assets before launching agents.")
        fi
    fi

    if ! is_linux_host; then
        errors+=("AppArmor enforcement requires a Linux host. Run from a Linux kernel with AppArmor enabled.")
    elif ! is_apparmor_supported; then
        if is_wsl_environment; then
            local helper_script
            helper_script=$(wsl_security_helper_path "$repo_root")
            if [ -x "$helper_script" ]; then
                errors+=("AppArmor kernel support not detected (WSL 2). Run '$helper_script --check' to audit your Windows configuration, then rerun '$helper_script' (optionally with --force) to apply the fixes and restart WSL.")
            else
                errors+=("AppArmor kernel support not detected (WSL 2). Use the WSL security helper under host/utils to enable AppArmor on the host kernel.")
            fi
        else
            errors+=("AppArmor kernel support not detected. Enable AppArmor to continue.")
        fi
    else
        local profile="containai-agent"
        local profile_file="$repo_root/host/profiles/apparmor-containai-agent.profile"
        local installed_apparmor_profile="${CONTAINAI_SECURITY_ASSET_DIR%/}/apparmor-containai-agent.profile"
        if [ ! -f "$profile_file" ] && [ -n "$installed_apparmor_profile" ] && [ -f "$installed_apparmor_profile" ]; then
            profile_file="$installed_apparmor_profile"
        fi
        if ! apparmor_profile_loaded "$profile"; then
            if [ "$profiles_file_readable" -eq 0 ] && [ "$current_uid" -ne 0 ]; then
                warnings+=("Unable to verify AppArmor profile '$profile' without elevated privileges. Re-run './host/utils/check-health.sh' with sudo or run: sudo apparmor_parser -r '$profile_file'.")
            elif [ "$current_uid" -ne 0 ] && [ -f "$profile_file" ]; then
                warnings+=("AppArmor profile '$profile' verification skipped (requires sudo). Rerun './host/utils/check-health.sh' with sudo to confirm.")
            elif [ -f "$profile_file" ]; then
                errors+=("AppArmor profile '$profile' is not loaded. Run: sudo apparmor_parser -r '$profile_file'.")
            else
                if [ -n "$installed_apparmor_profile" ]; then
                    errors+=("AppArmor profile file '$profile_file' not found (also checked $installed_apparmor_profile). Run scripts/install.sh to restore the host security profiles.")
                else
                    errors+=("AppArmor profile file '$profile_file' not found. Run scripts/install.sh to restore the host security profiles.")
                fi
            fi
        fi
    fi

    if [ "${CONTAINAI_DISABLE_PTRACE_SCOPE:-0}" = "1" ]; then
        warnings+=("Ptrace scope hardening disabled via CONTAINAI_DISABLE_PTRACE_SCOPE=1")
    elif is_linux_host && [ ! -e /proc/sys/kernel/yama/ptrace_scope ]; then
        errors+=("kernel.yama.ptrace_scope is unavailable. Enable the Yama LSM or export CONTAINAI_DISABLE_PTRACE_SCOPE=1 to bypass (not recommended).")
    fi

    if [ "${CONTAINAI_DISABLE_SENSITIVE_TMPFS:-0}" = "1" ]; then
        warnings+=("Sensitive tmpfs mounting disabled via CONTAINAI_DISABLE_SENSITIVE_TMPFS=1")
    fi

    if [ ${#errors[@]} -gt 0 ]; then
        echo "❌ Host security verification failed:" >&2
        local message
        for message in "${errors[@]}"; do
            echo "   - $message" >&2
        done
        return 1
    fi

    if [ ${#warnings[@]} -gt 0 ]; then
        echo "⚠️  Host security warnings:" >&2
        local warning
        for warning in "${warnings[@]}"; do
            echo "   - $warning" >&2
        done
    fi

    return 0
}

verify_container_security_support() {
    local info_json="${CONTAINAI_CONTAINER_INFO_JSON:-}"
    if [ -z "$info_json" ]; then
        local runtime
        runtime=$(get_active_container_cmd)
        if [ -z "$runtime" ]; then
            echo "❌ Unable to determine container runtime for security checks" >&2
            return 1
        fi
        if ! info_json=$($runtime info --format '{{json .}}' 2>/dev/null); then
            info_json=$($runtime info --format json 2>/dev/null || true)
        fi
    fi

    if [ -z "$info_json" ]; then
        echo "❌ Unable to inspect container runtime security options" >&2
        return 1
    fi

    local summary
    summary=$(python3 - "$info_json" <<'PY'
import json, sys

try:
    data = json.loads(sys.argv[1])
except Exception:
    sys.exit(1)

result = {"seccomp": False, "apparmor": False}

def consider(options):
    if isinstance(options, list):
        for entry in options:
            if isinstance(entry, str):
                low = entry.lower()
                if "seccomp" in low:
                    result["seccomp"] = True
                if "apparmor" in low:
                    result["apparmor"] = True

consider(data.get("SecurityOptions"))
consider(data.get("securityOptions"))

host = data.get("host") or {}
security = host.get("security") or {}
if security.get("seccompProfilePath") or security.get("seccompEnabled"):
    result["seccomp"] = True
if security.get("apparmorEnabled"):
    result["apparmor"] = True
if isinstance(host.get("seccomp"), str) and host["seccomp"].lower() == "enabled":
    result["seccomp"] = True
if isinstance(host.get("apparmor"), str) and host["apparmor"].lower() == "enabled":
    result["apparmor"] = True

print(json.dumps(result))
PY
) || summary=""

    if [ -z "$summary" ]; then
        echo "❌ Failed to parse container security capabilities" >&2
        return 1
    fi

    local has_seccomp=0
    local has_apparmor=0
    if printf '%s' "$summary" | grep -q '"seccomp"[[:space:]]*:[[:space:]]*true'; then
        has_seccomp=1
    fi
    if printf '%s' "$summary" | grep -q '"apparmor"[[:space:]]*:[[:space:]]*true'; then
        has_apparmor=1
    fi

    if [ $has_seccomp -ne 1 ]; then
        echo "❌ Container runtime does not report seccomp support. Update Docker to a build with seccomp enabled." >&2
        return 1
    fi

    if [ $has_apparmor -ne 1 ]; then
        echo "❌ Container runtime does not report AppArmor support. Enable the AppArmor module on the host kernel." >&2
        return 1
    fi

    return 0
}

sanitize_docker_resource_name() {
    local name="${1:-}"
    name=$(echo "$name" | tr '[:upper:]' '[:lower:]')
    name=$(echo "$name" | tr -c 'a-z0-9_.-' '-')
    name="${name#-}"
    name="${name%-}"
    if [ -z "$name" ]; then
        name="agent"
    fi
    if [ ${#name} -gt 48 ]; then
        name="${name:0:48}"
    fi
    echo "$name"
}

get_container_volume_name() {
    local container_name="$1"
    local suffix="$2"
    local sanitized_container
    sanitized_container=$(sanitize_docker_resource_name "$container_name")
    local sanitized_suffix
    sanitized_suffix=$(sanitize_docker_resource_name "$suffix")
    printf '%s-%s\n' "$sanitized_container" "$sanitized_suffix"
}

# Validate container name
validate_container_name() {
    local name="$1"
    # Container names must match: [a-zA-Z0-9][a-zA-Z0-9_.-]*
    if [[ "$name" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]]; then
        return 0
    fi
    return 1
}

# Validate branch name
validate_branch_name() {
    local branch="$1"
    # Basic git branch name validation
    if [[ "$branch" =~ ^[a-zA-Z0-9][a-zA-Z0-9/_.-]*$ ]] && [[ ! "$branch" =~ \.\. ]] && [[ ! "$branch" =~ /$ ]]; then
        return 0
    fi
    return 1
}

# Validate image name
validate_image_name() {
    local image="$1"
    # Docker image name validation
    if [[ "$image" =~ ^[a-z0-9]+(([._-]|__)[a-z0-9]+)*(:[a-zA-Z0-9_.-]+)?$ ]]; then
        return 0
    fi
    return 1
}

# Sanitize branch name for use in container names
sanitize_branch_name() {
    local branch="$1"
    local sanitized

    sanitized="${branch//\//-}"
    sanitized="${sanitized//\\/-}"
    sanitized="${sanitized//[^[:alnum:]._-]/-}"
    sanitized=$(printf '%s' "$sanitized" | tr -s '-')
    sanitized="${sanitized##[-._]*}"
    sanitized="${sanitized%%[-._]*}"
    sanitized=$(echo "$sanitized" | tr '[:upper:]' '[:lower:]')

    if [ -z "$sanitized" ]; then
        sanitized="branch"
    fi

    echo "$sanitized"
}

# Check if git branch exists in repository
branch_exists() {
    local repo_path="$1"
    local branch_name="$2"
    
    if (cd "$repo_path" && git show-ref --verify --quiet "refs/heads/$branch_name" 2>/dev/null); then
        return 0
    fi
    return 1
}

# Get unmerged commits between branches
get_unmerged_commits() {
    local repo_path="$1"
    local base_branch="$2"
    local compare_branch="$3"
    
    (cd "$repo_path" && git log "$base_branch..$compare_branch" --oneline 2>/dev/null)
}

# Remove git branch
remove_git_branch() {
    local repo_path="$1"
    local branch_name="$2"
    local force="${3:-false}"
    
    local flag="-d"
    if [ "$force" = "true" ]; then
        flag="-D"
    fi
    
    (cd "$repo_path" && git branch "$flag" "$branch_name" 2>/dev/null)
    return $?
}

# Rename git branch
rename_git_branch() {
    local repo_path="$1"
    local old_name="$2"
    local new_name="$3"
    
    (cd "$repo_path" && git branch -m "$old_name" "$new_name" 2>/dev/null)
    return $?
}

# Create new git branch
create_git_branch() {
    local repo_path="$1"
    local branch_name="$2"
    local start_point="${3:-HEAD}"
    
    (cd "$repo_path" && git branch "$branch_name" "$start_point" 2>/dev/null)
    return $?
}

# Get repository name from path
get_repo_name() {
    local repo_path="$1"
    basename "$repo_path"
}

# Get current git branch
get_current_branch() {
    local repo_path="$1"
    cd "$repo_path" && git branch --show-current 2>/dev/null || echo "main"
}

# Convert Windows path to WSL path
convert_to_wsl_path() {
    local path="$1"
    if [[ "$path" =~ ^[A-Z]: ]]; then
        local drive
        drive=$(echo "$path" | cut -d: -f1 | tr '[:upper:]' '[:lower:]')
        local rest
        # shellcheck disable=SC1003
        rest=$(echo "$path" | cut -d: -f2 | tr '\\' '/')
        echo "/mnt/${drive}${rest}"
    else
        echo "$path"
    fi
}

# Check if container runtime (Docker) is running
check_docker_running() {
    local runtime
    runtime=$(get_container_runtime 2>/dev/null || true)

    if [ -n "$runtime" ]; then
        if $runtime info > /dev/null 2>&1; then
            CONTAINAI_CONTAINER_CMD="$runtime"
            return 0
        fi
    fi

    echo "⚠️  Docker daemon not running. Checking installation..."

    if ! command -v docker &> /dev/null; then
        echo "❌ Docker CLI not found. Install Docker Desktop or Docker Engine from https://docs.docker.com/get-docker/."
        return 1
    fi

    # Everything below assumes docker is installed; attempt to help the user start it.
    if grep -qi microsoft /proc/version 2>/dev/null; then
        echo "🔍 Detected WSL environment. Checking Docker Desktop..."

        if command -v powershell.exe &> /dev/null; then
            local docker_desktop_path="/mnt/c/Program Files/Docker/Docker/Docker Desktop.exe"

            if [ -f "$docker_desktop_path" ]; then
                echo "🚀 Starting Docker Desktop..."
                powershell.exe -Command "Start-Process 'C:\\Program Files\\Docker\\Docker\\Docker Desktop.exe'" 2>/dev/null || true

                local max_wait=60
                local waited=0
                while [ $waited -lt $max_wait ]; do
                    sleep 2
                    waited=$((waited + 2))
                    if docker info > /dev/null 2>&1; then
                        CONTAINAI_CONTAINER_CMD="docker"
                        echo "✅ Docker started successfully"
                        return 0
                    fi
                    echo "  Waiting for Docker... ($waited/$max_wait seconds)"
                done

                echo "❌ Docker failed to start within $max_wait seconds"
                echo "   Please start Docker Desktop manually and try again"
                return 1
            fi
        fi
    fi

    if [ -f /etc/init.d/docker ] || systemctl list-unit-files docker.service &> /dev/null; then
        echo "💡 Docker service is installed but not running."
        echo "   Try starting it with: sudo systemctl start docker"
        echo "   Or: sudo service docker start"
        return 1
    fi

    echo "❌ Docker is installed but not running."
    echo "   Please start Docker and try again"
    return 1
}

get_python_runner_image() {
    if [ -n "${CONTAINAI_PYTHON_IMAGE:-}" ]; then
        echo "$CONTAINAI_PYTHON_IMAGE"
    else
        echo "python:3.11-slim"
    fi
}

run_python_tool() {
    local script_path="$1"
    if [ -z "$script_path" ]; then
        echo "❌ Missing script path for python runner" >&2
        return 1
    fi
    shift || true

    local extra_mounts=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --mount)
                if [[ $# -ge 2 ]]; then
                    extra_mounts+=("$2")
                    shift 2
                    continue
                else
                    break
                fi
                ;;
            --)
                shift
                break
                ;;
            *)
                break
                ;;
        esac
    done
    local script_args=("$@")

    local repo_root="${CONTAINAI_REPO_ROOT:-$CONTAINAI_REPO_ROOT_DEFAULT}"
    if [ ! -d "$repo_root" ]; then
        echo "❌ Repo root '$repo_root' not found for python runner" >&2
        return 1
    fi

    if ! check_docker_running; then
        return 1
    fi

    local container_cmd
    container_cmd=$(get_active_container_cmd)
    local image
    image=$(get_python_runner_image)

    local docker_args=("run" "--rm" "-w" "$repo_root" "-e" "PYTHONUNBUFFERED=1")
    if command -v id >/dev/null 2>&1; then
        docker_args+=("--user" "$(id -u):$(id -g)")
    fi
    docker_args+=("-e" "TZ=${TZ:-UTC}")
    docker_args+=("--pids-limit" "$CONTAINAI_HELPER_PIDS_LIMIT")
    docker_args+=("--security-opt" "no-new-privileges")
    docker_args+=("--cap-drop" "ALL")

    if [ -n "$CONTAINAI_HELPER_MEMORY" ]; then
        docker_args+=("--memory" "$CONTAINAI_HELPER_MEMORY")
    fi

    local helper_network="${CONTAINAI_HELPER_NETWORK_POLICY:-loopback}"
    case "$helper_network" in
        loopback|none)
            docker_args+=("--network" "none")
            ;;
        host)
            docker_args+=("--network" "host")
            ;;
        bridge|"" )
            docker_args+=("--network" "bridge")
            ;;
        *)
            docker_args+=("--network" "$helper_network")
            ;;
    esac

    docker_args+=("--tmpfs" "/tmp:rw,nosuid,nodev,noexec,size=64m")
    docker_args+=("--tmpfs" "/var/tmp:rw,nosuid,nodev,noexec,size=32m")

    while IFS='=' read -r name value; do
        [ -z "$name" ] && continue
        docker_args+=("-e" "${name}=${value}")
    done < <(env | grep '^CONTAINAI_' || true)

    local seccomp_profile=""
    if [ "${CONTAINAI_DISABLE_HELPER_SECCOMP:-0}" != "1" ]; then
        seccomp_profile=$(resolve_seccomp_profile_path "$repo_root" 2>/dev/null || true)
    fi
    if [ -n "$seccomp_profile" ]; then
        docker_args+=("--security-opt" "seccomp=$seccomp_profile")
    fi

    local mounts=("$repo_root")
    [ -n "${HOME:-}" ] && mounts+=("$HOME")
    local mount_path
    for mount_path in "${extra_mounts[@]}"; do
        [ -n "$mount_path" ] && mounts+=("$mount_path")
    done

    local mounted=()
    local path existing skip
    for path in "${mounts[@]}"; do
        [ -z "$path" ] && continue
        skip=0
        for existing in "${mounted[@]}"; do
            if [ "$existing" = "$path" ]; then
                skip=1
                break
            fi
        done
        if [ "$skip" -eq 1 ]; then
            continue
        fi
        mounted+=("$path")
        if [ ! -d "$path" ]; then
            mkdir -p "$path" 2>/dev/null || true
        fi
        docker_args+=("--mount" "type=bind,src=${path},dst=${path}")
    done

    docker_args+=("$image" "python3" "$script_path")
    if [ ${#script_args[@]} -gt 0 ]; then
        docker_args+=("${script_args[@]}")
    fi

    "$container_cmd" "${docker_args[@]}"
}

get_container_label() {
    local container_name="$1"
    local label_key="$2"
    local value
    value=$(container_cli inspect -f "{{ index .Config.Labels \"${label_key}\" }}" "$container_name" 2>/dev/null || true)
    if [ "$value" = "<no value>" ]; then
        value=""
    fi
    printf '%s' "$value"
}

copy_agent_data_exports() {
    local container_name="$1"
    local agent_name="$2"
    local dest_root="$3"
    local container_path="/run/agent-data-export/${agent_name}"

    if [ -z "$agent_name" ]; then
        return 1
    fi

    mkdir -p "$dest_root"
    local output
    if ! output=$(container_cli cp "${container_name}:${container_path}" "$dest_root" 2>&1); then
        if echo "$output" | grep -qiE 'no such file|could not find'; then
            return 1
        fi
        echo "⚠️  Failed to copy agent data export: $output" >&2
        return 1
    fi
    return 0
}

merge_agent_data_exports() {
    local agent_name="$1"
    local staged_dir="$2"
    local repo_root="$3"
    local home_dir="$4"
    local packager="$repo_root/host/utils/package-agent-data.py"

    if [ -z "$agent_name" ] || [ ! -d "$staged_dir" ] || [ ! -f "$packager" ]; then
        return 1
    fi

    local key_root="$home_dir/.config/containai/data-hmac/${agent_name}"
    mkdir -p -- "$key_root"

    local merged=false
    while IFS= read -r -d '' manifest_path; do
        local base_name
        base_name="$(basename "$manifest_path" .manifest.json)"
        local tar_path="${manifest_path%.manifest.json}.tar"
        if [ ! -f "$tar_path" ]; then
            echo "⚠️  Missing tarball for ${agent_name} payload ${base_name}; skipping" >&2
            continue
        fi

        local session_id
        if ! session_id=$(python3 - "$manifest_path" <<'PYINNER'
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as fh:
    data = json.load(fh)
session = data.get('session') or data.get('session_id')
if not session:
    raise SystemExit('missing-session')
print(session)
PYINNER
        ); then
            echo "⚠️  Could not determine session id for ${agent_name} payload ${base_name}; skipping" >&2
            continue
        fi

        local key_path="$key_root/${session_id}.key"
        if [ ! -f "$key_path" ]; then
            echo "⚠️  Missing HMAC key for ${agent_name} session ${session_id}; skipping" >&2
            continue
        fi

        local output_dir="$home_dir/.containai/${agent_name}/imports/${session_id}"
        mkdir -p -- "$output_dir"

        if run_python_tool "$packager" --mount "$staged_dir" --mount "$home_dir" -- \
            --mode merge \
            --agent "$agent_name" \
            --session-id "$session_id" \
            --manifest "$manifest_path" \
            --tar "$tar_path" \
            --target-home "$output_dir" \
            --require-hmac \
            --hmac-key-file "$key_path" >/dev/null; then
            merged=true
            rm -f -- "$manifest_path" "$tar_path"
        else
            echo "❌ HMAC validation failed for ${agent_name} session ${session_id}; payload retained for inspection" >&2
        fi
    done < <(find "$staged_dir" -type f -name '*.manifest.json' -print0)

    if [ "$merged" = true ]; then
        echo "📥 Merged ${agent_name} data export into host profile"
        return 0
    fi
    return 1
}

process_agent_data_exports() {
    local container_name="$1"
    local repo_root="$2"
    local home_dir="$3"
    local staging_root="${4:-}"

    if [ -z "$container_name" ] || [ -z "$repo_root" ] || [ -z "$home_dir" ]; then
        return 0
    fi

    local agent_name
    agent_name=$(get_container_label "$container_name" "containai.agent")
    if [ -z "$agent_name" ]; then
        return 0
    fi

    local cleanup_dir=false
    if [ -z "$staging_root" ]; then
        staging_root=$(mktemp -d "${TMPDIR:-/tmp}/agent-export.XXXXXX")
        cleanup_dir=true
    fi

    if copy_agent_data_exports "$container_name" "$agent_name" "$staging_root"; then
        local staged_path="$staging_root/${agent_name}"
        merge_agent_data_exports "$agent_name" "$staged_path" "$repo_root" "$home_dir"
        rm -rf "$staged_path"
    fi

    if [ "$cleanup_dir" = true ]; then
        rm -rf "$staging_root"
    fi
}

# Pull and tag image with retry logic
pull_and_tag_image() {
    local target="$1"
    local max_retries="${2:-3}"
    local retry_delay="${3:-2}"
    local registry_image=""
    local local_image=""
    local registry_prefix="${CONTAINAI_REGISTRY:-ghcr.io/novotnyllc}"
    local prefix="${CONTAINAI_IMAGE_PREFIX:-containai-dev}"
    local tag="${CONTAINAI_IMAGE_TAG:-devlocal}"

    case "$target" in
        base)
            registry_image="${registry_prefix}/${prefix}-base:${tag}"
            local_image="${prefix}-base:${tag}"
            ;;
        all|all-agents)
            registry_image="${registry_prefix}/${prefix}:${tag}"
            local_image="${prefix}:${tag}"
            ;;
        proxy)
            registry_image="${registry_prefix}/${prefix}-proxy:${tag}"
            local_image="${prefix}-proxy:${tag}"
            ;;
        *)
            registry_image="${registry_prefix}/${prefix}-${target}:${tag}"
            local_image="${prefix}-${target}:${tag}"
            ;;
    esac

    if [ "${CONTAINAI_PROFILE:-dev}" = "dev" ]; then
        echo "⏭️  Dev profile: using local image ${local_image} (skip registry pull)"
        return 0
    fi

    echo "📦 Checking for image updates (${target})..."

    local attempt=0
    local pulled=false

    while [ "$attempt" -lt "$max_retries" ] && [ "$pulled" = "false" ]; do
        attempt=$((attempt + 1))

        if [ $attempt -gt 1 ]; then
            echo "  ⚠️  Retry attempt $attempt of $max_retries..."
        fi

        if container_cli pull --quiet "$registry_image" 2>/dev/null; then
            container_cli tag "$registry_image" "$local_image" 2>/dev/null || true
            pulled=true
        else
            if [ "$attempt" -lt "$max_retries" ]; then
                sleep "$retry_delay"
            fi
        fi
    done

    if [ "$pulled" = "false" ]; then
        echo "  ⚠️  Warning: Could not pull latest image, using cached version"
    fi
}

# Check if container exists
container_exists() {
    local container_name="$1"
    container_cli ps -a --filter "name=^${container_name}$" --format "{{.Names}}" 2>/dev/null | grep -q "^${container_name}$"
}

# Get container status
get_container_status() {
    local container_name="$1"
    container_cli inspect -f '{{.State.Status}}' "$container_name" 2>/dev/null || echo "not-found"
}

# Push changes to local remote
push_to_local() {
    local container_name="$1"
    local skip_push="${2:-false}"
    
    if [ "$skip_push" = "true" ]; then
        echo "⏭️  Skipping git push (--no-push specified)"
        return 0
    fi
    
    echo "💾 Pushing changes to local remote..."
    # shellcheck disable=SC2016
    container_cli exec "$container_name" bash -c '
        cd /workspace
        if [ -n "$(git status --porcelain)" ]; then
            echo "📝 Uncommitted changes detected"
            read -p "Commit changes before push? (y/n) " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                read -p "Commit message: " msg
                git add -A
                git commit -m "$msg"
            fi
        fi
        
        if git push 2>&1; then
            echo "✅ Changes pushed to local remote"
        else
            echo "⚠️  Failed to push (may be up to date)"
        fi
    ' 2>/dev/null || echo "⚠️  Could not push changes"
}

# List all agent containers
list_agent_containers() {
    container_cli ps -a --filter "label=containai.type=agent" \
        --format "table {{.Names}}\t{{.Status}}\t{{.Image}}\t{{.CreatedAt}}"
}

# Get proxy container name for agent
get_proxy_container() {
    local agent_container="$1"
    container_cli inspect -f '{{ index .Config.Labels "containai.proxy-container" }}' "$agent_container" 2>/dev/null
}

# Get proxy network name for agent
get_proxy_network() {
    local agent_container="$1"
    container_cli inspect -f '{{ index .Config.Labels "containai.proxy-network" }}' "$agent_container" 2>/dev/null
}

# Remove container and associated resources
remove_container_with_sidecars() {
    local container_name="$1"
    local skip_push="${2:-false}"
    local keep_branch="${3:-false}"
    local cache_root="${CONTAINAI_SESSION_CACHE:-${HOME:-/tmp}/.containai/session-cache}"
    
    if ! container_exists "$container_name"; then
        echo "❌ Container '$container_name' does not exist"
        return 1
    fi
    
    # Get container labels to find repo and branch info
    local agent_branch
    agent_branch=$(container_cli inspect -f '{{ index .Config.Labels "containai.branch" }}' "$container_name" 2>/dev/null || true)
    local repo_path
    repo_path=$(container_cli inspect -f '{{ index .Config.Labels "containai.repo-path" }}' "$container_name" 2>/dev/null || true)
    local local_remote_path
    local_remote_path=$(container_cli inspect -f '{{ index .Config.Labels "containai.local-remote" }}' "$container_name" 2>/dev/null || true)
    
    local repo_root="${CONTAINAI_REPO_ROOT:-$CONTAINAI_REPO_ROOT_DEFAULT}"
    local home_dir="${HOME:-}"
    if [ -z "$home_dir" ] && command -v getent >/dev/null 2>&1; then
        home_dir="$(getent passwd "$(id -u)" | awk -F: '{print $6}' 2>/dev/null || true)"
    fi
    [ -n "$home_dir" ] || home_dir="/tmp"
    local container_status
    container_status=$(get_container_status "$container_name")

    # Push changes first while container is running
    if [ "$container_status" = "running" ]; then
        push_to_local "$container_name" "$skip_push"
        echo "⏹️  Stopping container to finalize exports..."
        if ! container_cli stop "$container_name" >/dev/null 2>&1; then
            echo "⚠️  Failed to stop container gracefully; exports may be incomplete" >&2
        fi
        container_status=$(get_container_status "$container_name")
    fi

    process_agent_data_exports "$container_name" "$repo_root" "$home_dir"
    
    # Get associated resources
    local proxy_container
    proxy_container=$(get_proxy_container "$container_name")
    local proxy_network
    proxy_network=$(get_proxy_network "$container_name")
    
    # Remove main container
    echo "🗑️  Removing container: $container_name"
    container_cli rm -f "$container_name" 2>/dev/null || true
    
    # Remove proxy if exists
    if [ -n "$proxy_container" ] && container_exists "$proxy_container"; then
        echo "🗑️  Removing proxy: $proxy_container"
        container_cli rm -f "$proxy_container" 2>/dev/null || true
    fi
    
    # Remove network if exists and no containers attached
    if [ -n "$proxy_network" ]; then
        local attached
        attached=$(container_cli network inspect -f '{{range .Containers}}{{.Name}} {{end}}' "$proxy_network" 2>/dev/null)
        if [ -z "$attached" ]; then
            echo "🗑️  Removing network: $proxy_network"
            container_cli network rm "$proxy_network" 2>/dev/null || true
        fi
    fi

    # Remove cached session artifacts for this container
    if [ -n "$cache_root" ] && [ -d "$cache_root/${container_name}" ]; then
        echo "🧹 Removing session cache: $cache_root/${container_name}"
        rm -rf "$cache_root/${container_name}" || true
    fi

    if [ -n "$agent_branch" ] && [ -n "$repo_path" ] && [ -d "$repo_path" ] && [ -n "$local_remote_path" ]; then
        echo ""
        echo "🔄 Syncing agent branch back to host repository..."
        sync_local_remote_to_host "$repo_path" "$local_remote_path" "$agent_branch"
    fi
    
    # Clean up agent branch in host repo if applicable
    if [ "$keep_branch" != "true" ] && [ -n "$agent_branch" ] && [ -n "$repo_path" ] && [ -d "$repo_path" ]; then
        echo ""
        echo "🌿 Cleaning up agent branch: $agent_branch"
        
        if branch_exists "$repo_path" "$agent_branch"; then
            # Check if branch has unpushed work
            local current_branch
            current_branch=$(cd "$repo_path" && git branch --show-current 2>/dev/null)
            local unmerged_commits
            unmerged_commits=$(get_unmerged_commits "$repo_path" "$current_branch" "$agent_branch")
            
            if [ -n "$unmerged_commits" ]; then
                echo "   ⚠️  Branch has unmerged commits - keeping branch"
                echo "   Manually merge or delete: git branch -D $agent_branch"
            else
                if remove_git_branch "$repo_path" "$agent_branch" "true"; then
                    echo "   ✅ Agent branch removed"
                else
                    echo "   ⚠️  Could not remove agent branch"
                fi
            fi
        fi
    fi
    
    echo ""
    echo "✅ Cleanup complete"
}

# Generate per-session MITM CA for the Squid proxy
generate_session_mitm_ca() {
    local output_dir="$1"
    if [ -z "$output_dir" ]; then
        echo "❌ MITM CA output directory not provided" >&2
        return 1
    fi
    if ! command -v openssl >/dev/null 2>&1; then
        echo "❌ openssl is required to generate MITM CA materials" >&2
        return 1
    fi
    mkdir -p "$output_dir"
    local original_umask
    original_umask=$(umask)
    umask 077
    local ca_key="$output_dir/proxy-ca.key"
    local ca_cert="$output_dir/proxy-ca.crt"
    if ! openssl req -x509 -newkey rsa:4096 -sha256 -days 2 -nodes \
        -subj "/CN=ContainAI Proxy MITM CA" \
        -addext "basicConstraints=critical,CA:TRUE,pathlen:0" \
        -addext "keyUsage=critical,keyCertSign,cRLSign,digitalSignature" \
        -addext "subjectKeyIdentifier=hash" \
        -addext "authorityKeyIdentifier=keyid:always,issuer" \
        -keyout "$ca_key" \
        -out "$ca_cert" >/dev/null 2>&1; then
        umask "$original_umask"
        echo "❌ Failed to generate MITM CA materials" >&2
        return 1
    fi
    umask "$original_umask"
    chmod 600 "$ca_key" "$ca_cert" || true
    SESSION_MITM_CA_CERT="$ca_cert"
    SESSION_MITM_CA_KEY="$ca_key"
    export SESSION_MITM_CA_CERT SESSION_MITM_CA_KEY
    return 0
}

generate_log_broker_certs() {
    local output_dir="$1"
    mkdir -p "$output_dir"
    local original_umask
    original_umask=$(umask)
    umask 077
    local ca_key="$output_dir/log-ca.key"
    local ca_crt="$output_dir/log-ca.crt"
    local server_key="$output_dir/log-server.key"
    local server_crt="$output_dir/log-server.crt"
    local client_key="$output_dir/log-client.key"
    local client_crt="$output_dir/log-client.crt"

    if [ ! -f "$ca_crt" ] || [ ! -f "$ca_key" ]; then
        openssl req -x509 -newkey rsa:2048 -nodes -subj "/CN=ContainAI Log Broker CA" -days 2 \
            -keyout "$ca_key" -out "$ca_crt" >/dev/null 2>&1 || true
    fi
    if [ ! -f "$server_crt" ] || [ ! -f "$server_key" ]; then
        openssl req -new -newkey rsa:2048 -nodes -subj "/CN=localhost" -keyout "$server_key" -out "$output_dir/server.csr" >/dev/null 2>&1 || true
        openssl x509 -req -in "$output_dir/server.csr" -CA "$ca_crt" -CAkey "$ca_key" -CAcreateserial -out "$server_crt" -days 2 -sha256 >/dev/null 2>&1 || true
    fi
    if [ ! -f "$client_crt" ] || [ ! -f "$client_key" ]; then
        openssl req -new -newkey rsa:2048 -nodes -subj "/CN=containai-forwarder" -keyout "$client_key" -out "$output_dir/client.csr" >/dev/null 2>&1 || true
        openssl x509 -req -in "$output_dir/client.csr" -CA "$ca_crt" -CAkey "$ca_key" -CAcreateserial -out "$client_crt" -days 2 -sha256 >/dev/null 2>&1 || true
    fi
    chmod 600 "$ca_key" "$ca_crt" "$server_key" "$server_crt" "$client_key" "$client_crt" 2>/dev/null || true
    umask "$original_umask"
}

find_free_port() {
    python3 - <<'PY'
import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
port = s.getsockname()[1]
s.close()
print(port)
PY
}

# Ensure squid proxy is running (for launch-agent)
start_proxy_log_streamer() {
    local proxy_container="$1"
    local log_dir="$2"
    local agent="$3"
    local session="$4"
    [ -z "$proxy_container" ] && return 0
    [ -z "$log_dir" ] && return 0
    mkdir -p "$log_dir"
    local log_file="$log_dir/access.log"
    local meta_file="$log_dir/meta"
    printf "agent=%s\nsession=%s\ncontainer=%s\n" "${agent:-unknown}" "${session:-unknown}" "$proxy_container" > "$meta_file"
    if ! container_exists "$proxy_container"; then
        echo "⚠️  Proxy container $proxy_container not found for log streaming" >&2
        return 1
    fi
    nohup container_cli logs -f "$proxy_container" >"$log_file" 2>&1 &
    echo $! > "$log_dir/streamer.pid"
    return 0
}

ensure_squid_proxy() {
    local network_name="$1"
    local proxy_container="$2"
    local proxy_image="$3"
    local agent_container="$4"
    local squid_allowed_domains="${5:-*.github.com,*.githubcopilot.com,*.nuget.org}"
    local helper_acl_file="${6:-}"
    local agent_id="${7:-}"
    local session_id="${8:-}"
    local mitm_ca_cert="${9:-${SESSION_MITM_CA_CERT:-}}"
    local mitm_ca_key="${10:-${SESSION_MITM_CA_KEY:-}}"
    local proxy_seccomp="${PROXY_SECCOMP_PROFILE_PATH:-${SECCOMP_PROFILE_PATH:-}}"
    local proxy_apparmor="${PROXY_APPARMOR_PROFILE:-containai-proxy}"
    
    if [ -z "$mitm_ca_cert" ] || [ -z "$mitm_ca_key" ] || [ ! -f "$mitm_ca_cert" ] || [ ! -f "$mitm_ca_key" ]; then
        echo "❌ MITM CA certificate and key are required to start the Squid proxy" >&2
        return 1
    fi
    
    # Create network if needed
    if ! container_cli network inspect "$network_name" >/dev/null 2>&1; then
        container_cli network create "$network_name" >/dev/null
    fi
    
    # Recreate proxy to ensure per-session CA and ACLs are applied
    if container_exists "$proxy_container"; then
        container_cli rm -f "$proxy_container" >/dev/null 2>&1 || true
    fi
    
    if ! container_cli image inspect "$proxy_image" >/dev/null 2>&1; then
        echo "📥 Proxy image '$proxy_image' not found locally; pulling..." >&2
        if ! container_cli pull "$proxy_image" >/dev/null 2>&1; then
            echo "❌ Failed to pull proxy image '$proxy_image'" >&2
            return 1
        fi
    fi

    local -a proxy_args=(
        -d
        --name "$proxy_container"
        --hostname "$proxy_container"
        --network "$network_name"
        --restart no
        --read-only
        --cap-drop=ALL
        --security-opt "no-new-privileges:true"
        ${proxy_seccomp:+--security-opt "seccomp=${proxy_seccomp}"}
        ${proxy_apparmor:+--security-opt "apparmor=${proxy_apparmor}"}
        --pids-limit 256
        -e "SQUID_ALLOWED_DOMAINS=$squid_allowed_domains"
        -e "SQUID_MITM_CA_CERT=/etc/squid/mitm/ca.crt"
        -e "SQUID_MITM_CA_KEY=/etc/squid/mitm/ca.key"
        --tmpfs "/var/log/squid:rw,nosuid,nodev,noexec,size=64m,mode=750"
        --tmpfs "/var/spool/squid:rw,nosuid,nodev,noexec,size=128m,mode=750"
        --tmpfs "/var/run/squid:rw,nosuid,nodev,noexec,size=16m,mode=750"
        --label "containai.proxy-of=$agent_container"
        --label "containai.proxy-image=$proxy_image"
        -v "$mitm_ca_cert:/etc/squid/mitm/ca.crt:ro"
        -v "$mitm_ca_key:/etc/squid/mitm/ca.key:ro"
    )
    if [ -n "$helper_acl_file" ] && [ -f "$helper_acl_file" ]; then
        proxy_args+=("-v" "$helper_acl_file:/etc/squid/helper-acls.conf:ro")
    fi
    [ -n "$agent_id" ] && proxy_args+=("-e" "CA_AGENT_ID=$agent_id")
    [ -n "$session_id" ] && proxy_args+=("-e" "CA_SESSION_ID=$session_id")
    proxy_args+=("$proxy_image")
    container_cli run "${proxy_args[@]}" >/dev/null
}

# Generate repository setup script for container
start_proxy_log_streamer() {
    local proxy_container="$1"
    local log_dir="$2"
    local agent="$3"
    local session="$4"
    [ -z "$proxy_container" ] && return 0
    [ -z "$log_dir" ] && return 0
    mkdir -p "$log_dir"
    local log_file="$log_dir/access.log"
    local meta_file="$log_dir/meta"
    printf "agent=%s\nsession=%s\ncontainer=%s\n" "${agent:-unknown}" "${session:-unknown}" "$proxy_container" > "$meta_file"
    if ! container_exists "$proxy_container"; then
        echo "⚠️  Proxy container $proxy_container not found for log streaming" >&2
        return 1
    fi
    nohup container_cli logs -f "$proxy_container" >"$log_file" 2>&1 &
    echo $! > "$log_dir/streamer.pid"
    return 0
}

start_proxy_log_pipeline() {
    local proxy_container="$1"
    local proxy_network="$2"
    local log_dir="$3"
    local cert_dir="$4"
    local broker_name="${proxy_container}-log-broker"
    local forwarder_name="${proxy_container}-log-forwarder"
    local broker_port="4433"
    local forwarder_image="${LOG_FORWARDER_IMAGE:-${CONTAINAI_IMAGE_PREFIX:-containai-dev}-log-forwarder:${CONTAINAI_IMAGE_TAG:-devlocal}}"
    local broker_image="${LOG_BROKER_IMAGE:-$forwarder_image}"
    local forwarder_seccomp="${LOG_FORWARDER_SECCOMP_PROFILE_PATH:-${SECCOMP_PROFILE_PATH:-}}"
    local forwarder_apparmor="${LOG_FORWARDER_APPARMOR_PROFILE:-containai-log-forwarder}"
    local broker_seccomp="${LOG_BROKER_SECCOMP_PROFILE_PATH:-${SECCOMP_PROFILE_PATH:-}}"
    local broker_apparmor="${LOG_BROKER_APPARMOR_PROFILE:-containai-log-forwarder}"

    mkdir -p "$log_dir" "$cert_dir"
    generate_log_broker_certs "$cert_dir"

    if ! container_exists "$proxy_container"; then
        echo "❌ Cannot start log pipeline; proxy container '$proxy_container' missing" >&2
        return 1
    fi

    stop_proxy_log_pipeline "$proxy_container"

    if ! container_cli run -d --name "$broker_name" --hostname "$broker_name" \
        --network "$proxy_network" \
        --read-only \
        --cap-drop=ALL \
        --security-opt "no-new-privileges:true" \
        ${broker_seccomp:+--security-opt "seccomp=${broker_seccomp}"} \
        ${broker_apparmor:+--security-opt "apparmor=${broker_apparmor}"} \
        --pids-limit 128 \
        --memory 128m \
        -u 65532:65532 \
        -v "$cert_dir:/certs:ro" \
        -v "$log_dir:/logs" \
        --tmpfs /tmp:rw,nosuid,nodev,noexec,size=16m,mode=755 \
        --label "containai.log-of=$proxy_container" \
        --label "containai.log-role=broker" \
        "$broker_image" \
        sh -c "openssl s_server -quiet -accept ${broker_port} -cert /certs/log-server.crt -key /certs/log-server.key -CAfile /certs/log-ca.crt -Verify 1 >>/logs/access.log 2>>/logs/broker.err"
    then
        echo "❌ Failed to start log broker container $broker_name" >&2
        return 1
    fi

    if ! container_cli run -d --name "$forwarder_name" --hostname "$forwarder_name" \
        --network "$proxy_network" \
        --read-only \
        --cap-drop=ALL \
        --security-opt "no-new-privileges:true" \
        ${forwarder_seccomp:+--security-opt "seccomp=${forwarder_seccomp}"} \
        ${forwarder_apparmor:+--security-opt "apparmor=${forwarder_apparmor}"} \
        --pids-limit 128 \
        --memory 128m \
        -u 65532:65532 \
        --volumes-from "$proxy_container":ro \
        -v "$cert_dir:/certs:ro" \
        --tmpfs /tmp:rw,nosuid,nodev,noexec,size=16m,mode=755 \
        --label "containai.log-of=$proxy_container" \
        --label "containai.log-role=forwarder" \
        "$forwarder_image" \
        sh -c "touch /var/log/squid/access.log && tail -F /var/log/squid/access.log | openssl s_client -quiet -connect ${broker_name}:${broker_port} -cert /certs/log-client.crt -key /certs/log-client.key -CAfile /certs/log-ca.crt >/dev/null 2>>/tmp/forwarder.err"
    then
        echo "❌ Failed to start log forwarder container $forwarder_name" >&2
        container_cli rm -f "$broker_name" >/dev/null 2>&1 || true
        return 1
    fi
    return 0
}

stop_proxy_log_pipeline() {
    local proxy_container="$1"
    if [ -z "$proxy_container" ]; then
        return 0
    fi
    local ids
    ids=$(container_cli ps -aq --filter "label=containai.log-of=${proxy_container}" 2>/dev/null || true)
    if [ -n "$ids" ]; then
        container_cli rm -f $ids >/dev/null 2>&1 || true
    fi
}

generate_repo_setup_script() {
    cat << 'SETUP_SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

TARGET_DIR="${WORKSPACE_DIR:-/workspace}"
mkdir -p "$TARGET_DIR"

# Clean target directory
if [ -d "$TARGET_DIR" ] && [ "$(find "$TARGET_DIR" -mindepth 1 -maxdepth 1 | wc -l)" -gt 0 ]; then
    find "$TARGET_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
fi

if [ "$SOURCE_TYPE" = "prompt" ]; then
    echo "🆕 Prompt session requested without repository: leaving workspace empty"
    exit 0
elif [ "$SOURCE_TYPE" = "url" ]; then
    echo "🌐 Cloning repository from $GIT_URL..."
    git clone "$GIT_URL" "$TARGET_DIR"
else
    echo "📁 Copying repository from host..."
    cp -a /tmp/source-repo/. "$TARGET_DIR/"
fi

cd "$TARGET_DIR"

# Configure local remote when cloning from the host copy
if [ "$SOURCE_TYPE" = "local" ]; then
    if [ -n "$LOCAL_REMOTE_URL" ]; then
        if git remote get-url local >/dev/null 2>&1; then
            git remote set-url local "$LOCAL_REMOTE_URL"
        else
            git remote add local "$LOCAL_REMOTE_URL"
        fi
        git config remote.pushDefault local
        git config remote.local.pushurl "$LOCAL_REMOTE_URL" 2>/dev/null || true
    elif [ -n "$LOCAL_REPO_PATH" ]; then
        # Backward compatibility for older launchers
        if ! git remote get-url local >/dev/null 2>&1; then
            git remote add local "$LOCAL_REPO_PATH"
        fi
        git config remote.pushDefault local
    fi
fi

# Remove upstream origin to keep the container isolated from the source remote
if git remote get-url origin >/dev/null 2>&1; then
    git remote remove origin
fi

# Create and checkout branch
if [ -n "$AGENT_BRANCH" ]; then
    BRANCH_NAME="$AGENT_BRANCH"
    if ! git show-ref --verify --quiet "refs/heads/$BRANCH_NAME"; then
        git checkout -b "$BRANCH_NAME"
    else
        git checkout "$BRANCH_NAME"
    fi
fi

echo "✅ Repository setup complete"
SETUP_SCRIPT
}

# Sync commits from secure bare remote back into host repository
sync_local_remote_to_host() {
    local repo_path="$1"
    local local_remote_path="$2"
    local agent_branch="$3"

    if [ -z "$repo_path" ] || [ -z "$local_remote_path" ] || [ -z "$agent_branch" ]; then
        return 0
    fi

    if [ ! -d "$repo_path/.git" ]; then
        return 0
    fi

    if [ ! -d "$local_remote_path" ]; then
        echo "⚠️  Secure remote missing at $local_remote_path" >&2
        return 0
    fi

    # Ensure bare remote actually has the branch
    if ! git --git-dir="$local_remote_path" rev-parse --verify --quiet "refs/heads/$agent_branch"; then
        return 0
    fi

    (
        cd "$repo_path" || exit 0

        local temp_ref="refs/containai-sync/${agent_branch// /-}"
        if ! git fetch "$local_remote_path" "$agent_branch:$temp_ref" >/dev/null 2>&1; then
            echo "⚠️  Failed to fetch agent branch from secure remote" >&2
            exit 0
        fi

        local fetched_sha
        fetched_sha=$(git rev-parse "$temp_ref" 2>/dev/null) || exit 0
        local current_branch
        current_branch=$(git branch --show-current 2>/dev/null || echo "")

        if git show-ref --verify --quiet "refs/heads/$agent_branch"; then
            if [ "$current_branch" = "$agent_branch" ]; then
                local worktree_state
                worktree_state=$(git status --porcelain 2>/dev/null)
                if [ -n "$worktree_state" ]; then
                    echo "⚠️  Working tree dirty on $agent_branch; skipped auto-sync" >&2
                else
                    if git merge --ff-only "$temp_ref" >/dev/null 2>&1; then
                        echo "✅ Host branch '$agent_branch' fast-forwarded from secure remote"
                    else
                        echo "⚠️  Unable to fast-forward '$agent_branch' (merge required)" >&2
                    fi
                fi
            else
                if git update-ref "refs/heads/$agent_branch" "$fetched_sha" >/dev/null 2>&1; then
                    echo "✅ Host branch '$agent_branch' updated from secure remote"
                else
                    echo "⚠️  Failed to update branch '$agent_branch'" >&2
                fi
            fi
        else
            if git branch "$agent_branch" "$temp_ref" >/dev/null 2>&1; then
                echo "✅ Created branch '$agent_branch' from secure remote"
            else
                echo "⚠️  Failed to create branch '$agent_branch'" >&2
            fi
        fi

        git update-ref -d "$temp_ref" >/dev/null 2>&1 || true
    )
}
