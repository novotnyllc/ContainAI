#!/usr/bin/env bash
set -euo pipefail

STUB_NAME="agent_codex_cli"
SECRET_NAME="codex_cli_auth_json"
AGENT_HOME="${CODING_AGENTS_AGENT_HOME:-/home/agentuser}"
AGENT_DATA_HOME="${CODING_AGENTS_AGENT_DATA_HOME:-$AGENT_HOME}"
AGENT_SECRET_ROOT="${CODING_AGENTS_AGENT_SECRET_ROOT:-/run/agent-secrets}"
DEFAULT_CAP_ROOT="${CODING_AGENTS_CAP_ROOT_OVERRIDE:-${AGENT_HOME}/.config/coding-agents/capabilities}"
AGENT_CLI_CAP_ROOT="${CODING_AGENTS_AGENT_CAP_ROOT:-/run/coding-agents/codex/cli/capabilities}"
DEST_DIR="${AGENT_SECRET_ROOT}/codex"
DEST_FILE="${DEST_DIR}/auth.json"
CLI_DIR="${AGENT_HOME}/.codex"
DATA_DIR="${AGENT_DATA_HOME}/.codex"
UNSEAL_BIN="${CODING_AGENTS_CAPABILITY_UNSEAL:-/usr/local/bin/capability-unseal}"

link_cli_dir() {
    local target="$1"
    local link_path="$2"
    mkdir -p "$(dirname "$link_path")"
    if [ -L "$link_path" ] || [ -f "$link_path" ]; then
        rm -f "$link_path"
    elif [ -d "$link_path" ]; then
        rm -rf "$link_path"
    fi
    ln -sfn "$target" "$link_path"
}

resolve_cap_root() {
    if [ -d "${AGENT_CLI_CAP_ROOT}/${STUB_NAME}" ]; then
        printf '%s' "$AGENT_CLI_CAP_ROOT"
        return 0
    fi
    printf '%s' "$DEFAULT_CAP_ROOT"
}

main() {
    local cap_root
    cap_root=$(resolve_cap_root)

    if [ ! -x "$UNSEAL_BIN" ]; then
        echo "capability-unseal utility missing at $UNSEAL_BIN" >&2
        return 1
    fi
    if [ ! -d "$cap_root/$STUB_NAME" ]; then
        echo "Codex capability bundle missing at $cap_root/$STUB_NAME" >&2
        return 1
    fi

    mkdir -p "$DEST_DIR"
    chmod 700 "$DEST_DIR"

    local tmp_file
    tmp_file=$(mktemp)
    trap 'rm -f "$tmp_file"' EXIT

    if ! "$UNSEAL_BIN" --stub "$STUB_NAME" --secret "$SECRET_NAME" --cap-root "$cap_root" --format raw >"$tmp_file"; then
        echo "Failed to decrypt Codex credential bundle" >&2
        return 1
    fi

    cp "$tmp_file" "$DEST_FILE"
    chmod 600 "$DEST_FILE"
    mkdir -p "$DATA_DIR"
    ln -sfn "$DEST_FILE" "$DATA_DIR/auth.json"
    link_cli_dir "$DATA_DIR" "$CLI_DIR"
    echo "Codex secrets prepared from capability bundle"
}

main "$@"
