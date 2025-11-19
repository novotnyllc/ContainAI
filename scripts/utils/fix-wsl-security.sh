#!/usr/bin/env bash
set -euo pipefail

print_usage() {
    cat <<'EOF'
Usage: fix-wsl-security.sh [--check] [--force]

Ensures your Windows host is configured so WSL 2 exposes AppArmor.

Options:
  --check   Only report missing settings without applying changes.
  --force   Skip interactive prompts when applying changes.
  -h,--help Show this help message.
EOF
}

if ! grep -qi "microsoft" /proc/version 2>/dev/null; then
    echo "❌ This helper must be executed from inside a WSL 2 shell." >&2
    exit 1
fi

mode="apply"
declare -a ps_args=()

while [ $# -gt 0 ]; do
    case "$1" in
        --check)
            mode="check"
            shift
            ;;
        --force)
            ps_args+=("-Force")
            shift
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            print_usage >&2
            exit 1
            ;;
    esac
done

POWERSHELL_EXE=$(command -v powershell.exe 2>/dev/null || true)
if [ -z "$POWERSHELL_EXE" ]; then
    if [ -x /mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe ]; then
        POWERSHELL_EXE="/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"
    else
        echo "❌ Unable to locate powershell.exe on the Windows host." >&2
        exit 1
    fi
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PS_SCRIPT_WIN=$(wslpath -w "$SCRIPT_DIR/enable-wsl-security.ps1")

declare -a command=("$POWERSHELL_EXE" -NoProfile -ExecutionPolicy Bypass -File "$PS_SCRIPT_WIN")
if [ "$mode" = "check" ]; then
    command+=("-CheckOnly")
fi
if [ ${#ps_args[@]} -gt 0 ]; then
    command+=("${ps_args[@]}")
fi

if [ "$mode" = "check" ]; then
    echo "🔍 Checking WSL security configuration..."
else
    echo "🚀 Launching Windows configuration helper (this may restart WSL)..."
fi

"${command[@]}"