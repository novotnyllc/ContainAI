#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -eq 0 ]; then
    echo "Usage: $0 binary:agent [binary:agent ...]" >&2
    exit 1
fi

install_wrapper() {
    local pair="$1"
    local binary="${pair%%:*}"
    local agent="${pair#*:}"
    if [ -z "$binary" ] || [ -z "$agent" ]; then
        echo "Skipping invalid pair '$pair'" >&2
        return
    fi
    local binary_path
    binary_path=$(command -v "$binary" 2>/dev/null || true)
    if [ -z "$binary_path" ]; then
        echo "Wrapper install skipped for '$binary' (binary not found)" >&2
        return
    fi

    local real_path="${binary_path}.real"
    if [ ! -x "$real_path" ]; then
        mv "$binary_path" "$real_path"
    fi

    local wrapper="${binary_path}"
    cat >"$wrapper" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
REAL_BIN="__REAL_BIN__"
AGENT_NAME="__AGENT_NAME__"
AGENT_BINARY="__AGENT_BINARY__"
DEFAULT_SOCKET="/run/agent-task-runner.sock"
AGENT_TASK_RUNNER_SOCKET="${AGENT_TASK_RUNNER_SOCKET:-$DEFAULT_SOCKET}"
export AGENT_TASK_RUNNER_SOCKET
export CODING_AGENTS_AGENT_NAME="$AGENT_NAME"
export CODING_AGENTS_AGENT_BINARY="$AGENT_BINARY"
export CODING_AGENTS_AGENTCLI_WRAPPER=1
export CODING_AGENTS_AGENTCLI_SECRETS="/run/agent-secrets/__AGENT_NAME__"
export CODING_AGENTS_AGENTCLI_DATA="/run/agent-data/__AGENT_NAME__"
RUNNERCTL="/usr/local/bin/agent-task-runnerctl"

if [ "$#" -gt 0 ]; then
    subcmd="$1"
    case "$subcmd" in
        exec|run|shell)
            shift
            if [ "${1:-}" = "--" ]; then
                shift
            fi
            if [ "$#" -eq 0 ]; then
                set -- /bin/sh
            fi
            exec "$RUNNERCTL" --agent "$AGENT_NAME" --binary "$AGENT_BINARY" -- "$@"
            ;;
    esac
fi
exec /usr/local/bin/agentcli-exec "$REAL_BIN" "$@"
SCRIPT

    local escaped_real_path="${real_path//\//\\/}"
    local escaped_agent="${agent//\//\\/}"
    local escaped_binary="${binary//\//\\/}"
    sed -i \
        -e "s/__REAL_BIN__/${escaped_real_path}/g" \
        -e "s/__AGENT_NAME__/${escaped_agent}/g" \
        -e "s/__AGENT_BINARY__/${escaped_binary}/g" \
        "$wrapper"
    chmod 0755 "$wrapper"
}

for pair in "$@"; do
    install_wrapper "$pair"
done
