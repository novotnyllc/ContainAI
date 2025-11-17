#!/usr/bin/env bash
# Common functions for agent management scripts
set -euo pipefail

COMMON_FUNCTIONS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CODING_AGENTS_REPO_ROOT_DEFAULT=$(cd "$COMMON_FUNCTIONS_DIR/../.." && pwd)

CODING_AGENTS_CONFIG_DIR="${HOME}/.config/coding-agents"
CODING_AGENTS_HOST_CONFIG_FILE="${CODING_AGENTS_HOST_CONFIG:-${CODING_AGENTS_CONFIG_DIR}/host-config.env}"
CODING_AGENTS_OVERRIDE_DIR="${CODING_AGENTS_OVERRIDE_DIR:-${CODING_AGENTS_CONFIG_DIR}/overrides}"
CODING_AGENTS_DIRTY_OVERRIDE_TOKEN="${CODING_AGENTS_DIRTY_OVERRIDE_TOKEN:-${CODING_AGENTS_OVERRIDE_DIR}/allow-dirty}"
CODING_AGENTS_BROKER_SCRIPT="${CODING_AGENTS_BROKER_SCRIPT:-${CODING_AGENTS_REPO_ROOT_DEFAULT}/scripts/runtime/secret-broker.py}"
CODING_AGENTS_AUDIT_LOG="${CODING_AGENTS_AUDIT_LOG:-${CODING_AGENTS_CONFIG_DIR}/security-events.log}"
CODING_AGENTS_HELPER_NETWORK_POLICY="${CODING_AGENTS_HELPER_NETWORK_POLICY:-loopback}"
CODING_AGENTS_HELPER_PIDS_LIMIT="${CODING_AGENTS_HELPER_PIDS_LIMIT:-64}"
CODING_AGENTS_HELPER_MEMORY="${CODING_AGENTS_HELPER_MEMORY:-512m}"
DEFAULT_LAUNCHER_UPDATE_POLICY="prompt"

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
    if [ "${CODING_AGENTS_DISABLE_AUDIT_LOG:-0}" = "1" ]; then
        return
    fi
    local event_name="$1"
    local payload="${2:-{}}"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local record
    record=$(printf '{"ts":"%s","event":"%s","payload":%s}\n' "$timestamp" "$(json_escape_string "$event_name")" "$payload")
    local log_file="$CODING_AGENTS_AUDIT_LOG"
    local log_dir
    log_dir=$(dirname "$log_file")
    mkdir -p "$log_dir"
    local previous_umask
    previous_umask=$(umask)
    umask 077
    printf '%s' "$record" >> "$log_file"
    umask "$previous_umask"
    if command -v systemd-cat >/dev/null 2>&1; then
        printf '%s' "$record" | systemd-cat -t coding-agents-launcher >/dev/null 2>&1 || true
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
    local repo_root="${CODING_AGENTS_REPO_ROOT:-$CODING_AGENTS_REPO_ROOT_DEFAULT}"
    local git_head
    git_head=$(get_git_head_hash "$repo_root" 2>/dev/null || echo "")
    local manifest_sha="${CODING_AGENTS_SESSION_CONFIG_SHA256:-}"
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

ensure_trusted_paths_clean() {
    local repo_root="$1"
    shift || true
    local label="${1:-trusted files}"
    shift || true
    local override_token="${CODING_AGENTS_DIRTY_OVERRIDE_TOKEN}"
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
    local file="$CODING_AGENTS_HOST_CONFIG_FILE"

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
    local env_value="${CODING_AGENTS_LAUNCHER_UPDATE_POLICY:-}"
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

    if [ "${CODING_AGENTS_SKIP_UPDATE_CHECK:-0}" = "1" ]; then
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

    read -p "Update Coding Agents launchers now? [Y/n]: " -r response
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

# Detect container runtime (docker or podman)
get_container_runtime() {
    # Check for CONTAINER_RUNTIME environment variable first
    if [ -n "${CONTAINER_RUNTIME:-}" ]; then
        if command -v "$CONTAINER_RUNTIME" &> /dev/null; then
            echo "$CONTAINER_RUNTIME"
            return 0
        fi
    fi
    
    # Auto-detect: prefer docker, fall back to podman
    if command -v docker &> /dev/null && docker info > /dev/null 2>&1; then
        echo "docker"
        return 0
    elif command -v podman &> /dev/null && podman info > /dev/null 2>&1; then
        echo "podman"
        return 0
    fi
    
    # Check if either exists but not running
    if command -v docker &> /dev/null; then
        echo "docker"
        return 0
    elif command -v podman &> /dev/null; then
        echo "podman"
        return 0
    fi
    
    # Neither found
    return 1
}

get_secret_broker_script() {
    local candidate
    candidate="${CODING_AGENTS_BROKER_SCRIPT}"
    if [ -x "$candidate" ]; then
        echo "$candidate"
        return 0
    fi
    candidate="${CODING_AGENTS_REPO_ROOT_DEFAULT}/scripts/runtime/secret-broker.py"
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

# Cache the active container CLI (docker or podman) so downstream helpers can reuse it
get_active_container_cmd() {
    if [ -n "${CODING_AGENTS_CONTAINER_CMD:-}" ]; then
        echo "$CODING_AGENTS_CONTAINER_CMD"
        return 0
    fi

    local runtime
    runtime=$(get_container_runtime 2>/dev/null || true)
    if [ -z "$runtime" ]; then
        runtime="docker"
    fi

    CODING_AGENTS_CONTAINER_CMD="$runtime"
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

resolve_seccomp_profile_path() {
    local repo_root="$1"
    local candidate="${CODING_AGENTS_SECCOMP_PROFILE:-}"

    if [ -z "$candidate" ]; then
        candidate="$repo_root/docker/profiles/seccomp-coding-agents.json"
    elif [[ "$candidate" != /* ]]; then
        candidate="$repo_root/$candidate"
    fi

    if [ -f "$candidate" ]; then
        echo "$candidate"
        return 0
    fi

    echo "❌ Seccomp profile not found at $candidate" >&2
    return 1
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

apparmor_profile_loaded() {
    local profile="$1"
    local profiles_file="/sys/kernel/security/apparmor/profiles"

    if [ -z "$profile" ] || [ ! -r "$profiles_file" ]; then
        return 1
    fi

    if grep -q "^${profile} " "$profiles_file"; then
        return 0
    fi
    return 1
}

resolve_apparmor_profile_name() {
    local repo_root="$1"
    local profile="${CODING_AGENTS_APPARMOR_PROFILE_NAME:-coding-agents}"
    local profile_file="${CODING_AGENTS_APPARMOR_PROFILE_FILE:-$repo_root/docker/profiles/apparmor-coding-agents.profile}"

    if [ "${CODING_AGENTS_DISABLE_APPARMOR:-0}" = "1" ]; then
        return 1
    fi

    if ! is_apparmor_supported; then
        return 1
    fi

    if apparmor_profile_loaded "$profile"; then
        echo "$profile"
        return 0
    fi

    if [ ! -f "$profile_file" ]; then
        echo "⚠️  AppArmor profile file not found at $profile_file" >&2
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
    local repo_root="${1:-${CODING_AGENTS_REPO_ROOT:-$CODING_AGENTS_REPO_ROOT_DEFAULT}}"
    local errors=()
    local warnings=()

    if [ "${CODING_AGENTS_DISABLE_SECCOMP:-0}" = "1" ]; then
        warnings+=("Seccomp enforcement disabled via CODING_AGENTS_DISABLE_SECCOMP=1")
    else
        if ! resolve_seccomp_profile_path "$repo_root" >/dev/null 2>&1; then
            local hint="${CODING_AGENTS_SECCOMP_PROFILE:-$repo_root/docker/profiles/seccomp-coding-agents.json}"
            if [[ "$hint" != /* ]]; then
                hint="$repo_root/$hint"
            fi
            errors+=("Seccomp profile not found at $hint. Install host security profiles or export CODING_AGENTS_DISABLE_SECCOMP=1 (not recommended).")
        fi
    fi

    if [ "${CODING_AGENTS_DISABLE_APPARMOR:-0}" = "1" ]; then
        warnings+=("AppArmor enforcement disabled via CODING_AGENTS_DISABLE_APPARMOR=1")
    else
        if ! is_linux_host; then
            errors+=("AppArmor enforcement requires a Linux host. Run from Linux or export CODING_AGENTS_DISABLE_APPARMOR=1 to acknowledge the risk.")
        elif ! is_apparmor_supported; then
            errors+=("AppArmor kernel support not detected. Enable AppArmor or export CODING_AGENTS_DISABLE_APPARMOR=1 to override.")
        else
            local profile="${CODING_AGENTS_APPARMOR_PROFILE_NAME:-coding-agents}"
            local profile_file="${CODING_AGENTS_APPARMOR_PROFILE_FILE:-$repo_root/docker/profiles/apparmor-coding-agents.profile}"
            if [[ "$profile_file" != /* ]]; then
                profile_file="$repo_root/$profile_file"
            fi
            if ! apparmor_profile_loaded "$profile"; then
                if [ -f "$profile_file" ]; then
                    errors+=("AppArmor profile '$profile' is not loaded. Run: sudo apparmor_parser -r '$profile_file' or export CODING_AGENTS_DISABLE_APPARMOR=1 to override.")
                else
                    errors+=("AppArmor profile file '$profile_file' not found. Set CODING_AGENTS_APPARMOR_PROFILE_FILE to a valid profile path.")
                fi
            fi
        fi
    fi

    if [ "${CODING_AGENTS_DISABLE_PTRACE_SCOPE:-0}" = "1" ]; then
        warnings+=("Ptrace scope hardening disabled via CODING_AGENTS_DISABLE_PTRACE_SCOPE=1")
    elif is_linux_host && [ ! -e /proc/sys/kernel/yama/ptrace_scope ]; then
        errors+=("kernel.yama.ptrace_scope is unavailable. Enable the Yama LSM or export CODING_AGENTS_DISABLE_PTRACE_SCOPE=1 to bypass (not recommended).")
    fi

    if [ "${CODING_AGENTS_DISABLE_SENSITIVE_TMPFS:-0}" = "1" ]; then
        warnings+=("Sensitive tmpfs mounting disabled via CODING_AGENTS_DISABLE_SENSITIVE_TMPFS=1")
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
    if [ "${CODING_AGENTS_DISABLE_CONTAINER_SECURITY_CHECK:-0}" = "1" ]; then
        echo "⚠️  Container security checks disabled via CODING_AGENTS_DISABLE_CONTAINER_SECURITY_CHECK=1" >&2
        return 0
    fi

    local require_seccomp=1
    local require_apparmor=1
    if [ "${CODING_AGENTS_DISABLE_SECCOMP:-0}" = "1" ]; then
        require_seccomp=0
    fi
    if [ "${CODING_AGENTS_DISABLE_APPARMOR:-0}" = "1" ]; then
        require_apparmor=0
    fi

    if [ $require_seccomp -eq 0 ] && [ $require_apparmor -eq 0 ]; then
        return 0
    fi

    local info_json="${CODING_AGENTS_CONTAINER_INFO_JSON:-}"
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
    summary=$(printf '%s' "$info_json" | python3 - <<'PY'
import json, sys
try:
    data = json.load(sys.stdin)
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

    if [ $require_seccomp -eq 1 ] && [ $has_seccomp -ne 1 ]; then
        echo "❌ Container runtime does not report seccomp support. Update Docker/Podman or export CODING_AGENTS_DISABLE_SECCOMP=1 to override." >&2
        return 1
    fi

    if [ $require_apparmor -eq 1 ] && [ $has_apparmor -ne 1 ]; then
        echo "❌ Container runtime does not report AppArmor support. Ensure the module is enabled or export CODING_AGENTS_DISABLE_APPARMOR=1 to override." >&2
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
    
    # Replace slashes with dashes
    sanitized="${branch//\//-}"
    sanitized="${sanitized//\\/-}"
    
    # Replace any other invalid characters with dashes
    sanitized=$(echo "$sanitized" | sed 's/[^a-zA-Z0-9._-]/-/g')
    
    # Collapse multiple dashes
    sanitized=$(echo "$sanitized" | sed 's/-\+/-/g')
    
    # Remove leading special characters
    sanitized=$(echo "$sanitized" | sed 's/^[._-]\+//')
    
    # Remove trailing special characters
    sanitized=$(echo "$sanitized" | sed 's/[._-]\+$//')
    
    # Convert to lowercase
    sanitized=$(echo "$sanitized" | tr '[:upper:]' '[:lower:]')
    
    # Ensure non-empty result
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
        local drive=$(echo "$path" | cut -d: -f1 | tr '[:upper:]' '[:lower:]')
        local rest=$(echo "$path" | cut -d: -f2 | tr '\\' '/')
        echo "/mnt/${drive}${rest}"
    else
        echo "$path"
    fi
}

# Check if container runtime (Docker/Podman) is running
check_docker_running() {
    local runtime
    runtime=$(get_container_runtime 2>/dev/null || true)

    if [ -n "$runtime" ]; then
        if $runtime info > /dev/null 2>&1; then
            CODING_AGENTS_CONTAINER_CMD="$runtime"
            return 0
        fi
    fi

    echo "⚠️  Container runtime not running. Checking installation..."

    local detected_runtime=""
    if command -v docker &> /dev/null; then
        detected_runtime="docker"
    elif command -v podman &> /dev/null; then
        detected_runtime="podman"
    else
        echo "❌ No container runtime found. Please install one:"
        echo "   Docker: https://www.docker.com/products/docker-desktop"
        echo "   Podman: https://podman.io/getting-started/installation"
        return 1
    fi

    if [ "$detected_runtime" = "podman" ]; then
        echo "ℹ️  Using Podman as container runtime"

        if podman info > /dev/null 2>&1; then
            CODING_AGENTS_CONTAINER_CMD="podman"
            return 0
        fi

        echo "❌ Podman is installed but not working properly"
        echo "   Try: podman system reset"
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
                        CODING_AGENTS_CONTAINER_CMD="docker"
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
    if [ -n "${CODING_AGENTS_PYTHON_IMAGE:-}" ]; then
        echo "$CODING_AGENTS_PYTHON_IMAGE"
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

    local repo_root="${CODING_AGENTS_REPO_ROOT:-$CODING_AGENTS_REPO_ROOT_DEFAULT}"
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
    docker_args+=("--pids-limit" "$CODING_AGENTS_HELPER_PIDS_LIMIT")
    docker_args+=("--security-opt" "no-new-privileges")
    docker_args+=("--cap-drop" "ALL")

    if [ -n "$CODING_AGENTS_HELPER_MEMORY" ]; then
        docker_args+=("--memory" "$CODING_AGENTS_HELPER_MEMORY")
    fi

    local helper_network="${CODING_AGENTS_HELPER_NETWORK_POLICY:-loopback}"
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
    done < <(env | grep '^CODING_AGENTS_' || true)

    local seccomp_profile=""
    if [ "${CODING_AGENTS_DISABLE_HELPER_SECCOMP:-0}" != "1" ]; then
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

# Pull and tag image with retry logic
pull_and_tag_image() {
    local agent="$1"
    local max_retries="${2:-3}"
    local retry_delay="${3:-2}"
    local registry_image="ghcr.io/novotnyllc/coding-agents-${agent}:latest"
    local local_image="coding-agents-${agent}:local"
    
    echo "📦 Checking for image updates..."
    
    local attempt=0
    local pulled=false
    
    while [ $attempt -lt $max_retries ] && [ "$pulled" = "false" ]; do
        attempt=$((attempt + 1))
        
        if [ $attempt -gt 1 ]; then
            echo "  ⚠️  Retry attempt $attempt of $max_retries..."
        fi
        
        if container_cli pull --quiet "$registry_image" 2>/dev/null; then
            container_cli tag "$registry_image" "$local_image" 2>/dev/null || true
            pulled=true
        else
            if [ $attempt -lt $max_retries ]; then
                sleep $retry_delay
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
    container_cli ps -a --filter "label=coding-agents.type=agent" \
        --format "table {{.Names}}\t{{.Status}}\t{{.Image}}\t{{.CreatedAt}}"
}

# Get proxy container name for agent
get_proxy_container() {
    local agent_container="$1"
    container_cli inspect -f '{{ index .Config.Labels "coding-agents.proxy-container" }}' "$agent_container" 2>/dev/null
}

# Get proxy network name for agent
get_proxy_network() {
    local agent_container="$1"
    container_cli inspect -f '{{ index .Config.Labels "coding-agents.proxy-network" }}' "$agent_container" 2>/dev/null
}

# Remove container and associated resources
remove_container_with_sidecars() {
    local container_name="$1"
    local skip_push="${2:-false}"
    local keep_branch="${3:-false}"
    
    if ! container_exists "$container_name"; then
        echo "❌ Container '$container_name' does not exist"
        return 1
    fi
    
    # Get container labels to find repo and branch info
    local agent_branch=$(container_cli inspect -f '{{ index .Config.Labels "coding-agents.branch" }}' "$container_name" 2>/dev/null || true)
    local repo_path=$(container_cli inspect -f '{{ index .Config.Labels "coding-agents.repo-path" }}' "$container_name" 2>/dev/null || true)
    local local_remote_path=$(container_cli inspect -f '{{ index .Config.Labels "coding-agents.local-remote" }}' "$container_name" 2>/dev/null || true)
    
    # Push changes first
    if [ "$(get_container_status "$container_name")" = "running" ]; then
        push_to_local "$container_name" "$skip_push"
    fi
    
    # Get associated resources
    local proxy_container=$(get_proxy_container "$container_name")
    local proxy_network=$(get_proxy_network "$container_name")
    
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
        local attached=$(container_cli network inspect -f '{{range .Containers}}{{.Name}} {{end}}' "$proxy_network" 2>/dev/null)
        if [ -z "$attached" ]; then
            echo "🗑️  Removing network: $proxy_network"
            container_cli network rm "$proxy_network" 2>/dev/null || true
        fi
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

# Ensure squid proxy is running (for launch-agent)
ensure_squid_proxy() {
    local network_name="$1"
    local proxy_container="$2"
    local proxy_image="$3"
    local agent_container="$4"
    local squid_allowed_domains="${5:-*.github.com,*.githubcopilot.com,*.nuget.org}"
    
    # Create network if needed
    if ! container_cli network inspect "$network_name" >/dev/null 2>&1; then
        container_cli network create "$network_name" >/dev/null
    fi
    
    # Check if proxy exists
    if container_exists "$proxy_container"; then
        local state=$(get_container_status "$proxy_container")
        if [ "$state" != "running" ]; then
            container_cli start "$proxy_container" >/dev/null
        fi
    else
        # Create new proxy
        container_cli run -d \
            --name "$proxy_container" \
            --hostname "$proxy_container" \
            --network "$network_name" \
            --restart unless-stopped \
            -e "SQUID_ALLOWED_DOMAINS=$squid_allowed_domains" \
            --label "coding-agents.proxy-of=$agent_container" \
            --label "coding-agents.proxy-image=$proxy_image" \
            "$proxy_image" >/dev/null
    fi
}

# Generate repository setup script for container
generate_repo_setup_script() {
    local source_type="$1"
    local git_url="$2"
    local wsl_path="$3"
    local origin_url="$4"
    local agent_branch="$5"
    
    cat << 'SETUP_SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

TARGET_DIR="${WORKSPACE_DIR:-/workspace}"
mkdir -p "$TARGET_DIR"

# Clean target directory
if [ -d "$TARGET_DIR" ] && [ "$(find "$TARGET_DIR" -mindepth 1 -maxdepth 1 | wc -l)" -gt 0 ]; then
    find "$TARGET_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
fi

if [ "$SOURCE_TYPE" = "url" ]; then
    echo "🌐 Cloning repository from $GIT_URL..."
    git clone "$GIT_URL" "$TARGET_DIR"
    cd "$TARGET_DIR"
    if [ -n "$ORIGIN_URL" ]; then
        git remote set-url origin "$ORIGIN_URL"
    fi
else
    echo "📁 Copying repository from host..."
    cp -a /tmp/source-repo/. "$TARGET_DIR/"
    cd "$TARGET_DIR"
    
    # Configure local remote
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

        local temp_ref="refs/coding-agents-sync/${agent_branch// /-}"
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
