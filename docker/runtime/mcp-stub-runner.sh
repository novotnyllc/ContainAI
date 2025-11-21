#!/usr/bin/env bash
# Dedicated per-stub entrypoint that isolates runtime state and invokes the core MCP stub.
set -euo pipefail

script_name="$(basename "$0")"
stub_name="${CONTAINAI_STUB_NAME:-$script_name}"
stub_name="${stub_name#mcp-stub-}"
stub_name="${stub_name:-default}"

runtime_root="/run/mcp-stubs/${stub_name}"
core_bin="${CONTAINAI_STUB_CORE:-/usr/local/libexec/mcp-stub-core.py}"

decode_stub_from_spec() {
    if [ -z "${CONTAINAI_STUB_SPEC:-}" ]; then
        return 0
    fi
    python3 - "$stub_name" <<'PY'
import base64, json, os, sys
spec_raw = os.environ.get("CONTAINAI_STUB_SPEC")
expected = sys.argv[1]
try:
    decoded = base64.b64decode(spec_raw)
    spec = json.loads(decoded)
    stub = spec.get("stub", "")
    if stub and stub != expected:
        print(f"mcp-stub-runner: spec stub '{stub}' mismatches runner '{expected}'", file=sys.stderr)
        sys.exit(1)
except Exception:
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

# Export runtime-scoped directories to keep stub state in tmpfs
export CONTAINAI_STUB_NAME="$stub_name"
export CONTAINAI_STUB_RUNTIME="$runtime_root"
export CONTAINAI_STUB_UID="$(python3 - <<'PY'
import hashlib, os
name = os.environ.get("CONTAINAI_STUB_NAME", "stub")
# Deterministic 16-bit uid within 20000-40000 range
uid = 20000 + (int(hashlib.sha256(name.encode()).hexdigest(), 16) % 20000)
print(uid)
PY
)"
export TMPDIR="$runtime_root/tmp"
export XDG_RUNTIME_DIR="$runtime_root"

decode_stub_from_spec

if [ ! -x "$core_bin" ]; then
    echo "mcp-stub-runner: core stub missing at $core_bin" >&2
    exit 1
fi

exec python3 "$core_bin"
