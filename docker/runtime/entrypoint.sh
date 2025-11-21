#!/usr/bin/env bash
set -euo pipefail

AGENT_USERNAME="${CONTAINAI_USER:-agentuser}"
AGENT_UID=$(id -u "$AGENT_USERNAME" 2>/dev/null || echo 1000)
AGENT_GID=$(id -g "$AGENT_USERNAME" 2>/dev/null || echo 1000)
AGENT_CLI_USERNAME="${CONTAINAI_CLI_USER:-agentcli}"
AGENT_CLI_UID=$(id -u "$AGENT_CLI_USERNAME" 2>/dev/null || echo "$AGENT_UID")
AGENT_CLI_GID=$(id -g "$AGENT_CLI_USERNAME" 2>/dev/null || echo "$AGENT_GID")
BASEFS_DIR="${CONTAINAI_BASEFS:-/opt/containai/basefs}"
TOOLCACHE_DIR="${CONTAINAI_TOOLCACHE:-/toolcache}"
PTRACE_SCOPE_VALUE="${CONTAINAI_PTRACE_SCOPE:-3}"
CAP_TMPFS_SIZE="${CONTAINAI_CAP_TMPFS_SIZE:-16m}"
DATA_TMPFS_SIZE="${CONTAINAI_DATA_TMPFS_SIZE:-64m}"
SECRETS_TMPFS_SIZE="${CONTAINAI_SECRET_TMPFS_SIZE:-32m}"
STUB_SHIM_ROOT="/home/${AGENT_USERNAME}/.local/bin"
declare -a MCP_HELPER_PIDS=()
declare -a MCP_HELPER_NAMES=()
PROXY_FIREWALL_APPLIED="${PROXY_FIREWALL_APPLIED:-0}"

is_mountpoint() {
    local path="$1"
    if command -v mountpoint >/dev/null 2>&1; then
        mountpoint -q "$path"
        return $?
    fi
    grep -qs "[[:space:]]${path}[[:space:]]" /proc/mounts
}

enforce_ptrace_scope() {
    local target="$PTRACE_SCOPE_VALUE"
    if [ "${CONTAINAI_DISABLE_PTRACE_SCOPE:-0}" = "1" ]; then
        return
    fi
    if [ ! -w /proc/sys/kernel/yama/ptrace_scope ]; then
        echo "⚠️  ptrace_scope not writable; skipping" >&2
        return
    fi
    if command -v sysctl >/dev/null 2>&1; then
        if sysctl -w kernel.yama.ptrace_scope="$target" >/dev/null 2>&1; then
            echo "🔒 kernel.yama.ptrace_scope set to $target"
            return
        fi
    fi
    if echo "$target" >/proc/sys/kernel/yama/ptrace_scope 2>/dev/null; then
        echo "🔒 kernel.yama.ptrace_scope set to $target"
    else
        echo "⚠️  Failed to set kernel.yama.ptrace_scope" >&2
    fi
}

harden_proc_visibility() {
    if [ "${CONTAINAI_DISABLE_PROC_HARDENING:-0}" = "1" ]; then
        return
    fi
    local group="${CONTAINAI_PROC_GROUP:-agentproc}"
    if ! getent group "$group" >/dev/null 2>&1; then
        if ! groupadd --system "$group" >/dev/null 2>&1; then
            echo "⚠️  Unable to create $group group for /proc hardening" >&2
            return
        fi
    fi
    usermod -a -G "$group" "$AGENT_USERNAME" >/dev/null 2>&1 || true
    local gid
    gid=$(getent group "$group" | awk -F: '{print $3}')
    if [ -z "$gid" ]; then
        echo "⚠️  Failed to resolve GID for $group" >&2
        return
    fi
    if mount -o remount,hidepid=2,gid="$gid" /proc >/dev/null 2>&1; then
        echo "🔒 /proc remounted with hidepid=2 (group $group)"
    else
        echo "⚠️  Unable to remount /proc with hidepid=2" >&2
    fi
}

prepare_sensitive_tmpfs() {
    local path="$1"
    local size="${2:-16m}"
    local owner_uid="${3:-$AGENT_UID}"
    local owner_gid="${4:-$AGENT_GID}"
    local dir_mode="${5:-700}"
    if [ "${CONTAINAI_DISABLE_SENSITIVE_TMPFS:-0}" = "1" ]; then
        return
    fi
    mkdir -p "$path"
    if ! is_mountpoint "$path"; then
        if ! mount -t tmpfs -o "size=$size,nosuid,nodev,noexec,mode=$dir_mode" tmpfs "$path" >/dev/null 2>&1; then
            echo "⚠️  Failed to mount tmpfs at $path" >&2
        fi
    else
        mount -o remount,nosuid,nodev,noexec,mode="$dir_mode" "$path" >/dev/null 2>&1 || true
    fi
    chown "$owner_uid:$owner_gid" "$path" 2>/dev/null || true
    chmod "$dir_mode" "$path" 2>/dev/null || true
    mount --make-private "$path" >/dev/null 2>&1 || true
    mount --make-unbindable "$path" >/dev/null 2>&1 || true
}

parse_proxy_target() {
    local proxy_url="$1"
    python3 - "$proxy_url" <<'PY'
import sys, urllib.parse, socket
url = sys.argv[1]
parsed = urllib.parse.urlparse(url)
host = parsed.hostname
port = parsed.port or (443 if parsed.scheme == "https" else 80)
if not host:
    sys.exit(1)
try:
    ip = socket.gethostbyname(host)
except Exception:
    sys.exit(1)
print(f"{ip}:{port}")
PY
}

enforce_proxy_firewall() {
    if [ "$PROXY_FIREWALL_APPLIED" = "1" ]; then
        return
    fi
    local proxy_url="${HTTPS_PROXY:-${https_proxy:-${HTTP_PROXY:-${http_proxy:-}}}}"
    if [ -z "$proxy_url" ]; then
        echo "❌ Proxy firewall enforcement requires HTTP(S)_PROXY to be set" >&2
        exit 1
    fi
    if ! command -v iptables >/dev/null 2>&1; then
        echo "❌ iptables not available; cannot enforce proxy-only egress" >&2
        exit 1
    fi
    local proxy_target
    proxy_target="$(parse_proxy_target "$proxy_url")" || {
        echo "❌ Unable to resolve proxy target from '$proxy_url'" >&2
        exit 1
    }
    local proxy_ip="${proxy_target%:*}"
    local proxy_port="${proxy_target##*:}"

    # Flush and enforce OUTPUT policy
    iptables -F OUTPUT >/dev/null 2>&1 || {
        echo "❌ iptables flush failed; need NET_ADMIN capability" >&2
        exit 1
    }
    iptables -P OUTPUT DROP
    iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    iptables -A OUTPUT -o lo -j ACCEPT
    # Allow DNS to Docker resolver
    iptables -A OUTPUT -p udp -d 127.0.0.11 --dport 53 -j ACCEPT
    iptables -A OUTPUT -p tcp -d 127.0.0.11 --dport 53 -j ACCEPT
    # Allow proxy traffic only
    iptables -A OUTPUT -p tcp -d "$proxy_ip" --dport "$proxy_port" -j ACCEPT
    iptables -A OUTPUT -p tcp -d "$proxy_ip" --dport 80 -j ACCEPT
    iptables -A OUTPUT -p tcp -d "$proxy_ip" --dport 443 -j ACCEPT
    PROXY_FIREWALL_APPLIED=1
    export PROXY_FIREWALL_APPLIED
    echo "🔒 Egress restricted to proxy ${proxy_ip}:${proxy_port}"
}

prepare_agent_task_runner_paths() {
    local log_root="/run/agent-task-runner"
    mkdir -p "$log_root"
    chown "$AGENT_CLI_UID:$AGENT_CLI_GID" "$log_root" 2>/dev/null || true
    chmod 0770 "$log_root" 2>/dev/null || true
}

ensure_dir_owned() {
    local path="$1"
    local mode="${2:-}"
    mkdir -p "$path"
    chown "$AGENT_UID:$AGENT_GID" "$path" 2>/dev/null || true
    if [ -n "$mode" ]; then
        chmod "$mode" "$path" 2>/dev/null || true
    fi
}

seed_tmpfs_from_base() {
    local base="$1"
    local target="$2"
    local mode="${3:-755}"
    mkdir -p "$target"
    if [ -d "$base" ] && [ -z "$(ls -A "$target" 2>/dev/null)" ]; then
        cp -a "$base"/. "$target"/ 2>/dev/null || true
    fi
    chmod "$mode" "$target" 2>/dev/null || true
}

install_host_session_configs() {
    local root="$1"
    local manifest="$root/manifest.json"
    local installed=1
    local -A targets=(
        ["github-copilot"]="/home/${AGENT_USERNAME}/.config/github-copilot/mcp"
        ["codex"]="/home/${AGENT_USERNAME}/.config/codex/mcp"
        ["claude"]="/home/${AGENT_USERNAME}/.config/claude/mcp"
    )

    for agent in "${!targets[@]}"; do
        local src="$root/${agent}/config.json"
        local dest_dir="${targets[$agent]}"
        if [ -f "$src" ]; then
            ensure_dir_owned "$dest_dir" 0700
            cp "$src" "$dest_dir/config.json"
            chown "$AGENT_UID:$AGENT_GID" "$dest_dir/config.json" 2>/dev/null || true
            chmod 0600 "$dest_dir/config.json" 2>/dev/null || true
            installed=0
        fi
    done

    if [ -f "$manifest" ]; then
        local manifest_dest="/home/${AGENT_USERNAME}/.config/containai/session-manifest.json"
        ensure_dir_owned "$(dirname "$manifest_dest")" 0700
        cp "$manifest" "$manifest_dest"
        chown "$AGENT_UID:$AGENT_GID" "$manifest_dest" 2>/dev/null || true
        chmod 0600 "$manifest_dest" 2>/dev/null || true
    fi

    return $installed
}

install_host_capabilities() {
    local root="$1"
    local target="/home/${AGENT_USERNAME}/.config/containai/capabilities"
    if [ ! -d "$root" ]; then
        return 1
    fi
    ensure_dir_owned "$target" 0700
    cp -a "$root/." "$target/" 2>/dev/null || true
    chown -R "$AGENT_UID:$AGENT_GID" "$target" 2>/dev/null || true
    find "$target" -type d -exec chmod 0700 {} + 2>/dev/null || true
    find "$target" -type f -exec chmod 0600 {} + 2>/dev/null || true
    return 0
}

ensure_stub_binaries() {
    local servers_file="$1"
    local runner="/usr/local/bin/mcp-stub-runner"
    [ -x "$runner" ] || return 0
    [ -f "$servers_file" ] || return 0
    mkdir -p "$STUB_SHIM_ROOT"
    while IFS= read -r stub; do
        [ -z "$stub" ] && continue
        local dest="${STUB_SHIM_ROOT}/mcp-stub-${stub}"
        if [ ! -e "$dest" ]; then
            ln -s "$runner" "$dest" 2>/dev/null || true
        fi
    done < "$servers_file"
}

create_stub_links_from_configs() {
    local runner="/usr/local/bin/mcp-stub-runner"
    [ -x "$runner" ] || return 0
    if [ "$#" -eq 0 ]; then
        return 0
    fi
    mkdir -p "$STUB_SHIM_ROOT"
    python3 - "$@" <<'PY' | while IFS= read -r stub; do
import json, sys
stubs = set()
for path in sys.argv[1:]:
    try:
        with open(path, "r", encoding="utf-8") as handle:
            data = json.load(handle)
    except Exception:
        continue
    if not isinstance(data, dict):
        continue
    servers = data.get("mcpServers") or {}
    for _, cfg in servers.items():
        if not isinstance(cfg, dict):
            continue
        env = cfg.get("env") or {}
        stub = env.get("CONTAINAI_STUB_NAME")
        if not stub:
            cmd = cfg.get("command", "")
            if isinstance(cmd, str) and "mcp-stub-" in cmd:
                stub = cmd.split("/")[-1].replace("mcp-stub-", "", 1)
        if stub:
            stubs.add(stub)
for stub in sorted(stubs):
    print(stub)
PY
    do
        [ -z "$stub" ] && continue
        local dest="${STUB_SHIM_ROOT}/mcp-stub-${stub}"
        if [ ! -e "$dest" ]; then
            ln -s "$runner" "$dest" 2>/dev/null || true
        fi
    done
}

parse_helper_definitions() {
    local helper_file="$1"
    [ -f "$helper_file" ] || return 0
    python3 - "$helper_file" <<'PY'
import json, sys
path = sys.argv[1]
try:
    with open(path, "r", encoding="utf-8") as handle:
        raw = json.load(handle)
except Exception:
    sys.exit(0)
helpers = raw if isinstance(raw, list) else raw.get("helpers", [])
for helper in helpers:
    name = helper.get("name")
    listen = helper.get("listen")
    target = helper.get("target")
    bearer = helper.get("bearerToken", "")
    if not name or not listen or not target:
        continue
    print(f"{name}|{listen}|{target}|{bearer}")
PY
}

start_mcp_helpers() {
    local helper_file="$1"
    [ -f "$helper_file" ] || return 0
    mkdir -p /run/mcp-helpers
    local line
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        IFS='|' read -r helper_name helper_listen helper_target helper_bearer <<< "$line"
        local log_file="/run/mcp-helpers/${helper_name}.log"
        local cmd=(env CONTAINAI_REQUIRE_PROXY=1 CONTAINAI_AGENT_ID="${AGENT_NAME:-}" CONTAINAI_SESSION_ID="${HOST_SESSION_ID:-}" python3 /usr/local/bin/mcp-http-helper.py --name "$helper_name" --listen "$helper_listen" --target "$helper_target")
        if [ -n "$helper_bearer" ]; then
            cmd+=("--bearer-token" "$helper_bearer")
        fi
        "${cmd[@]}" >"$log_file" 2>&1 &
        local pid=$!
        MCP_HELPER_PIDS+=("$pid")
        MCP_HELPER_NAMES+=("$helper_name")
        if command -v curl >/dev/null 2>&1; then
            curl --silent --max-time 2 "http://${helper_listen}/health" >/dev/null 2>&1 || \
                echo "⚠️  Helper ${helper_name} failed health check on ${helper_listen}" >&2
        fi
    done < <(parse_helper_definitions "$helper_file" || true)
}

link_agent_data_target() {
    local data_home="$1"
    local rel_path="$2"
    local kind="$3"
    local source_path="${data_home}/${rel_path}"
    local dest_path="/home/${AGENT_USERNAME}/${rel_path}"
    if [ "$kind" = "dir" ]; then
        mkdir -p "$source_path"
    else
        mkdir -p "$(dirname "$source_path")"
        : >"$source_path"
    fi
    mkdir -p "$(dirname "$dest_path")"
    rm -rf -- "$dest_path"
    ln -sfn "$source_path" "$dest_path"
    chown -h "$AGENT_UID:$AGENT_GID" "$dest_path" 2>/dev/null || true
}

link_agent_data_roots() {
    local agent="$1"
    local data_home="$2"
    case "$agent" in
        copilot)
            link_agent_data_target "$data_home" ".copilot" "dir"
            ;;
        codex)
            link_agent_data_target "$data_home" ".codex" "dir"
            ;;
        claude)
            link_agent_data_target "$data_home" ".claude" "dir"
            link_agent_data_target "$data_home" ".claude.json" "file"
            ;;
    esac
}

install_host_agent_data() {
    local root="$1"
    local dest_root="/run/agent-data"
    local session_id="${HOST_SESSION_ID:-default}"
    local imported=1
    local -a agents=("copilot" "codex" "claude")
    local packager="/usr/local/bin/package-agent-data.py"

    if [ ! -x "$packager" ]; then
        echo "⚠️  Data packager missing; cannot import host data safely" >&2
        return 1
    fi

    for agent in "${agents[@]}"; do
        local src_dir="$root/${agent}/data/${session_id}"
        local tar_path="$src_dir/data-import.tar"
        local manifest_path="$src_dir/manifest.json"
        local key_path="$src_dir/data-hmac.key"
        local dest_dir="${dest_root}/${agent}/${session_id}"
        local data_home="${dest_dir}/home"

        mkdir -p -- "$data_home"
        chmod 0770 "$dest_dir" "$data_home" 2>/dev/null || true

        if [ -f "$tar_path" ] && [ -s "$tar_path" ]; then
            if [ ! -f "$manifest_path" ] || [ ! -s "$manifest_path" ]; then
                echo "❌ Missing manifest for ${agent} data payload; refusing to import" >&2
                rm -rf -- "$data_home"
                mkdir -p -- "$data_home"
                continue
            fi
            if [ ! -f "$key_path" ] || [ ! -s "$key_path" ]; then
                echo "❌ Missing HMAC key for ${agent} data payload; refusing to import" >&2
                rm -rf -- "$data_home"
                mkdir -p -- "$data_home"
                continue
            fi
            rm -rf -- "$data_home"
            mkdir -p -- "$data_home"
            if python3 "$packager" \
                --mode merge \
                --agent "$agent" \
                --session-id "$session_id" \
                --manifest "$manifest_path" \
                --tar "$tar_path" \
                --target-home "$data_home" \
                --require-hmac \
                --hmac-key-file "$key_path"; then
                imported=0
                chown -R "$AGENT_CLI_UID:$AGENT_CLI_GID" "$data_home" 2>/dev/null || true
                find "$data_home" -type d -exec chmod 0770 {} + 2>/dev/null || true
                find "$data_home" -type f -exec chmod 0660 {} + 2>/dev/null || true
                echo "📦 Imported ${agent} data payload"
            else
                echo "❌ HMAC validation failed for ${agent} data payload" >&2
                rm -rf -- "$data_home"
                mkdir -p -- "$data_home"
            fi
        fi

        if [ -f "$manifest_path" ]; then
            cp "$manifest_path" "$dest_dir/import-manifest.json"
            chown "$AGENT_CLI_UID:$AGENT_CLI_GID" "$dest_dir/import-manifest.json" 2>/dev/null || true
            chmod 0660 "$dest_dir/import-manifest.json" 2>/dev/null || true
        fi
        if [ -f "$key_path" ]; then
            cp "$key_path" "$dest_dir/data-hmac.key"
            chown "$AGENT_CLI_UID:$AGENT_CLI_GID" "$dest_dir/data-hmac.key" 2>/dev/null || true
            chmod 0660 "$dest_dir/data-hmac.key" 2>/dev/null || true
        fi

        chown -R "$AGENT_CLI_UID:$AGENT_CLI_GID" "$dest_dir" 2>/dev/null || true
        link_agent_data_roots "$agent" "$data_home"
        if [ "$agent" = "${AGENT_NAME:-}" ]; then
            export CONTAINAI_AGENT_DATA_HOME="$data_home"
            export CONTAINAI_AGENT_HOME="/home/${AGENT_USERNAME}"
        fi
    done

    return $imported
}

ensure_agent_data_fallback() {
    local agent="$1"
    local session_id="${HOST_SESSION_ID:-default}"
    local fallback_dir="/run/agent-data/${agent}/${session_id}/home"
    mkdir -p "$fallback_dir"
    if [ "$(id -u)" -eq 0 ]; then
        chown -R "$AGENT_CLI_UID:$AGENT_CLI_GID" "/run/agent-data/${agent}" 2>/dev/null || true
    fi
    link_agent_data_roots "$agent" "$fallback_dir"
    if [ "$agent" = "${AGENT_NAME:-}" ]; then
        export CONTAINAI_AGENT_DATA_HOME="$fallback_dir"
        export CONTAINAI_AGENT_HOME="/home/${AGENT_USERNAME}"
    fi
}

start_agent_task_runnerd() {
    if [ ! -x /usr/local/bin/agent-task-runnerd ]; then
        return
    fi
    local socket_path="${AGENT_TASK_RUNNER_SOCKET:-/run/agent-task-runner.sock}"
    local log_dir="/run/agent-task-runner"
    mkdir -p "$log_dir"
    if [ -S "$socket_path" ]; then
        rm -f "$socket_path"
    fi
    if /usr/local/bin/agent-task-runnerd \
        --socket "$socket_path" \
        --log "$log_dir/events.log" \
        --policy "${CONTAINAI_RUNNER_POLICY:-observe}" \
        >/dev/null 2>&1 & then
        :
    else
        echo "⚠️  Failed to launch agent-task-runnerd" >&2
    fi
}

export_agent_data_payload() {
    local packager="/usr/local/bin/package-agent-data.py"
    local agent="${AGENT_NAME:-}"
    local session_id="${HOST_SESSION_ID:-}"
    local data_root="/run/agent-data"
    local export_root="/run/agent-data-export"

    if [ -z "$agent" ] || [ -z "$session_id" ]; then
        return 0
    fi
    if [ ! -x "$packager" ]; then
        return 0
    fi

    local source_dir="${data_root}/${agent}/${session_id}"
    local data_home="${source_dir}/home"
    if [ ! -d "$data_home" ]; then
        return 0
    fi

    local key_path="${source_dir}/data-hmac.key"
    if [ ! -f "$key_path" ]; then
        echo "⚠️  Missing data HMAC key for ${agent}; skipping export" >&2
        return 0
    fi

    local agent_export_dir="${export_root}/${agent}/${session_id}"
    rm -rf -- "$agent_export_dir"
    mkdir -p -- "$agent_export_dir"

    local tar_path="${agent_export_dir}/data-export.tar"
    local manifest_path="${agent_export_dir}/data-export.manifest.json"

    if python3 "$packager" \
        --agent "$agent" \
        --session-id "$session_id" \
        --home-path "$data_home" \
        --tar "$tar_path" \
        --manifest "$manifest_path" \
        --hmac-key-file "$key_path"; then
        if [ -s "$tar_path" ]; then
            echo "📤 Prepared ${agent} data export payload"
        else
            rm -f "$tar_path" "$manifest_path"
            rmdir --ignore-fail-on-non-empty "$agent_export_dir" 2>/dev/null || true
        fi
    else
        echo "⚠️  Failed to package ${agent} data export payload" >&2
        rm -rf -- "$agent_export_dir"
    fi
}

prepare_rootfs_mounts() {
    umask 0002
    ensure_dir_owned "/workspace" 0775
    ensure_dir_owned "/home/${AGENT_USERNAME}" 0755
    ensure_dir_owned "$TOOLCACHE_DIR" 0775

    local cache_paths=(
        "pip"
        "pipx"
        "pipx/bin"
        "npm"
        "yarn"
        "pnpm"
        "uv"
        "cargo"
        "rustup"
        "ms-playwright"
        "bun"
        "nuget"
        "nuget/http-cache"
        "nuget/packages"
        "dotnet"
    )

    for rel in "${cache_paths[@]}"; do
        ensure_dir_owned "${TOOLCACHE_DIR}/${rel}" 0775
    done

    seed_tmpfs_from_base "${BASEFS_DIR}/var/lib/dpkg" "/var/lib/dpkg"
    seed_tmpfs_from_base "${BASEFS_DIR}/var/lib/apt" "/var/lib/apt"
    seed_tmpfs_from_base "${BASEFS_DIR}/var/cache/apt" "/var/cache/apt"
    seed_tmpfs_from_base "${BASEFS_DIR}/var/cache/debconf" "/var/cache/debconf"

    chmod 1777 /tmp /var/tmp 2>/dev/null || true
    chmod 0755 /run /var/log 2>/dev/null || true
}

if [ "$(id -u)" -eq 0 ]; then
    prepare_rootfs_mounts
    enforce_ptrace_scope
    harden_proc_visibility
    prepare_sensitive_tmpfs "/home/${AGENT_USERNAME}/.config/containai/capabilities" "$CAP_TMPFS_SIZE" "$AGENT_UID" "$AGENT_GID" "700"
    prepare_sensitive_tmpfs "/run/agent-secrets" "$SECRETS_TMPFS_SIZE" "$AGENT_CLI_UID" "$AGENT_CLI_GID" "770"
    prepare_sensitive_tmpfs "/run/agent-data" "$DATA_TMPFS_SIZE" "$AGENT_CLI_UID" "$AGENT_CLI_GID" "770"
    prepare_sensitive_tmpfs "/run/agent-data-export" "$DATA_TMPFS_SIZE" "$AGENT_CLI_UID" "$AGENT_CLI_GID" "770"
    enforce_proxy_firewall
    prepare_agent_task_runner_paths
    CONTAINAI_AGENT_DATA_STAGED=0
    if [ -n "${HOST_SESSION_CONFIG_ROOT:-}" ] && [ -d "${HOST_SESSION_CONFIG_ROOT:-}" ]; then
        if install_host_agent_data "$HOST_SESSION_CONFIG_ROOT"; then
            echo "📂 Agent data caches staged under /run/agent-data"
        fi
        CONTAINAI_AGENT_DATA_STAGED=1
    fi
    if [ "$CONTAINAI_AGENT_DATA_STAGED" -ne 1 ] && [ -n "${AGENT_NAME:-}" ]; then
        ensure_agent_data_fallback "$AGENT_NAME"
        CONTAINAI_AGENT_DATA_STAGED=1
    fi
    export CONTAINAI_AGENT_DATA_STAGED
    start_agent_task_runnerd
    export CONTAINAI_RUNNER_STARTED=1
    if command -v gosu >/dev/null 2>&1; then
        exec gosu "$AGENT_USERNAME" /usr/local/bin/entrypoint.sh "$@"
    elif command -v sudo >/dev/null 2>&1; then
        exec sudo -E -u "$AGENT_USERNAME" /usr/local/bin/entrypoint.sh "$@"
    else
        echo "❌ Unable to drop privileges to $AGENT_USERNAME (gosu/sudo missing)" >&2
        exit 1
    fi
fi

AGENT_TASK_RUNNER_SOCKET="${AGENT_TASK_RUNNER_SOCKET:-/run/agent-task-runner.sock}"
export AGENT_TASK_RUNNER_SOCKET
if [ "${CONTAINAI_RUNNER_STARTED:-0}" != "1" ]; then
    start_agent_task_runnerd
fi
enforce_proxy_firewall

echo "🚀 Starting ContainAI Container..."


# Cleanup function to push changes before shutdown
cleanup_on_shutdown() {
    echo ""
    echo "📤 Container shutting down..."

    export_agent_data_payload

    if [ ${#MCP_HELPER_PIDS[@]} -gt 0 ]; then
        for helper_pid in "${MCP_HELPER_PIDS[@]}"; do
            kill "$helper_pid" >/dev/null 2>&1 || true
        done
    fi
    rm -rf /run/mcp-helpers /run/mcp-stubs

    # Check if auto-commit/push is enabled (default: true)
    AUTO_COMMIT="${AUTO_COMMIT_ON_SHUTDOWN:-true}"
    AUTO_PUSH="${AUTO_PUSH_ON_SHUTDOWN:-true}"
    
    if [ "$AUTO_COMMIT" != "true" ] && [ "$AUTO_PUSH" != "true" ]; then
        echo "⏭️  Auto-commit and auto-push disabled, skipping..."
        return 0
    fi
    
    # Only process if in a git repository
    if [ -d /workspace/.git ]; then
        cd /workspace || {
            echo "⚠️  Warning: Could not change to workspace directory"
            return 0
        }
        
        # Check if there are any changes (staged or unstaged)
        if ! git diff-index --quiet HEAD -- 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
            if [ "$AUTO_COMMIT" = "true" ]; then
                echo "💾 Uncommitted changes detected, creating automatic commit..."
                
                # Get repository and branch info
                REPO_NAME=$(basename "$(git rev-parse --show-toplevel 2>/dev/null)")
                BRANCH=$(git branch --show-current 2>/dev/null)
                
                # Stage all changes (tracked and untracked)
                git add -A 2>/dev/null || {
                    echo "⚠️  Warning: Failed to stage changes"
                    return 0
                }
                
                # Generate commit message based on changes
                COMMIT_MSG=$(generate_auto_commit_message)
                
                # Create commit
                if git commit -m "$COMMIT_MSG" 2>/dev/null; then
                    echo "✅ Auto-commit created"
                    echo "   Message: $COMMIT_MSG"
                    
                    # Push if auto-push is also enabled
                    if [ "$AUTO_PUSH" = "true" ] && [ -n "$BRANCH" ]; then
                        # Validate branch name (alphanumeric, dash, underscore, slash only)
                        if [[ "$BRANCH" =~ ^[a-zA-Z0-9/_-]+$ ]]; then
                            echo "📤 Pushing changes to local remote..."
                            if git push local "$BRANCH" 2>/dev/null; then
                                echo "✅ Changes pushed to local remote: $REPO_NAME ($BRANCH)"
                            else
                                echo "⚠️  Failed to push (local remote may not be configured)"
                                echo "💡 Run: git remote add local <url> to enable auto-push"
                            fi
                        else
                            echo "⚠️  Invalid branch name, skipping push"
                        fi
                    fi
                else
                    echo "⚠️  Warning: Failed to create commit"
                fi
            else
                echo "⚠️  Uncommitted changes exist but auto-commit is disabled"
                echo "💡 Set AUTO_COMMIT_ON_SHUTDOWN=true to enable"
            fi
        else
            echo "✅ No uncommitted changes"
        fi
    fi
}

# Generate intelligent commit message based on git status
generate_auto_commit_message() {
    
    # Get git diff summary
    local diff_stat
    diff_stat=$(git diff --cached --stat 2>/dev/null | tail -1)
    local files_changed
    files_changed=$(git diff --cached --name-only 2>/dev/null | head -10)
    
    # Try to generate commit message using the active AI agent
    local ai_message=""
    
    # Check if GitHub Copilot CLI is available and authenticated
    if command -v github-copilot-cli &> /dev/null && gh auth status &> /dev/null 2>&1; then
        echo "🤖 Asking GitHub Copilot to generate commit message..." >&2
        
        # Create prompt for the AI
        local prompt="Based on these git changes, write a concise commit message (50 chars max, conventional commits format):

Files changed:
$files_changed

Diff summary:
$diff_stat

Provide only the commit message, no explanation."
        
        # Use GitHub Copilot to generate message (with timeout)
        ai_message=$(timeout 10s github-copilot-cli suggest "$prompt" 2>/dev/null | head -1 | tr -d '\n' || echo "")
        
    # Fallback: Check if gh copilot is available as extension
    elif command -v gh &> /dev/null && gh auth status &> /dev/null 2>&1; then
        if gh copilot --help &> /dev/null 2>&1; then
            echo "🤖 Asking GitHub Copilot to generate commit message..." >&2
            
            local prompt="Write a concise git commit message for these changes (max 50 chars, conventional commits format):
$files_changed

Only output the commit message, nothing else."
            
            ai_message=$(timeout 10s gh copilot suggest -t shell "$prompt" 2>/dev/null | grep -v "^$" | head -1 | tr -d '\n' || echo "")
        fi
    fi
    
    # Clean up AI message if we got one
    if [ -n "$ai_message" ]; then
        # Remove common prefixes and clean up
        ai_message=$(echo "$ai_message" | sed -e 's/^git commit -m "//' -e 's/"$//' -e 's/^[Cc]ommit message: //' -e 's/^Message: //' | tr -d '\n')
        
        # Sanitize: remove control characters, limit length
        ai_message=$(echo "$ai_message" | tr -d '\r\n\t' | head -c 100)
        
        # Validate it's reasonable (not too long, not empty)
        if [ ${#ai_message} -gt 10 ] && [ ${#ai_message} -lt 100 ]; then
            echo "$ai_message"
            return 0
        fi
    fi
    
    # Fallback: Generate basic message if AI fails
    local added modified deleted
    added=$(git diff --cached --name-only --diff-filter=A 2>/dev/null | wc -l)
    modified=$(git diff --cached --name-only --diff-filter=M 2>/dev/null | wc -l)
    deleted=$(git diff --cached --name-only --diff-filter=D 2>/dev/null | wc -l)
    
    local msg_parts=()
    if [ "$added" -gt 0 ]; then msg_parts+=("$added added"); fi
    if [ "$modified" -gt 0 ]; then msg_parts+=("$modified modified"); fi
    if [ "$deleted" -gt 0 ]; then msg_parts+=("$deleted deleted"); fi
    
    local changes
    changes=$(IFS=", "; echo "${msg_parts[*]}")
    echo "chore: auto-commit ($changes)"
}

# Register cleanup on shutdown signals
trap cleanup_on_shutdown SIGTERM SIGINT EXIT

# Ensure we're in the workspace directory
cd /workspace || exit 1

# Display current repository information (concise)
if [ -d .git ]; then
    branch=$(git branch --show-current 2>/dev/null || echo 'detached')
    echo "📁 $(git remote get-url origin 2>/dev/null || echo 'Local repository') [${branch}]"
else
    echo "⚠️  Not a git repository - run 'git init' if needed"
fi

# Configure git to use generic credential helper that delegates to host's auth
# Works with GitHub, GitLab, Bitbucket, Azure DevOps, self-hosted, etc.
# The credential helper tries: gh CLI (for github.com) -> git-credential-store
git config --global credential.helper ""
git config --global credential.helper '!/usr/local/bin/git-credential-host-helper.sh'

# Configure git autocrlf for Windows compatibility
git config --global core.autocrlf true

# Configure commit signing if host has it configured
# This allows verified commits while keeping signing keys secure on host
if [ -f /home/agentuser/.gitconfig ]; then
    # Check if host has GPG signing configured
    if host_gpg_key=$(git config --file /home/agentuser/.gitconfig user.signingkey 2>/dev/null); then
        if [ -n "$host_gpg_key" ]; then
            # Copy GPG signing configuration from host
            git config --global user.signingkey "$host_gpg_key"
            
            # Check if host has commit signing enabled
            if git config --file /home/agentuser/.gitconfig commit.gpgsign 2>/dev/null | grep -q "true"; then
                git config --global commit.gpgsign true
                
                # Use GPG proxy instead of copying host's gpg.program path
                # This keeps private keys secure on host
                if [ -S "${GPG_PROXY_SOCKET:-/tmp/gpg-proxy.sock}" ]; then
                    git config --global gpg.program /usr/local/bin/gpg-host-proxy.sh
                    echo "🔏 Commit signing: GPG via proxy (key: ${host_gpg_key:0:8}...)"
                elif [ -S "${HOME}/.gnupg/S.gpg-agent" ]; then
                    # Fallback: Use direct GPG agent socket if available
                    git config --global gpg.program gpg
                    echo "🔏 Commit signing: GPG via agent (key: ${host_gpg_key:0:8}...)"
                else
                    echo "⚠️  GPG signing configured but proxy/agent unavailable"
                fi
            fi
        fi
    fi
    
    # Check if host has SSH signing configured (newer git feature)
    if host_ssh_key=$(git config --file /home/agentuser/.gitconfig user.signingkey 2>/dev/null); then
        if git config --file /home/agentuser/.gitconfig gpg.format 2>/dev/null | grep -q "ssh"; then
            # Copy SSH signing configuration from host
            git config --global gpg.format ssh
            git config --global user.signingkey "$host_ssh_key"
            
            if git config --file /home/agentuser/.gitconfig commit.gpgsign 2>/dev/null | grep -q "true"; then
                git config --global commit.gpgsign true
                echo "🔏 Commit signing: SSH via agent"
            fi
            
            # SSH signing uses SSH agent socket - already forwarded if available
            # The signing key can be different from authentication key
        fi
    fi
fi

HOST_CONFIG_DEPLOYED=false
if [ -n "${HOST_SESSION_CONFIG_ROOT:-}" ] && [ -d "${HOST_SESSION_CONFIG_ROOT:-}" ]; then
    echo "🔐 Applying host-rendered MCP configs (session ${HOST_SESSION_ID:-unknown})"
    if install_host_session_configs "$HOST_SESSION_CONFIG_ROOT"; then
        HOST_CONFIG_DEPLOYED=true
        echo "   Manifest SHA: ${HOST_SESSION_CONFIG_SHA256:-unknown}"
    else
        echo "⚠️  Host session config directory missing agent payloads; falling back to workspace config.toml"
    fi
fi

if [ -n "${HOST_CAPABILITY_ROOT:-}" ] && [ -d "${HOST_CAPABILITY_ROOT:-}" ]; then
    echo "🔑 Installing capability tokens from host"
    if install_host_capabilities "$HOST_CAPABILITY_ROOT"; then
        echo "   Capability tokens staged"
    else
        echo "⚠️  Failed to install capability tokens"
    fi
fi

if [ -n "${HOST_SESSION_CONFIG_ROOT:-}" ] && [ -d "${HOST_SESSION_CONFIG_ROOT:-}" ] && [ "${CONTAINAI_AGENT_DATA_STAGED:-0}" != "1" ]; then
    if install_host_agent_data "$HOST_SESSION_CONFIG_ROOT"; then
        echo "📂 Agent data caches staged under /run/agent-data"
        CONTAINAI_AGENT_DATA_STAGED=1
    fi
fi

if [ -n "${AGENT_NAME:-}" ] && [ -z "${CONTAINAI_AGENT_DATA_HOME:-}" ]; then
    ensure_agent_data_fallback "$AGENT_NAME"
fi

HELPER_MANIFEST_PATH=""
if [ -n "${HOST_SESSION_CONFIG_ROOT:-}" ] && [ -d "${HOST_SESSION_CONFIG_ROOT:-}" ]; then
    servers_file="$HOST_SESSION_CONFIG_ROOT/servers.txt"
    ensure_stub_binaries "$servers_file"
    helper_candidate="$HOST_SESSION_CONFIG_ROOT/helpers.json"
    if [ -f "$helper_candidate" ]; then
        HELPER_MANIFEST_PATH="$helper_candidate"
    fi
fi

if [ "$HOST_CONFIG_DEPLOYED" = false ] && [ -f "/workspace/config.toml" ]; then
    /usr/local/bin/setup-mcp-configs.sh 2>&1 | grep -E "^(ERROR|WARN)" || true
fi

create_stub_links_from_configs \
    "/home/${AGENT_USERNAME}/.config/github-copilot/mcp/config.json" \
    "/home/${AGENT_USERNAME}/.config/codex/mcp/config.json" \
    "/home/${AGENT_USERNAME}/.config/claude/mcp/config.json"

if [ -z "$HELPER_MANIFEST_PATH" ]; then
    HELPER_MANIFEST_PATH="/home/${AGENT_USERNAME}/.config/containai/helpers.json"
fi

if [ -n "$HELPER_MANIFEST_PATH" ] && [ ! -f "$HELPER_MANIFEST_PATH" ]; then
    for _ in {1..5}; do
        [ -f "$HELPER_MANIFEST_PATH" ] && break
        sleep 0.2
    done
fi

if [ -f "$HELPER_MANIFEST_PATH" ]; then
    echo "🔧 Starting MCP helper proxies from ${HELPER_MANIFEST_PATH}"
    start_mcp_helpers "$HELPER_MANIFEST_PATH"
else
    echo "ℹ️  No MCP helper manifest found; remote helpers not started"
fi

# Index project with Serena for faster semantic operations (silent unless error)
if [ -d "/workspace/.git" ]; then
    uvx --from "git+https://github.com/oraios/serena" serena project index --project /workspace >/dev/null 2>&1 || \
        echo "⚠️  Serena indexing failed"
fi

# Load MCP secrets from host mount if available
if [ -f "/home/agentuser/.mcp-secrets.env" ]; then
    set -a
    # shellcheck source=/home/agentuser/.mcp-secrets.env disable=SC1091
    source /home/agentuser/.mcp-secrets.env
    set +a
fi

# Update Serena MCP server to latest version (silent)
uvx --refresh --from "git+https://github.com/oraios/serena@main" serena --version >/dev/null 2>&1 || true

# Check authentication and configuration (concise summary)
echo ""

# Collect authentication status quietly
auth_status=""
git_user=$(git config user.name 2>/dev/null || echo "")
[ -n "$git_user" ] && auth_status="${auth_status}git:${git_user} "

if [ -S "${CREDENTIAL_SOCKET:-/tmp/git-credential-proxy.sock}" ]; then
    auth_status="${auth_status}creds:proxy(secure) "
elif command -v gh &> /dev/null && gh auth status &> /dev/null 2>&1; then
    auth_status="${auth_status}creds:gh "
elif [ -f ~/.git-credentials ]; then
    auth_status="${auth_status}creds:file "
fi

if [ -n "${SSH_AUTH_SOCK:-}" ] && [ -S "$SSH_AUTH_SOCK" ]; then
    key_count=$(ssh-add -l 2>/dev/null | grep -cv "no identities" || true)
    if [ "$key_count" -gt 0 ]; then
        auth_status="${auth_status}ssh:${key_count}keys "
    fi
elif [ -d ~/.ssh ] && [ -n "$(ls -A ~/.ssh/id_* 2>/dev/null)" ]; then
    auth_status="${auth_status}ssh:keys-only "
fi

# Single-line authentication summary
if [ -n "$auth_status" ]; then
    echo "✅ Auth: ${auth_status}"
else
    echo "⚠️  No authentication configured - see docs/vscode-integration.md"
fi

echo "✨ Container ready | MCP: /workspace/config.toml | Auto-commit on shutdown"
echo ""

SESSION_HELPER="/usr/local/bin/agent-session"
SESSION_MODE="${AGENT_SESSION_MODE:-disabled}"

if [ -x "$SESSION_HELPER" ]; then
    case "$SESSION_MODE" in
        supervised)
            # Run primary command inside managed tmux session for detach/reconnect support
            "$SESSION_HELPER" supervise "$@"
            exit $?
            ;;
        shell)
            # Ensure an interactive shell session exists alongside the main process
            SHELL_ARGS=()
            if [ -n "${AGENT_SESSION_SHELL_BIN:-}" ]; then
                SHELL_ARGS+=("$AGENT_SESSION_SHELL_BIN")
            fi
            if [ -n "${AGENT_SESSION_SHELL_ARGS:-}" ]; then
                read -r -a __extra_shell_args <<< "${AGENT_SESSION_SHELL_ARGS}"
                SHELL_ARGS+=("${__extra_shell_args[@]}")
            fi
            if [ ${#SHELL_ARGS[@]} -eq 0 ]; then
                SHELL_ARGS=("/bin/bash" "-l")
            fi
            "$SESSION_HELPER" ensure-shell "${SHELL_ARGS[@]}"
            ;;
    esac
fi

# Execute the command passed to the container
exec "$@"
