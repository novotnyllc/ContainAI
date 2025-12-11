#!/usr/bin/env bash
set -euo pipefail

# Capture caller-provided CONTAINAI_* values, then drop them from the environment
# to avoid leaking user-supplied values into child processes. We later export
# sanitized values explicitly when needed.
CA_USER="${CONTAINAI_USER:-agentuser}"
CA_CLI_USER="${CONTAINAI_CLI_USER:-agentcli}"
CA_BASEFS="${CONTAINAI_BASEFS:-/opt/containai/basefs}"
CA_TOOLCACHE="${CONTAINAI_TOOLCACHE:-/toolcache}"
CA_PTRACE_SCOPE="${CONTAINAI_PTRACE_SCOPE:-3}"
CA_CAP_TMPFS_SIZE="${CONTAINAI_CAP_TMPFS_SIZE:-16m}"
CA_DATA_TMPFS_SIZE="${CONTAINAI_DATA_TMPFS_SIZE:-64m}"
CA_SECRET_TMPFS_SIZE="${CONTAINAI_SECRET_TMPFS_SIZE:-32m}"
CA_DISABLE_PTRACE_SCOPE="${CONTAINAI_DISABLE_PTRACE_SCOPE:-0}"
CA_DISABLE_PROC_HARDENING="${CONTAINAI_DISABLE_PROC_HARDENING:-0}"
CA_PROC_GROUP="${CONTAINAI_PROC_GROUP:-agentproc}"
CA_RUNNER_POLICY="${CONTAINAI_RUNNER_POLICY:-observe}"
CA_AGENT_DATA_STAGED="${CONTAINAI_AGENT_DATA_STAGED:-0}"
CA_RUNNER_STARTED="${CONTAINAI_RUNNER_STARTED:-0}"
CA_AGENT_DATA_HOME="${CONTAINAI_AGENT_DATA_HOME:-}"
CA_AGENT_HOME="${CONTAINAI_AGENT_HOME:-}"
CA_LOG_DIR="${CONTAINAI_LOG_DIR:-}"

clear_containai_env() {
    for name in $(env | sed -n 's/^\(CONTAINAI_[^=]*\)=.*/\1/p'); do
        unset "$name"
    done
}
clear_containai_env

AGENT_USERNAME="$CA_USER"
AGENT_UID=$(id -u "$AGENT_USERNAME" 2>/dev/null || echo 1000)
AGENT_GID=$(id -g "$AGENT_USERNAME" 2>/dev/null || echo 1000)
AGENT_CLI_USERNAME="$CA_CLI_USER"
AGENT_CLI_UID=$(id -u "$AGENT_CLI_USERNAME" 2>/dev/null || echo "$AGENT_UID")
AGENT_CLI_GID=$(id -g "$AGENT_CLI_USERNAME" 2>/dev/null || echo "$AGENT_GID")
BASEFS_DIR="$CA_BASEFS"
TOOLCACHE_DIR="$CA_TOOLCACHE"
PTRACE_SCOPE_VALUE="$CA_PTRACE_SCOPE"
CAP_TMPFS_SIZE="$CA_CAP_TMPFS_SIZE"
DATA_TMPFS_SIZE="$CA_DATA_TMPFS_SIZE"
SECRETS_TMPFS_SIZE="$CA_SECRET_TMPFS_SIZE"
DISABLE_PTRACE_SCOPE="$CA_DISABLE_PTRACE_SCOPE"
DISABLE_PROC_HARDENING="$CA_DISABLE_PROC_HARDENING"
PROC_GROUP="$CA_PROC_GROUP"
RUNNER_POLICY="$CA_RUNNER_POLICY"
AGENT_DATA_STAGED="$CA_AGENT_DATA_STAGED"
RUNNER_STARTED="$CA_RUNNER_STARTED"
AGENT_DATA_HOME="$CA_AGENT_DATA_HOME"
AGENT_HOME="$CA_AGENT_HOME"
LOG_DIR="$CA_LOG_DIR"

STUB_SHIM_ROOT="/home/${AGENT_USERNAME}/.local/bin"
declare -a MCP_HELPER_PIDS=()
declare -a MCP_HELPER_NAMES=()
PROXY_FIREWALL_APPLIED="${PROXY_FIREWALL_APPLIED:-0}"

wait_for_host_payload() {
    local path="$1"
    local retries="$2"
    local interval="$3"
    local i=0
    while [ "$i" -lt "$retries" ]; do
        if [ -n "$(ls -A "$path" 2>/dev/null)" ]; then
            return 0
        fi
        sleep "$interval"
        i=$((i + 1))
    done
    return 1
}

prepare_agent_secrets_path() {
    local secrets_dir="/run/agent-secrets"
    mkdir -p "$secrets_dir"
    chown "$AGENT_CLI_UID:$AGENT_CLI_GID" "$secrets_dir" 2>/dev/null || true
    chmod 0770 "$secrets_dir" 2>/dev/null || true
}

prepare_agent_task_runner_paths() {
    local log_root="/run/agent-task-runner"
    mkdir -p "$log_root"
    chown "$AGENT_UID:$AGENT_GID" "$log_root" 2>/dev/null || true
    chmod 0770 "$log_root" 2>/dev/null || true

    local audit_dir="/run/containai"
    mkdir -p "$audit_dir"
    chown "$AGENT_UID:$AGENT_GID" "$audit_dir" 2>/dev/null || true
    chmod 0755 "$audit_dir" 2>/dev/null || true
}

prepare_mcp_helpers_paths() {
    local helpers_dir="/run/mcp-helpers"
    mkdir -p "$helpers_dir"
    chown "$AGENT_UID:$AGENT_GID" "$helpers_dir" 2>/dev/null || true
    chmod 0755 "$helpers_dir" 2>/dev/null || true
}

prepare_mcp_wrappers_paths() {
    local wrappers_dir="/run/mcp-wrappers"
    mkdir -p "$wrappers_dir"
    chown "$AGENT_UID:$AGENT_GID" "$wrappers_dir" 2>/dev/null || true
    chmod 1777 "$wrappers_dir" 2>/dev/null || true
}

prepare_agent_data_export_path() {
    local export_dir="/run/agent-data-export"
    mkdir -p "$export_dir"
    chown "$AGENT_UID:$AGENT_GID" "$export_dir" 2>/dev/null || true
    chmod 0755 "$export_dir" 2>/dev/null || true
}

prepare_agent_data_path() {
    local data_dir="/run/agent-data"
    mkdir -p "$data_dir"
    chown "$AGENT_CLI_UID:$AGENT_CLI_GID" "$data_dir" 2>/dev/null || true
    chmod 0770 "$data_dir" 2>/dev/null || true
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
    local trust_bundle_src="${HOST_MITM_CA_CERT:-$root/mitm/proxy-ca.crt}"
    local trust_bundle_dest="/usr/local/share/ca-certificates/containai-proxy.crt"

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

    # Install proxy CA if provided
    if [ -f "$trust_bundle_src" ]; then
        echo "🔐 Installing proxy MITM CA into trust store"
        cp "$trust_bundle_src" "$trust_bundle_dest"
        chown root:root "$trust_bundle_dest" 2>/dev/null || true
        chmod 644 "$trust_bundle_dest" 2>/dev/null || true
        if command -v update-ca-certificates >/dev/null 2>&1; then
            update-ca-certificates >/dev/null 2>&1 || true
        fi
        # Python: SSL_CERT_FILE and REQUESTS_CA_BUNDLE
        SSL_CERT_FILE="$trust_bundle_dest"
        REQUESTS_CA_BUNDLE="$SSL_CERT_FILE"
        export SSL_CERT_FILE
        export REQUESTS_CA_BUNDLE
        # Node.js: NODE_EXTRA_CA_CERTS (Node uses bundled CAs, not system store)
        NODE_EXTRA_CA_CERTS="$trust_bundle_dest"
        export NODE_EXTRA_CA_CERTS
        # .NET: Uses system CA store via OpenSSL (update-ca-certificates above)
        # Explicitly set SSL_CERT_DIR for .NET HttpClient fallback
        SSL_CERT_DIR="/etc/ssl/certs"
        export SSL_CERT_DIR
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

ensure_wrapper_binaries() {
    local servers_file="$1"
    local runner="/usr/local/bin/mcp-wrapper-runner"
    [ -x "$runner" ] || return 0
    [ -f "$servers_file" ] || return 0
    ensure_dir_owned "$STUB_SHIM_ROOT" 0755
    while IFS= read -r name; do
        [ -z "$name" ] && continue
        local dest="${STUB_SHIM_ROOT}/mcp-wrapper-${name}"
        if [ ! -e "$dest" ]; then
            ln -s "$runner" "$dest" 2>/dev/null || true
            chown -h "$AGENT_UID:$AGENT_GID" "$dest" 2>/dev/null || true
        fi
    done < "$servers_file"
}

create_wrapper_links_from_configs() {
    local runner="/usr/local/bin/mcp-wrapper-runner"
    [ -x "$runner" ] || return 0
    if [ "$#" -eq 0 ]; then
        return 0
    fi
    ensure_dir_owned "$STUB_SHIM_ROOT" 0755
    python3 - "$@" <<'PY' | while IFS= read -r name; do
import json, sys
names = set()
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
        name = env.get("CONTAINAI_WRAPPER_NAME")
        if not name:
            cmd = cfg.get("command", "")
            if isinstance(cmd, str) and "mcp-wrapper-" in cmd:
                name = cmd.split("/")[-1].replace("mcp-wrapper-", "", 1)
        if name:
            names.add(name)
for name in sorted(names):
    print(name)
PY
        [ -z "$name" ] && continue
        local dest="${STUB_SHIM_ROOT}/mcp-wrapper-${name}"
        if [ ! -e "$dest" ]; then
            ln -s "$runner" "$dest" 2>/dev/null || true
            chown -h "$AGENT_UID:$AGENT_GID" "$dest" 2>/dev/null || true
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
        
        # Calculate deterministic UID for this helper (range 40000-60000, separate from wrappers)
        local helper_uid
        helper_uid=$(python3 -c "import hashlib; print(40000 + (int(hashlib.sha256('helper-${helper_name}'.encode()).hexdigest(), 16) % 20000))")
        
        # Create isolated runtime directory for this helper
        local helper_runtime="/run/mcp-helpers/${helper_name}"
        mkdir -p "$helper_runtime"
        chown "$helper_uid:$helper_uid" "$helper_runtime"
        chmod 700 "$helper_runtime"
        
        local log_file="${helper_runtime}/helper.log"
        local helper_ca="${SSL_CERT_FILE:-${HOST_MITM_CA_CERT:-}}"
        
        # Build environment for the helper process
        local helper_env=(
            "CONTAINAI_REQUIRE_PROXY=1"
            "CONTAINAI_AGENT_ID=${AGENT_NAME:-}"
            "CONTAINAI_SESSION_ID=${HOST_SESSION_ID:-}"
            "CONTAINAI_HELPER_NAME=${helper_name}"
            "CONTAINAI_HELPER_UID=${helper_uid}"
            "SSL_CERT_FILE=${helper_ca}"
            "REQUESTS_CA_BUNDLE=${helper_ca}"
            "HOME=${helper_runtime}"
            "TMPDIR=${helper_runtime}"
            "LD_PRELOAD=/usr/lib/containai/libaudit_shim.so"
        )
        
        # Inherit proxy settings
        [ -n "${HTTP_PROXY:-}" ] && helper_env+=("HTTP_PROXY=${HTTP_PROXY}")
        [ -n "${HTTPS_PROXY:-}" ] && helper_env+=("HTTPS_PROXY=${HTTPS_PROXY}")
        [ -n "${http_proxy:-}" ] && helper_env+=("http_proxy=${http_proxy}")
        [ -n "${https_proxy:-}" ] && helper_env+=("https_proxy=${https_proxy}")
        [ -n "${NO_PROXY:-}" ] && helper_env+=("NO_PROXY=${NO_PROXY}")
        [ -n "${no_proxy:-}" ] && helper_env+=("no_proxy=${no_proxy}")
        
        local cmd_args=(
            --name "$helper_name"
            --listen "$helper_listen"
            --target "$helper_target"
        )
        if [ -n "$helper_bearer" ]; then
            cmd_args+=(--bearer-token "$helper_bearer")
        fi
        
        # Run the helper under its isolated UID
        env -i "${helper_env[@]}" setpriv --reuid="$helper_uid" --regid="$helper_uid" --clear-groups \
            python3 /usr/local/bin/mcp-http-helper.py "${cmd_args[@]}" >"$log_file" 2>&1 &
        local pid=$!
        MCP_HELPER_PIDS+=("$pid")
        MCP_HELPER_NAMES+=("$helper_name")
        echo "$pid" >> "/run/mcp-helpers/pids"
        
        # Health check
        if command -v curl >/dev/null 2>&1; then
            sleep 0.2  # Brief pause for helper to start
            curl --silent --max-time 2 "http://${helper_listen}/health" >/dev/null 2>&1 || \
                echo "⚠️  Helper ${helper_name} (UID ${helper_uid}) failed health check on ${helper_listen}" >&2
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
            AGENT_DATA_HOME="$data_home"
            AGENT_HOME="/home/${AGENT_USERNAME}"
            export CONTAINAI_AGENT_DATA_HOME="$AGENT_DATA_HOME"
            export CONTAINAI_AGENT_HOME="$AGENT_HOME"
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
        AGENT_DATA_HOME="$fallback_dir"
        AGENT_HOME="/home/${AGENT_USERNAME}"
        export CONTAINAI_AGENT_DATA_HOME="$AGENT_DATA_HOME"
        export CONTAINAI_AGENT_HOME="$AGENT_HOME"
    fi
}

start_agent_task_runnerd() {
    local socket_path="${AGENT_TASK_RUNNER_SOCKET:-/run/agent-task-runner.sock}"
    local log_dir="/run/agent-task-runner"
    mkdir -p "$log_dir"
    if [ -S "$socket_path" ]; then
        rm -f "$socket_path"
    fi
    
    # Start LogCollector (Mandatory)
    local audit_socket="/run/containai/audit.sock"
    # Logs are written to the workspace by default to ensure they persist to the host
    # without requiring additional volume mounts.
    local log_destination="${LOG_DIR:-/workspace/.containai/logs}"
    
    mkdir -p "$(dirname "$audit_socket")"
    mkdir -p "$log_destination"
    chown "$AGENT_UID:$AGENT_GID" "$log_destination" 2>/dev/null || true
    
    # Run log collector as agent user (even if called from root)
    # Explicitly unset LD_PRELOAD to avoid the collector auditing itself
    if [ "$(id -u)" -eq 0 ]; then
        gosu "$AGENT_USERNAME" env -u LD_PRELOAD /usr/local/bin/containai-log-collector \
            --socket-path "$audit_socket" \
            --log-dir "$log_destination" \
            > "$log_dir/collector.log" 2>&1 &
    else
        env -u LD_PRELOAD /usr/local/bin/containai-log-collector \
            --socket-path "$audit_socket" \
            --log-dir "$log_destination" \
            > "$log_dir/collector.log" 2>&1 &
    fi
        
    # Wait for socket to appear
    local retries=50
    while [ ! -S "$audit_socket" ]; do
        sleep 0.1
        retries=$((retries-1))
        if [ "$retries" -le 0 ]; then
            echo "❌ FATAL: LogCollector failed to start (socket missing)" >&2
            exit 1
        fi
    done
    
    chmod 0666 "$audit_socket"
    echo "📝 LogCollector started (logs -> $log_destination)"

    # Start Agent Task Runner (Mandatory)
    if [ "$(id -u)" -eq 0 ]; then
        gosu "$AGENT_USERNAME" env -u LD_PRELOAD /usr/local/bin/agent-task-runnerd \
            --socket "$socket_path" \
            --log "$log_dir/events.log" \
            --policy "$RUNNER_POLICY" \
            &
    else
        env -u LD_PRELOAD /usr/local/bin/agent-task-runnerd \
            --socket "$socket_path" \
            --log "$log_dir/events.log" \
            --policy "$RUNNER_POLICY" \
            &
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

    seed_tmpfs_from_base "${BASEFS_DIR}/var/lib/dpkg" "/var/lib/dpkg"
    seed_tmpfs_from_base "${BASEFS_DIR}/var/lib/apt" "/var/lib/apt"
    seed_tmpfs_from_base "${BASEFS_DIR}/var/cache/apt" "/var/cache/apt"
    seed_tmpfs_from_base "${BASEFS_DIR}/var/cache/debconf" "/var/cache/debconf"

    chmod 1777 /tmp /var/tmp 2>/dev/null || true
    chmod 0755 /run /var/log 2>/dev/null || true
}

if [ "$(id -u)" -eq 0 ]; then
    AGENT_UID=$(id -u "$AGENT_USERNAME" 2>/dev/null || echo "$AGENT_UID")
    AGENT_GID=$(id -g "$AGENT_USERNAME" 2>/dev/null || echo "$AGENT_GID")
    AGENT_CLI_UID=$(id -u "$AGENT_CLI_USERNAME" 2>/dev/null || echo "$AGENT_CLI_UID")
    AGENT_CLI_GID=$(id -g "$AGENT_CLI_USERNAME" 2>/dev/null || echo "$AGENT_CLI_GID")
    
    # Ensure proc group exists
    if ! getent group "$PROC_GROUP" >/dev/null 2>&1; then
        groupadd -r "$PROC_GROUP" || true
    fi

    prepare_rootfs_mounts
    
    prepare_agent_task_runner_paths
    prepare_agent_secrets_path
    prepare_mcp_helpers_paths
    prepare_mcp_wrappers_paths
    prepare_agent_data_export_path
    prepare_agent_data_path
    AGENT_DATA_STAGED=0
    if [ -n "${HOST_SESSION_CONFIG_ROOT:-}" ] && [ -d "${HOST_SESSION_CONFIG_ROOT:-}" ]; then
        if install_host_agent_data "$HOST_SESSION_CONFIG_ROOT"; then
            echo "📂 Agent data caches staged under /run/agent-data"
        fi
        AGENT_DATA_STAGED=1
    fi
    if [ "$AGENT_DATA_STAGED" -ne 1 ] && [ -n "${AGENT_NAME:-}" ]; then
        ensure_agent_data_fallback "$AGENT_NAME"
        AGENT_DATA_STAGED=1
    fi
    export CONTAINAI_AGENT_DATA_STAGED="$AGENT_DATA_STAGED"
    
    # Start task runner (and log collector) BEFORE MCP helpers
    # This ensures the audit socket is ready for the shim
    start_agent_task_runnerd
    RUNNER_STARTED=1
    export CONTAINAI_RUNNER_STARTED="$RUNNER_STARTED"

    export CONTAINAI_USER="$AGENT_USERNAME"
    export CONTAINAI_CLI_USER="$AGENT_CLI_USERNAME"
    export CONTAINAI_BASEFS="$BASEFS_DIR"
    export CONTAINAI_TOOLCACHE="$TOOLCACHE_DIR"
    export CONTAINAI_PTRACE_SCOPE="$PTRACE_SCOPE_VALUE"
    export CONTAINAI_CAP_TMPFS_SIZE="$CAP_TMPFS_SIZE"
    export CONTAINAI_DATA_TMPFS_SIZE="$DATA_TMPFS_SIZE"
    export CONTAINAI_SECRET_TMPFS_SIZE="$SECRETS_TMPFS_SIZE"
    export CONTAINAI_DISABLE_PTRACE_SCOPE="$DISABLE_PTRACE_SCOPE"
    export CONTAINAI_DISABLE_PROC_HARDENING="$DISABLE_PROC_HARDENING"
    export CONTAINAI_PROC_GROUP="$PROC_GROUP"
    export CONTAINAI_RUNNER_POLICY="$RUNNER_POLICY"

    # Host-provided configs and capabilities must be present before dropping caps
    HOST_CONFIG_DEPLOYED=false
    if [ -n "${HOST_SESSION_CONFIG_ROOT:-}" ] && [ -d "${HOST_SESSION_CONFIG_ROOT:-}" ]; then
        wait_for_host_payload "$HOST_SESSION_CONFIG_ROOT" 50 0.1 || true
        if [ ! -f "${HOST_MITM_CA_CERT:-${HOST_SESSION_CONFIG_ROOT}/mitm/proxy-ca.crt}" ]; then
            echo "❌ MITM CA missing in session artifacts; expected ${HOST_MITM_CA_CERT:-${HOST_SESSION_CONFIG_ROOT}/mitm/proxy-ca.crt}" >&2
            exit 1
        fi
        echo "🔐 Applying host-rendered MCP configs (session ${HOST_SESSION_ID:-unknown})"
        if install_host_session_configs "$HOST_SESSION_CONFIG_ROOT"; then
            HOST_CONFIG_DEPLOYED=true
            echo "   Manifest SHA: ${HOST_SESSION_CONFIG_SHA256:-unknown}"
        else
            echo "❌ Host session config directory missing agent payloads" >&2
            exit 1
        fi
    fi

    if [ -n "${HOST_CAPABILITY_ROOT:-}" ] && [ -d "${HOST_CAPABILITY_ROOT:-}" ]; then
        wait_for_host_payload "$HOST_CAPABILITY_ROOT" 50 0.1 || true
        echo "🔑 Installing capability tokens from host"
        if install_host_capabilities "$HOST_CAPABILITY_ROOT"; then
            echo "   Capability tokens staged"
        else
            echo "❌ Failed to install capability tokens" >&2
            exit 1
        fi
    fi

    HELPER_MANIFEST_PATH=""
    if [ -n "${HOST_SESSION_CONFIG_ROOT:-}" ] && [ -d "${HOST_SESSION_CONFIG_ROOT:-}" ]; then
        servers_file="$HOST_SESSION_CONFIG_ROOT/servers.txt"
        ensure_wrapper_binaries "$servers_file"
        helper_candidate="$HOST_SESSION_CONFIG_ROOT/helpers.json"
        if [ -f "$helper_candidate" ]; then
            HELPER_MANIFEST_PATH="$helper_candidate"
        fi
    fi

    if [ -z "$HELPER_MANIFEST_PATH" ]; then
        HELPER_MANIFEST_PATH="/home/${AGENT_USERNAME}/.config/containai/helpers.json"
    fi

    create_wrapper_links_from_configs \
        "/home/${AGENT_USERNAME}/.config/github-copilot/mcp/config.json" \
        "/home/${AGENT_USERNAME}/.config/codex/mcp/config.json" \
        "/home/${AGENT_USERNAME}/.config/claude/mcp/config.json"

    if [ -f "$HELPER_MANIFEST_PATH" ]; then
        echo "🔧 Starting MCP helper proxies from ${HELPER_MANIFEST_PATH}"
        start_mcp_helpers "$HELPER_MANIFEST_PATH"
    else
        echo "ℹ️  No MCP helper manifest found; remote helpers not started"
    fi

    export HELPER_MANIFEST_PATH
    export HOST_CONFIG_DEPLOYED


    # Switch to agent user for the rest of the initialization
    # We export necessary variables so they persist across the user switch
    export HOST_CONFIG_DEPLOYED
    export SSL_CERT_FILE
    export REQUESTS_CA_BUNDLE
    export NODE_EXTRA_CA_CERTS
    export SSL_CERT_DIR
    export CONTAINAI_AGENT_DATA_STAGED
    export CONTAINAI_RUNNER_STARTED
    export CONTAINAI_USER
    export CONTAINAI_CLI_USER
    export CONTAINAI_BASEFS
    export CONTAINAI_TOOLCACHE
    export CONTAINAI_PTRACE_SCOPE
    export CONTAINAI_CAP_TMPFS_SIZE
    export CONTAINAI_DATA_TMPFS_SIZE
    export CONTAINAI_SECRET_TMPFS_SIZE
    export CONTAINAI_DISABLE_PTRACE_SCOPE
    export CONTAINAI_DISABLE_PROC_HARDENING
    export CONTAINAI_PROC_GROUP
    export CONTAINAI_RUNNER_POLICY
    export HELPER_MANIFEST_PATH
    export AGENT_DATA_HOME
    export AGENT_HOME
    export CONTAINAI_AGENT_DATA_HOME
    export CONTAINAI_AGENT_HOME

    # Enable audit shim via LD_PRELOAD since we cannot write to /etc/ld.so.preload
    # on a read-only rootfs without SYS_ADMIN capabilities.
    export LD_PRELOAD="/usr/lib/containai/libaudit_shim.so"

    echo "🔒 Switching to $AGENT_USERNAME..."
    exec gosu "$AGENT_USERNAME" "$0" "$@"
fi

AGENT_TASK_RUNNER_SOCKET="${AGENT_TASK_RUNNER_SOCKET:-/run/agent-task-runner.sock}"
export AGENT_TASK_RUNNER_SOCKET
if [ "${RUNNER_STARTED:-0}" != "1" ]; then
    # If we are here, we are running as agentuser but the runner wasn't started by root
    # (e.g. container started with --user agentuser directly)
    start_agent_task_runnerd
fi

echo "🚀 Starting ContainAI Container..."


# Cleanup function to push changes before shutdown
cleanup_on_shutdown() {
    echo ""
    echo "📤 Container shutting down..."

    export_agent_data_payload

    if [ -f "/run/mcp-helpers/pids" ]; then
        while read -r helper_pid; do
            kill "$helper_pid" >/dev/null 2>&1 || true
        done < "/run/mcp-helpers/pids"
    fi
    rm -rf /run/mcp-helpers /run/mcp-wrappers

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
                REPO_NAME=$(basename "$(git rev-parse --show-toplevel)")
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

# Trust the workspace directory to avoid "dubious ownership" errors
# (Configured in Dockerfile via --system, but kept here as fallback if needed? No, removing.)

# Display current repository information (concise)
if [ -d .git ]; then
    branch=$(git branch --show-current 2>/dev/null || echo 'detached')
    echo "📁 $(git remote get-url origin 2>/dev/null || echo 'Local repository') [${branch}]"
else
    echo "⚠️  Not a git repository - run 'git init' if needed"
fi

# Configure git autocrlf for Windows compatibility
# (Configured in Dockerfile via --system)

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

HOST_CONFIG_DEPLOYED=${HOST_CONFIG_DEPLOYED:-false}

if [ -n "${HOST_SESSION_CONFIG_ROOT:-}" ] && [ -d "${HOST_SESSION_CONFIG_ROOT:-}" ] && [ "${AGENT_DATA_STAGED:-0}" != "1" ]; then
    if install_host_agent_data "$HOST_SESSION_CONFIG_ROOT"; then
        echo "📂 Agent data caches staged under /run/agent-data"
        AGENT_DATA_STAGED=1
        export CONTAINAI_AGENT_DATA_STAGED="$AGENT_DATA_STAGED"
    fi
fi

if [ -n "${AGENT_NAME:-}" ] && [ -z "${AGENT_DATA_HOME:-${CONTAINAI_AGENT_DATA_HOME:-}}" ]; then
    ensure_agent_data_fallback "$AGENT_NAME"
fi

if [ "$HOST_CONFIG_DEPLOYED" = false ] && [ -f "/workspace/config.toml" ]; then
    /usr/local/bin/setup-mcp-configs.sh 2>&1 | grep -E "^(ERROR|WARN)" || true
fi

# Index project with Serena for faster semantic operations (silent unless error)
if [ -d "/workspace/.git" ]; then
    timeout 30s serena project index --project /workspace >/dev/null 2>&1 || \
        echo "⚠️  Serena indexing failed or timed out"
fi

# Load MCP secrets from host mount if available
if [ -f "/home/agentuser/.mcp-secrets.env" ]; then
    set -a
    # shellcheck source=/home/agentuser/.mcp-secrets.env disable=SC1091
    source /home/agentuser/.mcp-secrets.env
    set +a
fi

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

AUTO_COMMIT_MSG="Auto-commit on shutdown"
if [ "${AUTO_COMMIT_ON_SHUTDOWN:-true}" != "true" ] && [ "${AUTO_PUSH_ON_SHUTDOWN:-true}" != "true" ]; then
    AUTO_COMMIT_MSG="Auto-commit disabled"
fi

echo "✨ Container ready | MCP: /workspace/config.toml | $AUTO_COMMIT_MSG"
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

# Ensure LD_PRELOAD is set for the final execution (in case we started as agentuser directly)
export LD_PRELOAD="/usr/lib/containai/libaudit_shim.so"

# Execute the command passed to the container
exec "$@"
