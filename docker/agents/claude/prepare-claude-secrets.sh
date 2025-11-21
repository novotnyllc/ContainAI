#!/usr/bin/env bash
set -euo pipefail

STUB_NAME="agent_claude_cli"
SECRET_NAME="claude_cli_credentials"
AGENT_HOME="${CONTAINAI_AGENT_HOME:-/home/agentuser}"
AGENT_SECRET_ROOT="${CONTAINAI_AGENT_SECRET_ROOT:-/run/agent-secrets}"
DEFAULT_CAP_ROOT="${CONTAINAI_CAP_ROOT_OVERRIDE:-${AGENT_HOME}/.config/containai/capabilities}"
AGENT_CLI_CAP_ROOT="${CONTAINAI_AGENT_CAP_ROOT:-/run/containai/claude/cli/capabilities}"
DEST_DIR="${AGENT_SECRET_ROOT}/claude"
DEST_FILE="${DEST_DIR}/.credentials.json"
CLI_DIR="${AGENT_HOME}/.claude"
GLOBAL_CFG_SOURCE="${AGENT_HOME}/.config/containai/claude/.claude.json"
GLOBAL_CFG_DEST="${AGENT_HOME}/.claude.json"
UNSEAL_BIN="${CONTAINAI_CAPABILITY_UNSEAL:-/usr/local/bin/capability-unseal}"

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

write_credentials() {
    local input_file="$1"
    local output_file="$2"
    python3 - "$input_file" "$output_file" <<'PY'
import json
import pathlib
import sys

if len(sys.argv) < 3:
    raise SystemExit("usage: script input output")
source = pathlib.Path(sys.argv[1])
destination = pathlib.Path(sys.argv[2])
raw = source.read_text(encoding="utf-8")
stripped = raw.strip()
if not stripped:
    raise SystemExit("Claude credential payload empty")
try:
    parsed = json.loads(stripped)
    if not isinstance(parsed, dict):
        raise ValueError("credential payload must be an object")
    destination.write_text(json.dumps(parsed, indent=2) + "\n", encoding="utf-8")
except Exception:
    doc = {"api_key": stripped}
    destination.write_text(json.dumps(doc, indent=2) + "\n", encoding="utf-8")
PY
}

main() {
    local cap_root
    cap_root=$(resolve_cap_root)

    if [ ! -x "$UNSEAL_BIN" ]; then
        echo "capability-unseal utility missing at $UNSEAL_BIN" >&2
        return 1
    fi
    if [ ! -d "$cap_root/$STUB_NAME" ]; then
        echo "Claude capability bundle missing at $cap_root/$STUB_NAME" >&2
        return 1
    fi

    mkdir -p "$DEST_DIR"
    chmod 700 "$DEST_DIR"

    if [ -f "$GLOBAL_CFG_SOURCE" ] && [ ! -f "$GLOBAL_CFG_DEST" ]; then
        cp "$GLOBAL_CFG_SOURCE" "$GLOBAL_CFG_DEST"
    fi

    local tmp_file
    tmp_file=$(mktemp)
    trap 'rm -f "${tmp_file:-}"' EXIT

    if ! "$UNSEAL_BIN" --stub "$STUB_NAME" --secret "$SECRET_NAME" --cap-root "$cap_root" --format raw >"$tmp_file"; then
        echo "Failed to decrypt Claude credential bundle" >&2
        return 1
    fi

    if ! write_credentials "$tmp_file" "$DEST_FILE"; then
        echo "Failed to materialize Claude credentials" >&2
        return 1
    fi
    chmod 600 "$DEST_FILE"
    link_cli_dir "$DEST_DIR" "$CLI_DIR"
    echo "Claude secrets prepared from capability bundle"
}

main "$@"
