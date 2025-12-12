#!/usr/bin/env bash
# Common functions for agent management scripts
set -euo pipefail

COMMON_FUNCTIONS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# Internal bootstrap: where this script lives. NOT necessarily a git repo in prod.
_CONTAINAI_SCRIPT_ROOT=$(cd "$COMMON_FUNCTIONS_DIR/../.." && pwd)

CONTAINAI_PROFILE_FILE="${CONTAINAI_PROFILE_FILE:-$_CONTAINAI_SCRIPT_ROOT/profile.env}"
CONTAINAI_PROFILE="dev"
# CONTAINAI_HOME: The user-specific state directory (logs, session cache, local remotes)
if [ "${CONTAINAI_PROFILE}" = "prod" ]; then
    CONTAINAI_HOME="${HOME}/.containai"
else
    CONTAINAI_HOME="${HOME}/.containai-${CONTAINAI_PROFILE}"
fi
export CONTAINAI_HOME

# CONTAINAI_ROOT: The ContainAI installation directory (dev clone or prod /opt/containai/current)
CONTAINAI_ROOT="$_CONTAINAI_SCRIPT_ROOT"
# Defaults for dev; overridden by env-detect profile file.
CONTAINAI_CONFIG_DIR="${HOME}/.config/containai-${CONTAINAI_PROFILE}"
CONTAINAI_DATA_ROOT="${HOME}/.local/share/containai-${CONTAINAI_PROFILE}"
CONTAINAI_CACHE_ROOT="${HOME}/.cache/containai-${CONTAINAI_PROFILE}"
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
# Security profiles MUST be root-owned to prevent tampering. System location used by both prod and dev.
# This path is hardcoded and NOT overridable - security critical.
# Guard against re-sourcing this file (readonly can only be set once)
if [[ -z "${_CONTAINAI_COMMON_FUNCTIONS_LOADED:-}" ]]; then
    readonly CONTAINAI_SYSTEM_PROFILES_DIR="/opt/containai/profiles"
    readonly _CONTAINAI_COMMON_FUNCTIONS_LOADED=1
fi
CONTAINAI_BROKER_SCRIPT="${CONTAINAI_BROKER_SCRIPT:-${_CONTAINAI_SCRIPT_ROOT}/host/utils/secret_broker.py}"
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

_resolve_apparmor_channel() {
    local channel="${CONTAINAI_LAUNCHER_CHANNEL:-${CONTAINAI_PROFILE:-dev}}"
    case "$channel" in
        prod|nightly|dev) ;; 
        *) channel="dev" ;;
    esac
    printf '%s' "$channel"
}

_format_apparmor_profile_name() {
    local base="$1"
    local channel="$2"
    if [ -z "$base" ]; then
        return 1
    fi
    printf '%s-%s' "$base" "$channel"
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

# Collects a fingerprint of prerequisite check inputs for caching.
# Args:
#   $1: containai_root - The ContainAI installation directory
_collect_prereq_fingerprint() {
    local containai_root="$1"
    local script_path="$containai_root/host/utils/verify-prerequisites.sh"
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

# Ensures prerequisites have been verified (uses cached result if inputs unchanged).
# Args:
#   $1: containai_root - The ContainAI installation directory (optional, defaults to CONTAINAI_ROOT)
ensure_prerequisites_verified() {
    local containai_root="${1:-${CONTAINAI_ROOT:-$_CONTAINAI_SCRIPT_ROOT}}"
    if [ "${CONTAINAI_DISABLE_AUTO_PREREQ_CHECK:-0}" = "1" ]; then
        return 0
    fi
    local script_path="$containai_root/host/utils/verify-prerequisites.sh"
    if [ ! -x "$script_path" ]; then
        return 0
    fi
    local fingerprint
    fingerprint=$(_collect_prereq_fingerprint "$containai_root" 2>/dev/null || echo "")
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

# ============================================================================
# GIT-SPECIFIC FUNCTIONS
# These functions require a git repository and will NOT work with production
# installs at /opt/containai/current (which have no .git directory).
# The $repo_root parameter here refers specifically to a git repository root.
# ============================================================================

# Gets the HEAD commit hash from a git repository.
# Args: $1 - repo_root: Path to a git repository (must contain .git)
# Returns: The HEAD commit SHA, or fails if not a git repo.
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
    local repo_root="${CONTAINAI_ROOT:-$_CONTAINAI_SCRIPT_ROOT}"
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
            CONTAINAI_HOME) CONTAINAI_HOME="$value" ;;
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
    export CONTAINAI_PROFILE CONTAINAI_ROOT CONTAINAI_HOME CONTAINAI_CONFIG_DIR CONTAINAI_DATA_ROOT CONTAINAI_CACHE_ROOT CONTAINAI_SHA256_FILE CONTAINAI_IMAGE_PREFIX CONTAINAI_IMAGE_TAG CONTAINAI_REGISTRY CONTAINAI_IMAGE_DIGEST CONTAINAI_IMAGE_DIGEST_COPILOT CONTAINAI_IMAGE_DIGEST_CODEX CONTAINAI_IMAGE_DIGEST_CLAUDE CONTAINAI_IMAGE_DIGEST_PROXY CONTAINAI_IMAGE_DIGEST_LOG_FORWARDER
    return 0
}

run_integrity_check_if_needed() {
    local integrity_script="$COMMON_FUNCTIONS_DIR/integrity-check.sh"
    if [ ! -x "$integrity_script" ]; then
        echo "⚠️  Missing integrity-check.sh; skipping integrity validation" >&2
        return 0
    fi
    local enforcement_profile="${CONTAINAI_PROFILE:-dev}"
    if [ "${CONTAINAI_LAUNCHER_CHANNEL:-}" = "nightly" ]; then
        enforcement_profile="prod"
    fi
    if "$integrity_script" --mode "$enforcement_profile" --root "$CONTAINAI_ROOT" --sums "$CONTAINAI_SHA256_FILE"; then
        return 0
    fi
    if [ "$enforcement_profile" = "prod" ]; then
        log_security_event "enforcement" '{"reason":"integrity-failed"}' >/dev/null 2>&1 || true
    fi
    echo "❌ Integrity verification failed for $CONTAINAI_ROOT (profile: $CONTAINAI_PROFILE, channel: ${CONTAINAI_LAUNCHER_CHANNEL:-dev})" >&2
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
    candidate="${_CONTAINAI_SCRIPT_ROOT}/host/utils/secret_broker.py"
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
    local containai_root="${1:-${CONTAINAI_ROOT:-$_CONTAINAI_SCRIPT_ROOT}}"
    echo "$containai_root/host/utils/fix-wsl-security.sh"
}

# Resolves the path to a security profile file.
# Args:
#   $1: containai_root - The ContainAI installation directory (NOT necessarily a git repo)
#   $2: filename - The profile filename to find
#   $3: label - Human-readable label for error messages (optional)
resolve_security_asset_path() {
    local containai_root="$1"
    local filename="$2"
    local label="${3:-$filename}"

    if [ -z "$containai_root" ] || [ -z "$filename" ]; then
        return 1
    fi

    # SECURITY: Check system profiles location FIRST (dev setup installs here)
    local system_candidate="${CONTAINAI_SYSTEM_PROFILES_DIR%/}/$filename"
    if [ -f "$system_candidate" ]; then
        echo "$system_candidate"
        return 0
    fi

    # Check installed location (prod tarball extracts profiles to $install_root/host/profiles/)
    local installed_candidate="$containai_root/host/profiles/$filename"
    if [ -f "$installed_candidate" ]; then
        # SECURITY: Profiles MUST be root-owned to prevent tampering
        local owner
        owner=$(stat -c "%U" "$installed_candidate" 2>/dev/null || echo "unknown")
        if [ "$owner" = "root" ]; then
            echo "$installed_candidate"
            return 0
        fi

        # User-owned profiles are a security risk - reject them
        echo "❌ ${label} found but not root-owned (security risk)." >&2
        echo "   File: $installed_candidate (owner: $owner)" >&2
        echo "   → Run 'sudo ./scripts/setup-local-dev.sh' to install profiles with proper ownership" >&2
        return 1
    fi

    # Profile not found
    echo "❌ ${label} not found." >&2
    echo "   System location: $system_candidate (missing)" >&2
    echo "   Installed location: $installed_candidate (missing)" >&2
    echo "   → Run 'sudo ./scripts/setup-local-dev.sh' to install security profiles" >&2
    return 1
}

# Helper to get channel-specific seccomp filename.
# Args:
#   $1: base_name - Base profile name (e.g., "containai-agent")
# Returns: Channel-specific filename (e.g., "seccomp-containai-agent-dev.json")
_format_seccomp_filename() {
    local base_name="$1"
    local channel
    channel=$(_resolve_apparmor_channel)  # Reuse same channel resolution
    echo "seccomp-${base_name}-${channel}.json"
}

# Backward-compatible helper for the agent seccomp profile; use resolve_security_asset_path directly where possible.
resolve_seccomp_profile_path() {
    local filename
    filename=$(_format_seccomp_filename "containai-agent")
    resolve_security_asset_path "$1" "$filename" "Agent seccomp profile"
}

# Resolves and optionally loads an AppArmor profile for a given channel.
# Args:
#   $1: containai_root - The ContainAI installation directory
#   $2: base_name - Base profile name (e.g., "containai-agent")
#   $3: filename - Profile filename (ignored, kept for backward compatibility)
#   $4: label - Human-readable label for messages
_resolve_channel_apparmor_profile() {
    local containai_root="$1"
    local base_name="$2"
    local filename="$3"  # Ignored - we use channel-specific filename
    local label="$4"

    local channel
    channel=$(_resolve_apparmor_channel)
    local profile_name
    profile_name=$(_format_apparmor_profile_name "$base_name" "$channel") || return 1
    
    # Pre-generated profile filename: apparmor-containai-agent-dev.profile
    local channel_filename="apparmor-${base_name}-${channel}.profile"

    if ! is_apparmor_supported; then
        return 1
    fi

    # Use resolve_security_asset_path with channel-specific filename
    local profile_file
    profile_file=$(resolve_security_asset_path "$containai_root" "$channel_filename" "$label" 2>/dev/null) || {
        echo "⚠️  ${label} file not found. Run scripts/setup-local-dev.sh to install security profiles." >&2
        return 1
    }

    # Check if profile is loaded in kernel
    if apparmor_profile_loaded "$profile_name"; then
        echo "$profile_name"
        return 0
    fi

    # If we can't verify loaded state (non-root), trust that setup script loaded it
    # as long as the profile file exists on disk
    if ! apparmor_profiles_readable; then
        # Can't verify - trust file existence (setup script handles loading)
        echo "$profile_name"
        return 0
    fi

    # We CAN read the profiles file but profile isn't loaded - need root to load
    if [ "$(id -u 2>/dev/null || echo 1)" != "0" ]; then
        echo "⚠️  ${label} '${profile_name}' not loaded (requires sudo). Run: sudo apparmor_parser -r '$profile_file'" >&2
        return 1
    fi

    if ! command -v apparmor_parser >/dev/null 2>&1; then
        echo "⚠️  apparmor_parser not available; cannot load ${label} '${profile_name}'." >&2
        return 1
    fi

    # Load pre-generated profile directly (no rendering needed)
    if apparmor_parser -r -T -W "$profile_file" >/dev/null 2>&1 && apparmor_profile_loaded "$profile_name"; then
        echo "$profile_name"
        return 0
    fi

    echo "⚠️  AppArmor profile '$profile_name' is not loaded. Run: sudo apparmor_parser -r '$profile_file'" >&2
    return 1
}

# Loads all security profiles (seccomp + AppArmor) for ContainAI.
# Args:
#   $1: containai_root - The ContainAI installation directory
load_security_profiles() {
    local containai_root="$1"
    local agent_seccomp proxy_seccomp log_forwarder_seccomp apparmor_profile=""

    local agent_seccomp_file proxy_seccomp_file log_forwarder_seccomp_file
    agent_seccomp_file=$(_format_seccomp_filename "containai-agent")
    proxy_seccomp_file=$(_format_seccomp_filename "containai-proxy")
    log_forwarder_seccomp_file=$(_format_seccomp_filename "containai-log-forwarder")

    if ! agent_seccomp=$(resolve_security_asset_path "$containai_root" "$agent_seccomp_file" "Agent seccomp profile"); then
        return 1
    fi
    if ! proxy_seccomp=$(resolve_security_asset_path "$containai_root" "$proxy_seccomp_file" "Proxy seccomp profile"); then
        return 1
    fi
    if ! log_forwarder_seccomp=$(resolve_security_asset_path "$containai_root" "$log_forwarder_seccomp_file" "Log forwarder seccomp profile"); then
        return 1
    fi

    if ! ensure_security_assets_current "$containai_root"; then
        return 1
    fi

    # Resolve channel-specific AppArmor profile names and ensure they are loaded.
    if apparmor_profile=$(_resolve_channel_apparmor_profile "$containai_root" "containai-agent" "apparmor-containai-agent.profile" "Agent AppArmor profile"); then
        :
    else
        apparmor_profile=""
    fi

    local channel
    channel=$(_resolve_apparmor_channel)
    PROXY_APPARMOR_PROFILE=$(_format_apparmor_profile_name "containai-proxy" "$channel")
    LOG_FORWARDER_APPARMOR_PROFILE=$(_format_apparmor_profile_name "containai-log-forwarder" "$channel")
    LOG_BROKER_APPARMOR_PROFILE="$LOG_FORWARDER_APPARMOR_PROFILE"

    SECCOMP_PROFILE_PATH="$agent_seccomp"
    PROXY_SECCOMP_PROFILE_PATH="$proxy_seccomp"
    LOG_FORWARDER_SECCOMP_PROFILE_PATH="$log_forwarder_seccomp"
    LOG_BROKER_SECCOMP_PROFILE_PATH="$log_forwarder_seccomp"
    APPARMOR_PROFILE_NAME="$apparmor_profile"
}

# Ensures security profile assets are current (hashes match manifest).
# Args:
#   $1: containai_root - The ContainAI installation directory
ensure_security_assets_current() {
    local containai_root="$1"
    local channel
    channel=$(_resolve_apparmor_channel)
    
    local seccomp_filename
    seccomp_filename=$(_format_seccomp_filename "containai-agent")
    local seccomp_source="$containai_root/host/profiles/seccomp-containai-agent.json"
    # Channel-specific apparmor profile
    local apparmor_source="$containai_root/host/profiles/apparmor-containai-agent-${channel}.profile"
    local manifest_path="${CONTAINAI_SYSTEM_PROFILES_DIR%/}/containai-profiles-${channel}.sha256"
    local manifest_source="$containai_root/host/profiles/containai-profiles-${channel}.sha256"
    if [ ! -f "$manifest_path" ] && [ -f "$manifest_source" ]; then
        manifest_path="$manifest_source"
    fi

    local seccomp_path
    if ! seccomp_path=$(resolve_seccomp_profile_path "$containai_root"); then
        return 1
    fi

    local manifest_seccomp_hash=""
    local manifest_apparmor_hash=""
    if [ -f "$manifest_path" ]; then
        # Look for channel-specific seccomp profile in manifest
        manifest_seccomp_hash=$(awk "/${seccomp_filename//\//\\/}/ {print \$2}" "$manifest_path" 2>/dev/null | head -1)
        # Look for channel-specific apparmor profile in manifest
        manifest_apparmor_hash=$(awk "/apparmor-containai-agent-${channel}.profile/ {print \$2}" "$manifest_path" 2>/dev/null | head -1)
    fi

    local hash_source hash_active
    hash_source=$(_sha256_file "$seccomp_source" 2>/dev/null || echo "")
    if [ -z "$hash_source" ]; then
        hash_source="$manifest_seccomp_hash"
    fi
    hash_active=$(_sha256_file "$seccomp_path" 2>/dev/null || echo "")

    if [ -n "$hash_source" ] && [ -n "$hash_active" ]; then
        if [ "$hash_source" != "$hash_active" ]; then
            echo "❌ Seccomp profile is outdated. Run 'sudo ./scripts/setup-local-dev.sh' to refresh host security assets." >&2
            return 1
        fi
    else
        echo "❌ Unable to verify seccomp profile freshness (missing reference hash). Run 'sudo ./scripts/setup-local-dev.sh' to reinstall host security assets." >&2
        return 1
    fi

    # Check channel-specific AppArmor profile
    local apparmor_filename="apparmor-containai-agent-${channel}.profile"
    local apparmor_candidate
    apparmor_candidate=$(resolve_security_asset_path "$containai_root" "$apparmor_filename" "Agent AppArmor profile" 2>/dev/null || true)
    if [ -n "$apparmor_candidate" ] && [ -f "$apparmor_candidate" ]; then
        local aa_source_hash aa_active_hash
        aa_source_hash=$(_sha256_file "$apparmor_source" 2>/dev/null || echo "")
        if [ -z "$aa_source_hash" ]; then
            aa_source_hash="$manifest_apparmor_hash"
        fi
        aa_active_hash=$(_sha256_file "$apparmor_candidate" 2>/dev/null || echo "")
        if [ -n "$aa_source_hash" ] && [ -n "$aa_active_hash" ] && [ "$aa_source_hash" != "$aa_active_hash" ]; then
            echo "❌ AppArmor profile is outdated. Run 'sudo ./scripts/setup-local-dev.sh' to refresh host security assets." >&2
            return 1
        elif [ -z "$aa_source_hash" ] || [ -z "$aa_active_hash" ]; then
            echo "❌ Unable to verify AppArmor profile freshness (missing reference hash). Run 'sudo ./scripts/setup-local-dev.sh' to reinstall host security assets." >&2
            return 1
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

# Require apparmor_parser tool to be available.
# Args: none
# Returns: 0 if available, 1 if missing (with error message)
require_apparmor_tools() {
    if command -v apparmor_parser >/dev/null 2>&1; then
        return 0
    fi
    echo "❌ apparmor_parser not found. Install apparmor-utils package." >&2
    return 1
}

# Require AppArmor to be enabled in kernel.
# Args: none
# Returns: 0 if enabled, 1 if disabled (with error message)
require_apparmor_enabled() {
    local enabled_flag="/sys/module/apparmor/parameters/enabled"
    if [[ -r "$enabled_flag" ]] && grep -qi '^y' "$enabled_flag" 2>/dev/null; then
        return 0
    fi
    echo "❌ AppArmor is not enabled. Enable AppArmor in your kernel." >&2
    return 1
}

# Load an AppArmor profile file into the kernel.
# Args:
#   $1: profile_file - Path to the .profile file
#   $2: label - Human-readable label for messages (optional)
# Returns: 0 on success, 1 on failure
load_apparmor_profile() {
    local profile_file="$1"
    local label="${2:-AppArmor profile}"

    if [[ ! -f "$profile_file" ]]; then
        echo "❌ ${label} file not found: $profile_file" >&2
        return 1
    fi

    if ! apparmor_parser -r "$profile_file"; then
        echo "❌ Failed to load ${label} from $profile_file" >&2
        return 1
    fi

    local profile_name
    profile_name=$(basename "$profile_file" .profile)
    echo "  ✓ Loaded $profile_name"
    return 0
}

# Install security profiles to system location and load into kernel.
# This is the canonical function for both dev and prod installations.
# Args:
#   $1: source_dir - Directory containing channel-specific profiles
#   $2: channel - Channel name (dev|nightly|prod)
#   $3: manifest_name - Name for the SHA256 manifest file (optional)
# Returns: 0 on success, 1 on failure
install_security_profiles_to_system() {
    local source_dir="$1"
    local channel="$2"
    local manifest_name="${3:-containai-profiles-${channel}.sha256}"
    local system_dir="$CONTAINAI_SYSTEM_PROFILES_DIR"

    if [[ -z "$source_dir" || -z "$channel" ]]; then
        echo "❌ Source directory and channel are required" >&2
        return 1
    fi

    if [[ ! -d "$source_dir" ]]; then
        echo "❌ Source profile directory not found: $source_dir" >&2
        return 1
    fi

    # Validate channel
    case "$channel" in
        dev|nightly|prod) ;;
        *) echo "❌ Invalid channel: $channel" >&2; return 1 ;;
    esac

    # Check AppArmor prerequisites
    require_apparmor_tools || return 1
    require_apparmor_enabled || return 1

    # Expected profile files (channel-specific)
    local profile_files=(
        "apparmor-containai-agent-${channel}.profile"
        "apparmor-containai-proxy-${channel}.profile"
        "apparmor-containai-log-forwarder-${channel}.profile"
        "apparmor-containai-logcollector-${channel}.profile"
        "seccomp-containai-agent-${channel}.json"
        "seccomp-containai-proxy-${channel}.json"
        "seccomp-containai-log-forwarder-${channel}.json"
    )

    # Verify all required profiles exist in source
    local missing=()
    for f in "${profile_files[@]}"; do
        if [[ ! -f "$source_dir/$f" ]]; then
            missing+=("$f")
        fi
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "❌ Missing profile files in $source_dir:" >&2
        printf '   - %s\n' "${missing[@]}" >&2
        return 1
    fi

    echo "📦 Installing security profiles to $system_dir (channel: $channel)..."

    # Create system directory with proper ownership
    install -d -m 0755 "$system_dir"

    # Copy all profile files
    local manifest_entries=()
    for f in "${profile_files[@]}"; do
        install -m 0644 "$source_dir/$f" "$system_dir/$f"
        manifest_entries+=("$f $(_sha256_file "$system_dir/$f")")
    done

    # Write manifest
    printf '%s\n' "${manifest_entries[@]}" > "$system_dir/$manifest_name"
    echo "✓ Security profiles installed to $system_dir"

    # Load AppArmor profiles
    echo "Loading AppArmor profiles (channel: $channel)..."
    for f in "${profile_files[@]}"; do
        if [[ "$f" == *.profile ]]; then
            load_apparmor_profile "$system_dir/$f" "$f" || return 1
        fi
    done

    return 0
}

apparmor_profiles_file() {
    echo "/sys/kernel/security/apparmor/profiles"
}

apparmor_profiles_readable() {
    local profiles_file
    profiles_file=$(apparmor_profiles_file)
    # Note: /sys/kernel/security/apparmor/profiles shows r--r--r-- but
    # actually requires CAP_SYS_ADMIN to read. The -r test lies.
    # We must actually attempt to read it.
    cat "$profiles_file" >/dev/null 2>&1
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

ensure_apparmor_profile_loaded() {
    local profile="$1"
    local profile_file="$2"

    if apparmor_profile_loaded "$profile"; then
        return 0
    fi

    if ! is_apparmor_supported; then
        return 1
    fi

    if [ -z "$profile_file" ] || [ ! -f "$profile_file" ]; then
        return 1
    fi

    if [ "$(id -u 2>/dev/null || echo 1)" != "0" ]; then
        return 1
    fi

    if command -v apparmor_parser >/dev/null 2>&1; then
        if apparmor_parser -r -T -W "$profile_file" >/dev/null 2>&1 && apparmor_profile_loaded "$profile"; then
            return 0
        fi
    fi

    return 1
}

# Resolves the AppArmor profile name for the agent.
# Args:
#   $1: containai_root - The ContainAI installation directory
resolve_apparmor_profile_name() {
    local containai_root="$1"
    _resolve_channel_apparmor_profile "$containai_root" "containai-agent" "apparmor-containai-agent.profile" "Agent AppArmor profile"
}

# Verifies all host security prerequisites (seccomp, AppArmor).
# Args:
#   $1: containai_root - The ContainAI installation directory (optional)
verify_host_security_prereqs() {
    local containai_root="${1:-${CONTAINAI_ROOT:-$_CONTAINAI_SCRIPT_ROOT}}"
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

    local channel
    channel=$(_resolve_apparmor_channel)
    local seccomp_agent_file seccomp_proxy_file seccomp_fwd_file
    seccomp_agent_file=$(_format_seccomp_filename "containai-agent")
    seccomp_proxy_file=$(_format_seccomp_filename "containai-proxy")
    seccomp_fwd_file=$(_format_seccomp_filename "containai-log-forwarder")

    local default_seccomp_profile="$containai_root/host/profiles/seccomp-containai-agent.json"
    local installed_seccomp_profile="${CONTAINAI_SYSTEM_PROFILES_DIR%/}/$seccomp_agent_file"

    # Check Agent Seccomp
    if ! resolve_seccomp_profile_path "$containai_root" >/dev/null 2>&1; then
        if [ -n "$installed_seccomp_profile" ]; then
            errors+=("Agent seccomp profile not found at $default_seccomp_profile (or $installed_seccomp_profile). Run scripts/setup-local-dev.sh to reinstall the host security assets.")
        else
            errors+=("Agent seccomp profile not found at $default_seccomp_profile. Run scripts/setup-local-dev.sh to reinstall the host security assets.")
        fi
    fi

    # Check Proxy Seccomp
    if ! resolve_security_asset_path "$containai_root" "$seccomp_proxy_file" "Proxy seccomp profile" >/dev/null 2>&1; then
        errors+=("Proxy seccomp profile not found. Run scripts/setup-local-dev.sh to reinstall the host security assets.")
    fi

    # Check Log Forwarder Seccomp
    if ! resolve_security_asset_path "$containai_root" "$seccomp_fwd_file" "Log forwarder seccomp profile" >/dev/null 2>&1; then
        errors+=("Log forwarder seccomp profile not found. Run scripts/setup-local-dev.sh to reinstall the host security assets.")
    fi

    if ! is_linux_host; then
        errors+=("AppArmor enforcement requires a Linux host. Run from a Linux kernel with AppArmor enabled.")
    elif ! is_apparmor_supported; then
        if is_wsl_environment; then
            local helper_script
            helper_script=$(wsl_security_helper_path "$containai_root")
            if [ -x "$helper_script" ]; then
                errors+=("AppArmor kernel support not detected (WSL 2). Run '$helper_script --check' to audit your Windows configuration, then rerun '$helper_script' (optionally with --force) to apply the fixes and restart WSL.")
            else
                errors+=("AppArmor kernel support not detected (WSL 2). Use the WSL security helper under host/utils to enable AppArmor on the host kernel.")
            fi
        else
            errors+=("AppArmor kernel support not detected. Enable AppArmor to continue.")
        fi
    else
        local channel
        channel=$(_resolve_apparmor_channel)
        local bases=("containai-agent" "containai-proxy" "containai-log-forwarder")
        local idx base p_name label
        # Use channel-specific filenames
        local channel_file p_file p_installed

        for idx in "${!bases[@]}"; do
            base="${bases[$idx]}"
            p_name=$(_format_apparmor_profile_name "$base" "$channel")
            # Channel-specific filename: apparmor-containai-agent-dev.profile
            channel_file="apparmor-${base}-${channel}.profile"
            p_file="$containai_root/host/profiles/$channel_file"
            p_installed="${CONTAINAI_SYSTEM_PROFILES_DIR%/}/$channel_file"
            label="${base//-/ }"

            if [ ! -f "$p_file" ] && [ -n "$p_installed" ] && [ -f "$p_installed" ]; then
                p_file="$p_installed"
            fi

            if apparmor_profile_loaded "$p_name"; then
                continue
            fi

            if _resolve_channel_apparmor_profile "$containai_root" "$base" "$channel_file" "${label^} AppArmor profile" >/dev/null 2>&1; then
                continue
            fi

            if [ "$profiles_file_readable" -eq 0 ] && [ "$current_uid" -ne 0 ]; then
                warnings+=("Unable to verify AppArmor profile '$p_name' without elevated privileges. Re-run './host/utils/check-health.sh' with sudo or run: sudo apparmor_parser -r '$p_file'.")
            elif [ "$current_uid" -ne 0 ] && [ -f "$p_file" ]; then
                warnings+=("AppArmor profile '$p_name' verification skipped (requires sudo). Rerun './host/utils/check-health.sh' with sudo to confirm.")
            elif [ -f "$p_file" ]; then
                errors+=("AppArmor profile '$p_name' not loaded. Run: sudo apparmor_parser -r '$p_file'")
            else
                errors+=("AppArmor profile file missing for '$p_name'. Run scripts/setup-local-dev.sh to reinstall the host security assets.")
            fi
        done
    fi

    if [ "${CONTAINAI_DISABLE_PTRACE_SCOPE:-0}" = "1" ]; then
        warnings+=("Ptrace scope hardening disabled via CONTAINAI_DISABLE_PTRACE_SCOPE=1")
    elif is_linux_host && [ ! -e /proc/sys/kernel/yama/ptrace_scope ]; then
        errors+=("kernel.yama.ptrace_scope is unavailable. Enable the Yama LSM or export CONTAINAI_DISABLE_PTRACE_SCOPE=1 to bypass (not recommended).")
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

    local containai_root="${CONTAINAI_ROOT:-$_CONTAINAI_SCRIPT_ROOT}"
    if [ ! -d "$containai_root" ]; then
        echo "❌ ContainAI root '$containai_root' not found for python runner" >&2
        return 1
    fi

    if ! check_docker_running; then
        return 1
    fi

    local container_cmd
    container_cmd=$(get_active_container_cmd)
    local image
    image=$(get_python_runner_image)

    local docker_args=("run" "--rm" "-w" "$containai_root" "-e" "PYTHONUNBUFFERED=1")
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
        seccomp_profile=$(resolve_seccomp_profile_path "$containai_root" 2>/dev/null || true)
    fi
    if [ -n "$seccomp_profile" ]; then
        docker_args+=("--security-opt" "seccomp=$seccomp_profile")
    fi

    local mounts=("$containai_root")
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

# Merges agent data exports from a staged directory.
# Args:
#   $1: agent_name - Agent name
#   $2: staged_dir - Staged directory with exports
#   $3: containai_root - The ContainAI installation directory
#   $4: home_dir - User home directory
merge_agent_data_exports() {
    local agent_name="$1"
    local staged_dir="$2"
    local containai_root="$3"
    local home_dir="$4"
    local packager="$containai_root/host/utils/package_agent_data.py"

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
        # Use CONTAINAI_HOME if available, otherwise fallback to default
        if [ -n "${CONTAINAI_HOME:-}" ]; then
            output_dir="${CONTAINAI_HOME}/${agent_name}/imports/${session_id}"
        fi
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

# Processes and merges agent data exports from a container.
# Args:
#   $1: container_name - Container name
#   $2: containai_root - The ContainAI installation directory
#   $3: home_dir - User home directory
#   $4: staging_root - Staging directory (optional)
process_agent_data_exports() {
    local container_name="$1"
    local containai_root="$2"
    local home_dir="$3"
    local staging_root="${4:-}"

    if [ -z "$container_name" ] || [ -z "$containai_root" ] || [ -z "$home_dir" ]; then
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
        merge_agent_data_exports "$agent_name" "$staged_path" "$containai_root" "$home_dir"
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

    echo "❌ Error: Pulling by tag is not allowed for profile '$CONTAINAI_PROFILE'. Use digests." >&2
    return 1
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
    local cache_root="${CONTAINAI_SESSION_CACHE:-${CONTAINAI_HOME:-${HOME:-/tmp}/.containai}/session-cache}"
    
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
    
    local containai_root="${CONTAINAI_ROOT:-$_CONTAINAI_SCRIPT_ROOT}"
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

    process_agent_data_exports "$container_name" "$containai_root" "$home_dir"
    
    # Get associated resources
    local proxy_container
    proxy_container=$(get_proxy_container "$container_name")
    local proxy_network
    proxy_network=$(get_proxy_network "$container_name")
    if [ -n "$proxy_container" ]; then
        stop_proxy_log_pipeline "$proxy_container"
    fi
    
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
        rm -rf "${cache_root:?}/${container_name:?}" || true
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
    # Generate key and cert, then convert key to traditional RSA format
    # Squid 5.7 has issues with PKCS#8 format keys
    if ! openssl req -x509 -newkey rsa:4096 -sha256 -days 2 -nodes \
        -subj "/CN=ContainAI Proxy MITM CA" \
        -addext "basicConstraints=critical,CA:TRUE,pathlen:0" \
        -addext "keyUsage=critical,keyCertSign,cRLSign,digitalSignature" \
        -addext "subjectKeyIdentifier=hash" \
        -addext "authorityKeyIdentifier=keyid:always,issuer" \
        -keyout "$ca_key.tmp" \
        -out "$ca_cert" >/dev/null 2>&1; then
        umask "$original_umask"
        echo "❌ Failed to generate MITM CA materials" >&2
        return 1
    fi
    # Convert PKCS#8 key to traditional RSA PEM format for Squid compatibility
    if ! openssl rsa -in "$ca_key.tmp" -out "$ca_key" -traditional 2>/dev/null; then
        # Fallback: use the original key if conversion fails
        mv "$ca_key.tmp" "$ca_key"
    else
        rm -f "$ca_key.tmp"
    fi
    umask "$original_umask"
    # Key owned by proxy user (uid 13) so it's readable inside container
    # when CAP_DAC_READ_SEARCH is dropped. Cert is world-readable for MITM verification.
    # NOTE: chown to uid 13 requires running as root or having CAP_CHOWN on host
    if chown 13:13 "$ca_key" 2>/dev/null; then
        chmod 600 "$ca_key"
    elif chgrp 13 "$ca_key" 2>/dev/null; then
        # Can set group to proxy gid, make group-readable
        chmod 640 "$ca_key"
    else
        # Last resort: world-readable key (least secure, but works for non-root testing)
        chmod 644 "$ca_key" || true
    fi
    chmod 644 "$ca_cert" || true
    SESSION_MITM_CA_CERT="$ca_cert"
    SESSION_MITM_CA_KEY="$ca_key"
    export SESSION_MITM_CA_CERT SESSION_MITM_CA_KEY
    return 0
}

generate_log_broker_certs() {
    local output_dir="$1"
    local broker_hostname="${2:-localhost}"

    if [ -z "$output_dir" ]; then
        echo "❌ Log broker cert output directory not provided" >&2
        return 1
    fi
    if ! command -v openssl >/dev/null 2>&1; then
        echo "❌ openssl is required to generate log broker certificates" >&2
        return 1
    fi

    mkdir -p "$output_dir"
    chmod 700 "$output_dir" 2>/dev/null || true

    local original_umask
    original_umask=$(umask)
    umask 077
    local ca_key="$output_dir/log-ca.key"
    local ca_crt="$output_dir/log-ca.crt"
    local server_key="$output_dir/log-server.key"
    local server_crt="$output_dir/log-server.crt"
    local client_key="$output_dir/log-client.key"
    local client_crt="$output_dir/log-client.crt"
    local ok=true

    if [ ! -f "$ca_crt" ] || [ ! -f "$ca_key" ]; then
        if ! openssl req -x509 -newkey rsa:2048 -nodes -subj "/CN=ContainAI Log Broker CA" -days 2 \
            -keyout "$ca_key" -out "$ca_crt" >/dev/null 2>&1; then
            ok=false
        fi
    fi
    if [ ! -f "$server_crt" ] || [ ! -f "$server_key" ]; then
        if ! openssl req -new -newkey rsa:2048 -nodes -subj "/CN=${broker_hostname}" -keyout "$server_key" -out "$output_dir/server.csr" >/dev/null 2>&1; then
            ok=false
        elif ! openssl x509 -req -in "$output_dir/server.csr" -CA "$ca_crt" -CAkey "$ca_key" -CAcreateserial -out "$server_crt" -days 2 -sha256 >/dev/null 2>&1; then
            ok=false
        fi
    fi
    if [ ! -f "$client_crt" ] || [ ! -f "$client_key" ]; then
        if ! openssl req -new -newkey rsa:2048 -nodes -subj "/CN=containai-forwarder" -keyout "$client_key" -out "$output_dir/client.csr" >/dev/null 2>&1; then
            ok=false
        elif ! openssl x509 -req -in "$output_dir/client.csr" -CA "$ca_crt" -CAkey "$ca_key" -CAcreateserial -out "$client_crt" -days 2 -sha256 >/dev/null 2>&1; then
            ok=false
        fi
    fi
    umask "$original_umask"

    chmod 600 "$ca_key" "$ca_crt" "$server_key" "$server_crt" "$client_key" "$client_crt" 2>/dev/null || true

    if [ "$ok" = false ]; then
        echo "❌ Failed to generate log broker certificates in $output_dir" >&2
        return 1
    fi
    return 0
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
    local internal_network="$1"
    local egress_network="$2"
    local proxy_container="$3"
    local proxy_image="$4"
    local agent_container="$5"
    local squid_allowed_domains="${6:-*.github.com,*.githubcopilot.com,*.nuget.org}"
    local helper_acl_file="${7:-}"
    local agent_id="${8:-}"
    local session_id="${9:-}"
    local mitm_ca_cert="${10:-${SESSION_MITM_CA_CERT:-}}"
    local mitm_ca_key="${11:-${SESSION_MITM_CA_KEY:-}}"
    local internal_subnet="${12:-}"
    local proxy_seccomp="${PROXY_SECCOMP_PROFILE_PATH:-${SECCOMP_PROFILE_PATH:-}}"
    local proxy_apparmor="${PROXY_APPARMOR_PROFILE:-containai-proxy}"
    
    if [ -z "$mitm_ca_cert" ] || [ -z "$mitm_ca_key" ] || [ ! -f "$mitm_ca_cert" ] || [ ! -f "$mitm_ca_key" ]; then
        echo "❌ MITM CA certificate and key are required to start the Squid proxy" >&2
        return 1
    fi
    
    # Create networks if needed
    if [ -n "$internal_network" ] && ! container_cli network inspect "$internal_network" >/dev/null 2>&1; then
        if [ -n "$internal_subnet" ]; then
            container_cli network create --internal --subnet "$internal_subnet" "$internal_network" >/dev/null
        else
            container_cli network create --internal "$internal_network" >/dev/null
        fi
    fi
    if [ -n "$egress_network" ] && ! container_cli network inspect "$egress_network" >/dev/null 2>&1; then
        container_cli network create "$egress_network" >/dev/null
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
        --network "$internal_network"
        --restart no
        --read-only
        --cap-drop=ALL
        --cap-add=CHOWN
        --cap-add=SETUID
        --cap-add=SETGID
        --security-opt "no-new-privileges:true"
        ${proxy_seccomp:+--security-opt "seccomp=${proxy_seccomp}"}
        ${proxy_apparmor:+--security-opt "apparmor=${proxy_apparmor}"}
        --pids-limit 256
        -e "SQUID_ALLOWED_DOMAINS=$squid_allowed_domains"
        -e "SQUID_MITM_CA_CERT=/etc/squid/mitm/ca.crt"
        -e "SQUID_MITM_CA_KEY=/etc/squid/mitm/ca.key"
        --tmpfs "/var/log/squid:rw,nosuid,nodev,noexec,size=64m,mode=755"
        --tmpfs "/var/spool/squid:rw,nosuid,nodev,noexec,size=128m,mode=755"
        --tmpfs "/var/run/squid:rw,nosuid,nodev,noexec,size=16m,mode=755"
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

    if [ -n "$egress_network" ]; then
        # Attach proxy to egress network for outbound traffic
        container_cli network connect "$egress_network" "$proxy_container" >/dev/null 2>&1 || true
    fi
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
    local agent_id="${5:-}"
    local session_id="${6:-}"
    local broker_name="${proxy_container}-log-broker"
    local forwarder_name="${proxy_container}-log-forwarder"
    local broker_port="4433"
    local forwarder_image="${LOG_FORWARDER_IMAGE:-${CONTAINAI_IMAGE_PREFIX:-containai-dev}-log-forwarder:${CONTAINAI_IMAGE_TAG:-devlocal}}"
    local broker_image="${LOG_BROKER_IMAGE:-$forwarder_image}"
    local forwarder_seccomp="${LOG_FORWARDER_SECCOMP_PROFILE_PATH:-${SECCOMP_PROFILE_PATH:-}}"
    # Use channel-aware AppArmor profile name
    local channel
    channel=$(_resolve_apparmor_channel)
    local default_log_apparmor
    default_log_apparmor=$(_format_apparmor_profile_name "containai-log-forwarder" "$channel")
    local forwarder_apparmor="${LOG_FORWARDER_APPARMOR_PROFILE:-$default_log_apparmor}"
    local broker_seccomp="${LOG_BROKER_SECCOMP_PROFILE_PATH:-${SECCOMP_PROFILE_PATH:-}}"
    local broker_apparmor="${LOG_BROKER_APPARMOR_PROFILE:-$default_log_apparmor}"
    local run_user
    local proxy_image=""
    run_user="$(id -u):$(id -g)"

    mkdir -p "$log_dir" "$cert_dir"
    chmod 750 "$log_dir" 2>/dev/null || true

    # Generate certs with the broker hostname for proper TLS verification
    if ! generate_log_broker_certs "$cert_dir" "$broker_name"; then
        return 1
    fi
    chmod 640 "$cert_dir"/* 2>/dev/null || true

    if ! container_exists "$proxy_container"; then
        echo "❌ Cannot start log pipeline; proxy container '$proxy_container' missing" >&2
        return 1
    fi

    if ! container_cli image inspect "$forwarder_image" >/dev/null 2>&1; then
        local proxy_image
        proxy_image=$(container_cli inspect -f '{{.Config.Image}}' "$proxy_container" 2>/dev/null || true)
        if [ -n "$proxy_image" ]; then
            forwarder_image="$proxy_image"
            broker_image="$proxy_image"
        else
            echo "❌ No log forwarder image available and proxy image unknown" >&2
            return 1
        fi
    fi
    if ! container_cli image inspect "$broker_image" >/dev/null 2>&1; then
        broker_image="$forwarder_image"
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
        -u "$run_user" \
        -v "$cert_dir:/certs:ro" \
        -v "$log_dir:/logs" \
        --tmpfs /tmp:rw,nosuid,nodev,noexec,size=16m,mode=1777 \
        --label "containai.log-of=$proxy_container" \
        --label "containai.log-role=broker" \
        ${agent_id:+--label "containai.agent=${agent_id}"} \
        ${session_id:+--label "containai.session=${session_id}"} \
        "$broker_image" \
        sh -c "socat -u OPENSSL-LISTEN:${broker_port},reuseaddr,fork,cert=/certs/log-server.crt,key=/certs/log-server.key,cafile=/certs/log-ca.crt,verify=1 OPEN:/logs/access.log,creat,append 2>>/logs/broker.err"
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
        -u "$run_user" \
        --volumes-from "$proxy_container":ro \
        -v "$cert_dir:/certs:ro" \
        --tmpfs /tmp:rw,nosuid,nodev,noexec,size=16m,mode=1777 \
        --label "containai.log-of=$proxy_container" \
        --label "containai.log-role=forwarder" \
        ${agent_id:+--label "containai.agent=${agent_id}"} \
        ${session_id:+--label "containai.session=${session_id}"} \
        "$forwarder_image" \
        sh -c "tail -F /var/log/squid/access.log 2>/dev/null | socat -u - OPENSSL:${broker_name}:${broker_port},cert=/certs/log-client.crt,key=/certs/log-client.key,cafile=/certs/log-ca.crt,verify=1 2>>/tmp/forwarder.err"
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
