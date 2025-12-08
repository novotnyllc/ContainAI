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

runtime_root="/run/mcp-wrappers/${wrapper_name}"
core_bin="${CONTAINAI_WRAPPER_CORE:-/usr/local/libexec/mcp-wrapper-core.py}"

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
    rm -rf -- "$runtime_root"
}
trap cleanup EXIT

umask 077
mkdir -p "$runtime_root" "$runtime_root/tmp"

# Export runtime-scoped directories to keep wrapper state in tmpfs
export CONTAINAI_WRAPPER_NAME="$wrapper_name"
export CONTAINAI_WRAPPER_RUNTIME="$runtime_root"
export CONTAINAI_WRAPPER_UID="$(python3 - <<'PY'
import hashlib, os
name = os.environ.get("CONTAINAI_WRAPPER_NAME", "wrapper")
# Deterministic 16-bit uid within 20000-40000 range
uid = 20000 + (int(hashlib.sha256(name.encode()).hexdigest(), 16) % 20000)
print(uid)
PY
)"
export TMPDIR="$runtime_root/tmp"
export XDG_RUNTIME_DIR="$runtime_root"

validate_spec

if [ ! -f "$core_bin" ]; then
    echo "mcp-wrapper-runner: wrapper core missing at $core_bin" >&2
    exit 1
fi

exec python3 "$core_bin"
