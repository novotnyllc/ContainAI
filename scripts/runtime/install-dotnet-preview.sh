#!/usr/bin/env bash
# Install .NET SDK preview versions with proper privilege handling
# Usage: install-dotnet-preview.sh [channel]
# Example: install-dotnet-preview.sh 9.0

set -euo pipefail

CHANNEL="${1:-9.0}"
INSTALLER_URL="https://dot.net/v1/dotnet-install.sh"
SYSTEM_INSTALL_DIR="/usr/share/dotnet"
USER_INSTALL_DIR="${HOME}/.dotnet"

echo "📦 Installing .NET SDK ${CHANNEL} preview..."

run_installer() {
    local install_dir="$1"
    bash -s -- --channel "${CHANNEL}" --quality preview --install-dir "${install_dir}"
}

if [ "$(id -u)" -eq 0 ]; then
    curl -sSL "${INSTALLER_URL}" | run_installer "${SYSTEM_INSTALL_DIR}"
else
    if command -v sudo >/dev/null 2>&1; then
        echo "🔐 Using sudo to install into ${SYSTEM_INSTALL_DIR}"
        curl -sSL "${INSTALLER_URL}" | sudo bash -s -- --channel "${CHANNEL}" --quality preview --install-dir "${SYSTEM_INSTALL_DIR}"
    else
        echo "⚠️  sudo not available. Installing preview SDK to ${USER_INSTALL_DIR}"
        mkdir -p "${USER_INSTALL_DIR}"
        curl -sSL "${INSTALLER_URL}" | run_installer "${USER_INSTALL_DIR}"
        if ! grep -q 'DOTNET_ROOT' "${HOME}/.bashrc" 2>/dev/null; then
            {
                echo "export DOTNET_ROOT=\"${USER_INSTALL_DIR}\""
                echo "export PATH=\"${USER_INSTALL_DIR}:\$PATH\""
            } >> "${HOME}/.bashrc"
            echo "ℹ️  Added DOTNET_ROOT and PATH updates to ~/.bashrc"
        fi
        export DOTNET_ROOT="${USER_INSTALL_DIR}"
        export PATH="${USER_INSTALL_DIR}:${PATH}"
    fi
fi

echo "✅ .NET SDK ${CHANNEL} preview installed"
dotnet --list-sdks
