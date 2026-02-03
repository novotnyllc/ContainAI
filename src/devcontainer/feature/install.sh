#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════
# install.sh - ContainAI devcontainer feature install script
#
# Runs at container BUILD time. Responsibilities:
# - Check platform (Debian/Ubuntu only in V1)
# - Install dependencies (jq, openssh-server, docker)
# - Store configuration for runtime scripts
# - Copy bundled scripts to /usr/local/share/containai/
# - Copy link-spec.json to /usr/local/lib/containai/
# ══════════════════════════════════════════════════════════════════════
set -euo pipefail

# Feature options (passed as uppercase env vars by devcontainer)
DATA_VOLUME="${DATAVOLUME:-containai-data}"
ENABLE_CREDENTIALS="${ENABLECREDENTIALS:-false}"
ENABLE_SSH="${ENABLESSH:-true}"
INSTALL_DOCKER="${INSTALLDOCKER:-true}"
REMOTE_USER="${REMOTEUSER:-auto}"

# ══════════════════════════════════════════════════════════════════════
# INPUT VALIDATION (SECURITY: Prevent command injection)
# Feature options come from devcontainer.json which may be attacker-controlled
# ══════════════════════════════════════════════════════════════════════
validate_input() {
    # DATA_VOLUME must be a valid Docker volume name: alphanumeric, dots, underscores, hyphens
    # Must start with alphanumeric
    if ! [[ "$DATA_VOLUME" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
        printf 'ERROR: Invalid dataVolume "%s". Must be alphanumeric with ._- allowed.\n' "$DATA_VOLUME" >&2
        exit 1
    fi

    # ENABLE_CREDENTIALS must be true or false
    if [[ "$ENABLE_CREDENTIALS" != "true" && "$ENABLE_CREDENTIALS" != "false" ]]; then
        printf 'ERROR: Invalid enableCredentials "%s". Must be true or false.\n' "$ENABLE_CREDENTIALS" >&2
        exit 1
    fi

    # ENABLE_SSH must be true or false
    if [[ "$ENABLE_SSH" != "true" && "$ENABLE_SSH" != "false" ]]; then
        printf 'ERROR: Invalid enableSsh "%s". Must be true or false.\n' "$ENABLE_SSH" >&2
        exit 1
    fi

    # INSTALL_DOCKER must be true or false
    if [[ "$INSTALL_DOCKER" != "true" && "$INSTALL_DOCKER" != "false" ]]; then
        printf 'ERROR: Invalid installDocker "%s". Must be true or false.\n' "$INSTALL_DOCKER" >&2
        exit 1
    fi

    # REMOTE_USER must be 'auto' or a valid Unix username
    # Valid: starts with lowercase letter or underscore, followed by lowercase letters, digits, underscores, or hyphens
    if [[ "$REMOTE_USER" != "auto" ]] && ! [[ "$REMOTE_USER" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
        printf 'ERROR: Invalid remoteUser "%s". Must be "auto" or a valid Unix username.\n' "$REMOTE_USER" >&2
        exit 1
    fi
}

validate_input

# ══════════════════════════════════════════════════════════════════════
# PLATFORM CHECK (Debian/Ubuntu only in V1)
# ══════════════════════════════════════════════════════════════════════
if ! command -v apt-get &>/dev/null; then
    cat >&2 <<'ERROR'
╔═══════════════════════════════════════════════════════════════════╗
║  ContainAI feature requires Debian/Ubuntu base image              ║
║  Alpine, Fedora, and other distros not yet supported              ║
╚═══════════════════════════════════════════════════════════════════╝
ERROR
    exit 1
fi

printf 'ContainAI: Installing feature...\n'

# ══════════════════════════════════════════════════════════════════════
# CREATE DIRECTORIES
# ══════════════════════════════════════════════════════════════════════
mkdir -p /usr/local/share/containai
mkdir -p /usr/local/lib/containai

# ══════════════════════════════════════════════════════════════════════
# STORE CONFIGURATION AS JSON (SECURITY: avoid sourcing untrusted data)
# Runtime scripts parse this with jq instead of sourcing
# ══════════════════════════════════════════════════════════════════════
cat > /usr/local/share/containai/config.json << EOF
{
    "data_volume": "$DATA_VOLUME",
    "enable_credentials": $( [[ "$ENABLE_CREDENTIALS" == "true" ]] && echo "true" || echo "false" ),
    "enable_ssh": $( [[ "$ENABLE_SSH" == "true" ]] && echo "true" || echo "false" ),
    "install_docker": $( [[ "$INSTALL_DOCKER" == "true" ]] && echo "true" || echo "false" ),
    "remote_user": "$REMOTE_USER"
}
EOF

printf '  Configuration saved\n'

# ══════════════════════════════════════════════════════════════════════
# COPY BUNDLED SCRIPTS
# These are included in the feature bundle (same directory as install.sh)
# ══════════════════════════════════════════════════════════════════════
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Copy runtime scripts
for script in verify-sysbox.sh init.sh start.sh; do
    if [[ -f "$SCRIPT_DIR/$script" ]]; then
        cp "$SCRIPT_DIR/$script" "/usr/local/share/containai/$script"
        chmod +x "/usr/local/share/containai/$script"
        printf '  Installed: %s\n' "$script"
    else
        printf '  Warning: %s not found in feature bundle\n' "$script" >&2
    fi
done

# ══════════════════════════════════════════════════════════════════════
# COPY LINK-SPEC.JSON
# Symlink configuration from canonical source (no duplicate lists)
# ══════════════════════════════════════════════════════════════════════
if [[ -f "$SCRIPT_DIR/link-spec.json" ]]; then
    cp "$SCRIPT_DIR/link-spec.json" /usr/local/lib/containai/link-spec.json
    printf '  Installed: link-spec.json\n'
else
    printf '  Note: link-spec.json not bundled - symlinks will be skipped\n'
fi

# ══════════════════════════════════════════════════════════════════════
# INSTALL DEPENDENCIES
# ══════════════════════════════════════════════════════════════════════
printf '  Installing dependencies...\n'

# Update package lists (quiet mode)
apt-get update -qq

# jq is required for JSON parsing in init.sh
apt-get install -y -qq jq
printf '    Installed: jq\n'

# ──────────────────────────────────────────────────────────────────────
# SSH server (if enabled)
# ──────────────────────────────────────────────────────────────────────
if [[ "$ENABLE_SSH" == "true" ]]; then
    apt-get install -y -qq openssh-server
    mkdir -p /var/run/sshd
    printf '    Installed: openssh-server\n'
fi

# ──────────────────────────────────────────────────────────────────────
# Docker for DinD (sysbox provides isolation, no --privileged needed)
# Note: dockerd startup happens in postStartCommand, not here
# ──────────────────────────────────────────────────────────────────────
if [[ "$INSTALL_DOCKER" == "true" ]]; then
    # Install curl and ca-certificates first (may be missing on slim images)
    apt-get install -y -qq curl ca-certificates
    printf '    Installed: curl, ca-certificates\n'

    # Install Docker using official script
    curl -fsSL https://get.docker.com | sh

    # Add devcontainer user to docker group
    # Common devcontainer users: vscode, node
    if id -u vscode &>/dev/null; then
        usermod -aG docker vscode
        printf '    Added vscode to docker group\n'
    fi
    if id -u node &>/dev/null; then
        usermod -aG docker node
        printf '    Added node to docker group\n'
    fi

    printf '    Installed: docker (DinD starts via postStartCommand)\n'
fi

# ══════════════════════════════════════════════════════════════════════
# CLEANUP
# ══════════════════════════════════════════════════════════════════════
apt-get clean
rm -rf /var/lib/apt/lists/*

printf 'ContainAI feature installed successfully\n'
printf '  Data volume: %s\n' "$DATA_VOLUME"
printf '  Credentials: %s\n' "$ENABLE_CREDENTIALS"
printf '  SSH: %s\n' "$ENABLE_SSH"
printf '  Docker: %s\n' "$INSTALL_DOCKER"
