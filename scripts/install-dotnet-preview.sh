#!/bin/bash
# Install .NET SDK preview versions
# Usage: install-dotnet-preview.sh [channel]
# Example: install-dotnet-preview.sh 9.0

set -e

CHANNEL="${1:-9.0}"

echo "📦 Installing .NET SDK ${CHANNEL} preview..."

curl -sSL https://dot.net/v1/dotnet-install.sh | bash -s -- \
    --channel "${CHANNEL}" \
    --quality preview \
    --install-dir /usr/share/dotnet

echo "✅ .NET SDK ${CHANNEL} preview installed"
dotnet --list-sdks
