#!/usr/bin/env bash
# MCP Wrapper Runner - Isolates runtime state and invokes the wrapper core.
#
# This script is symlinked as mcp-wrapper-<name> for each local MCP server.
# It sets up an isolated runtime environment and then calls the Python wrapper
# which handles secret decryption and command execution.
set -euo pipefail

script_name="$(basename "$0")"
wrapper_name="${CONTAINAI_WRAPPER_NAME:-$script_name}"
# Strip mcp-wrapper- prefix if invoked via symlink
wrapper_name="${wrapper_name#mcp-wrapper-}"
wrapper_name="${wrapper_name:-default}"

# Sanitize wrapper_name to prevent directory traversal
if [[ ! "$wrapper_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo "mcp-wrapper-runner: invalid wrapper name '$wrapper_name'" >&2
    exit 1
fi

runtime_root="/run/mcp-wrappers/${wrapper_name}"
core_bin="${CONTAINAI_WRAPPER_CORE:-/usr/local/libexec/mcp-wrapper-core.py}"
cap_root_default="/home/agentuser/.config/containai/capabilities/${wrapper_name}"

validate_spec() {
    # Validate the spec file exists and matches this wrapper
    local spec_file="${CONTAINAI_WRAPPER_SPEC:-}"
    if [ -z "$spec_file" ]; then
        return 0
    fi
    if [ ! -f "$spec_file" ]; then
        echo "mcp-wrapper-runner: spec file not found: $spec_file" >&2
        exit 1
    fi
    python3 - "$wrapper_name" "$spec_file" <<'PY'
import json, sys
expected = sys.argv[1]
spec_path = sys.argv[2]
try:
    with open(spec_path, "r") as f:
        spec = json.load(f)
    name = spec.get("name", "")
    if name and name != expected:
        print(f"mcp-wrapper-runner: spec name '{name}' mismatches runner '{expected}'", file=sys.stderr)
        sys.exit(1)
except Exception as e:
    # Best-effort validation; fall through to core which will perform its own checks
    pass
PY
}

cleanup() {
    # Cleanup runtime directory (owned by agentuser, so we can delete it)
    if [[ "$runtime_root" == /run/mcp-wrappers/* ]]; then
        rm -rf -- "$runtime_root"
    fi
}
trap cleanup EXIT

umask 077

# Calculate deterministic UID for this wrapper (range 20000-40000)
# wrapper_uid=$(python3 -c "import hashlib; print(20000 + (int(hashlib.sha256('${wrapper_name}'.encode()).hexdigest(), 16) % 20000))")

# Export runtime-scoped directories to keep wrapper state in tmpfs
export CONTAINAI_WRAPPER_NAME="$wrapper_name"
export CONTAINAI_WRAPPER_RUNTIME="$runtime_root"
export TMPDIR="$runtime_root/tmp"
export XDG_RUNTIME_DIR="$runtime_root"

validate_spec

if [ ! -f "$core_bin" ]; then
    echo "mcp-wrapper-runner: wrapper core missing at $core_bin" >&2
    exit 1
fi

# Copy capability bundle into runtime so the wrapper can read it
cap_src="${CONTAINAI_CAP_ROOT:-$cap_root_default}"

# Setup runtime directory with group permissions for agentcli
# We use 'agentcli' user for all MCP servers to avoid sudo.
# 'agentuser' is in 'agentcli' group, so we use group permissions to pass data.
target_group="agentcli"

mkdir -p "$runtime_root" "$runtime_root/tmp"
chgrp "$target_group" "$runtime_root" "$runtime_root/tmp"
chmod 770 "$runtime_root" "$runtime_root/tmp"

if [ -d "$cap_src" ]; then
    cap_dst="$runtime_root/capabilities"
    rm -rf "$cap_dst"
    cp -a "$cap_src" "$cap_dst"
    chgrp -R "$target_group" "$cap_dst"
    chmod -R g+rX "$cap_dst"
fi

# Execute wrapper core via agentcli-exec
# This binary is setuid root and switches to the agentcli user
export CONTAINAI_CLI_USER="agentcli"
exec /usr/local/bin/agentcli-exec "$core_bin" "$@"
