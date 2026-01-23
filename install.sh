#!/usr/bin/env bash
# ==============================================================================
# ContainAI Installer
# ==============================================================================
# One-liner installation:
#   curl -fsSL https://raw.githubusercontent.com/novotnyllc/containai/main/install.sh | bash
#
# This script:
#   1. Detects OS (macOS, Linux)
#   2. Checks prerequisites (Docker, git)
#   3. Clones/updates the repo to ~/.local/share/containai
#   4. Creates wrapper script in ~/.local/bin/cai
#   5. Adds bin directory to PATH if needed
#
# Note: The installer runs on bash 3.2+, but the cai CLI requires bash 4.0+.
# On macOS, install bash 4+ with: brew install bash
#
# Environment variables:
#   CAI_INSTALL_DIR  - Installation directory (default: ~/.local/share/containai)
#   CAI_BIN_DIR      - Binary directory (default: ~/.local/bin)
#   CAI_BRANCH       - Git branch to install (default: main)
#
# ==============================================================================
set -euo pipefail

# Colors for output (disabled if not a terminal)
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    NC=''
fi

# Logging functions
info() { printf '%b[INFO]%b %s\n' "$BLUE" "$NC" "$1"; }
success() { printf '%b[OK]%b %s\n' "$GREEN" "$NC" "$1"; }
warn() { printf '%b[WARN]%b %s\n' "$YELLOW" "$NC" "$1" >&2; }
error() { printf '%b[ERROR]%b %s\n' "$RED" "$NC" "$1" >&2; }

# Configuration with defaults
REPO_URL="https://github.com/novotnyllc/containai.git"
INSTALL_DIR="${CAI_INSTALL_DIR:-$HOME/.local/share/containai}"
BIN_DIR="${CAI_BIN_DIR:-$HOME/.local/bin}"
BRANCH="${CAI_BRANCH:-main}"

# ==============================================================================
# OS Detection
# ==============================================================================
detect_os() {
    local os
    os="$(uname -s)"
    case "$os" in
        Darwin)
            echo "macos"
            ;;
        Linux)
            # Detect specific Linux distro
            if [[ -f /etc/os-release ]]; then
                # shellcheck disable=SC1091
                . /etc/os-release
                case "${ID:-}" in
                    ubuntu | debian)
                        echo "debian"
                        ;;
                    fedora | rhel | centos | rocky | almalinux)
                        echo "fedora"
                        ;;
                    arch | manjaro)
                        echo "arch"
                        ;;
                    *)
                        echo "linux"
                        ;;
                esac
            else
                echo "linux"
            fi
            ;;
        *)
            error "Unsupported operating system: $os"
            exit 1
            ;;
    esac
}

# ==============================================================================
# Prerequisite Checks
# ==============================================================================
check_bash_version() {
    # Check for bash 4.0+ (required by cai CLI, not installer)
    local major_version
    major_version="${BASH_VERSION%%.*}"

    if [[ "$major_version" -lt 4 ]]; then
        warn "bash version $BASH_VERSION detected"
        warn "The cai CLI requires bash 4.0+ (installer works on bash 3.2+)"
        local os
        os="$(detect_os)"
        if [[ "$os" == "macos" ]]; then
            warn "macOS ships with bash 3.2. After installation, install bash 4+ with:"
            warn "  brew install bash"
            warn "Then run cai with: /opt/homebrew/bin/bash cai (Apple Silicon)"
            warn "                or: /usr/local/bin/bash cai (Intel)"
        else
            warn "Please install bash 4.0 or later to use the cai CLI"
        fi
        # Return success - installer can proceed, CLI will check at runtime
        return 0
    fi
    return 0
}

check_docker() {
    if ! command -v docker >/dev/null 2>&1; then
        local os
        os="$(detect_os)"
        error "Docker is not installed"
        case "$os" in
            macos)
                error "Install Docker Desktop: https://www.docker.com/products/docker-desktop/"
                ;;
            debian)
                error "Install Docker: sudo apt-get update && sudo apt-get install -y docker.io"
                error "Or Docker Desktop: https://docs.docker.com/desktop/install/linux-install/"
                ;;
            fedora)
                error "Install Docker: sudo dnf install -y docker"
                error "Or Docker Desktop: https://docs.docker.com/desktop/install/linux-install/"
                ;;
            *)
                error "Install Docker: https://docs.docker.com/engine/install/"
                ;;
        esac
        return 1
    fi

    # Check if Docker is running
    if ! docker info >/dev/null 2>&1; then
        warn "Docker is installed but not running"
        warn "Please start Docker and run this script again"
        warn "Continuing with installation anyway..."
    fi

    return 0
}

check_git() {
    if ! command -v git >/dev/null 2>&1; then
        local os
        os="$(detect_os)"
        error "git is not installed"
        case "$os" in
            macos)
                error "Install git: xcode-select --install"
                error "Or: brew install git"
                ;;
            debian)
                error "Install git: sudo apt-get update && sudo apt-get install -y git"
                ;;
            fedora)
                error "Install git: sudo dnf install -y git"
                ;;
            *)
                error "Install git from: https://git-scm.com/downloads"
                ;;
        esac
        return 1
    fi
    return 0
}

check_prerequisites() {
    info "Checking prerequisites..."
    local failed=0
    local major_version
    major_version="${BASH_VERSION%%.*}"

    # bash check (warn only, don't fail)
    check_bash_version
    if [[ "$major_version" -lt 4 ]]; then
        warn "bash ${BASH_VERSION} (4.0+ needed for cai CLI)"
    else
        success "bash ${BASH_VERSION}"
    fi

    if ! check_git; then
        failed=1
    else
        success "git $(git --version | cut -d' ' -f3)"
    fi

    if ! check_docker; then
        failed=1
    else
        local docker_version
        docker_version=$(docker --version 2>/dev/null | cut -d' ' -f3 | tr -d ',')
        success "Docker $docker_version"
    fi

    if [[ "$failed" -eq 1 ]]; then
        error "Prerequisites check failed. Please install missing dependencies."
        exit 1
    fi

    success "All prerequisites satisfied"
}

# ==============================================================================
# Installation
# ==============================================================================
install_containai() {
    info "Installing ContainAI to $INSTALL_DIR..."

    # Create parent directory
    mkdir -p "$(dirname "$INSTALL_DIR")"

    if [[ -d "$INSTALL_DIR/.git" ]]; then
        # Existing installation - update
        info "Existing installation found, updating..."
        (
            cd -- "$INSTALL_DIR"
            git fetch origin "$BRANCH"
            git checkout "$BRANCH"
            git reset --hard "origin/$BRANCH"
        )
        success "Updated to latest version"
    else
        # Fresh installation
        if [[ -d "$INSTALL_DIR" ]]; then
            warn "Directory exists but is not a git repository: $INSTALL_DIR"
            warn "Removing and re-cloning..."
            rm -rf "$INSTALL_DIR"
        fi
        git clone --branch "$BRANCH" --depth 1 "$REPO_URL" "$INSTALL_DIR"
        success "Cloned ContainAI repository"
    fi

    # Show installed version
    if [[ -f "$INSTALL_DIR/VERSION" ]]; then
        local version
        version=$(tr -d '[:space:]' <"$INSTALL_DIR/VERSION")
        info "Installed version: $version"
    fi
}

setup_path() {
    info "Setting up PATH integration..."

    # Create bin directory
    mkdir -p "$BIN_DIR"

    # Create wrapper script (bake in INSTALL_DIR so it works without env var)
    local wrapper="$BIN_DIR/cai"
    # Note: Using unquoted heredoc so $INSTALL_DIR expands at install time
    cat >"$wrapper" <<WRAPPER_EOF
#!/usr/bin/env bash
# ContainAI CLI wrapper
# This wrapper sources containai.sh and runs the cai function
# Generated by install.sh - install directory baked in at install time

# Require bash
if [ -z "\${BASH_VERSION:-}" ]; then
    echo "[ERROR] cai requires bash" >&2
    exit 1
fi

# Check bash version
major_version="\${BASH_VERSION%%.*}"
if [[ "\$major_version" -lt 4 ]]; then
    echo "[ERROR] cai requires bash 4.0 or later (found \$BASH_VERSION)" >&2
    if [[ "\$(uname -s)" == "Darwin" ]]; then
        echo "  Install with: brew install bash" >&2
        echo "  Then run: /opt/homebrew/bin/bash \\\$(which cai) (Apple Silicon)" >&2
        echo "         or: /usr/local/bin/bash \\\$(which cai) (Intel)" >&2
    fi
    exit 1
fi

# Install directory (baked in at install time, can override with env var)
CAI_INSTALL_DIR="\${CAI_INSTALL_DIR:-$INSTALL_DIR}"

# Source the main script
if [[ ! -f "\$CAI_INSTALL_DIR/src/containai.sh" ]]; then
    echo "[ERROR] ContainAI not found at \$CAI_INSTALL_DIR" >&2
    echo "  Re-run the installer or set CAI_INSTALL_DIR" >&2
    exit 1
fi

# Source in a subshell-like manner to get the functions
source "\$CAI_INSTALL_DIR/src/containai.sh"

# Run cai with all arguments
cai "\$@"
WRAPPER_EOF

    chmod +x "$wrapper"
    success "Created cai wrapper at $wrapper"

    # Check if BIN_DIR is in PATH
    if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
        warn "$BIN_DIR is not in your PATH"

        # Detect shell and suggest adding to PATH
        local shell_name
        shell_name="$(basename "${SHELL:-/bin/bash}")"
        local rc_file

        case "$shell_name" in
            bash)
                if [[ -f "$HOME/.bash_profile" ]]; then
                    rc_file="$HOME/.bash_profile"
                else
                    rc_file="$HOME/.bashrc"
                fi
                ;;
            zsh)
                rc_file="$HOME/.zshrc"
                ;;
            fish)
                rc_file="$HOME/.config/fish/config.fish"
                ;;
            *)
                rc_file="$HOME/.profile"
                ;;
        esac

        # Ensure parent directory exists (especially for fish config)
        mkdir -p "$(dirname "$rc_file")"

        # Build PATH line using actual BIN_DIR (escape for shell literal)
        local path_line
        if [[ "$shell_name" == "fish" ]]; then
            path_line="set -gx PATH $BIN_DIR \$PATH"
        else
            path_line="export PATH=\"$BIN_DIR:\$PATH\""
        fi

        if [[ -f "$rc_file" ]]; then
            # Check if already present (match full BIN_DIR path to avoid false positives)
            if ! grep -qF -- "$BIN_DIR" "$rc_file" 2>/dev/null; then
                {
                    echo ""
                    echo "# Added by ContainAI installer"
                    echo "$path_line"
                } >>"$rc_file"
                success "Added $BIN_DIR to PATH in $rc_file"
                warn "Run 'source $rc_file' or start a new terminal to use cai"
            else
                info "$rc_file already contains PATH entry for $BIN_DIR"
            fi
        else
            # Create the rc file
            {
                echo "# Added by ContainAI installer"
                echo "$path_line"
            } >"$rc_file"
            success "Created $rc_file with PATH entry"
            warn "Run 'source $rc_file' or start a new terminal to use cai"
        fi

        # Store rc_file for post_install message
        _CAI_RC_FILE="$rc_file"
    else
        success "$BIN_DIR is already in PATH"
        _CAI_RC_FILE=""
    fi
}

# ==============================================================================
# Post-installation
# ==============================================================================
post_install() {
    echo ""
    success "ContainAI installed successfully!"
    echo ""
    info "Quick start:"
    if [[ -n "${_CAI_RC_FILE:-}" ]]; then
        echo "  1. Open a new terminal (or run: source $_CAI_RC_FILE)"
    else
        echo "  1. Open a new terminal"
    fi
    echo "  2. Navigate to your project: cd /path/to/your/project"
    echo "  3. Start the sandbox: cai"
    echo ""
    info "Other commands:"
    echo "  cai doctor     - Check system capabilities"
    echo "  cai setup      - Install Sysbox (Linux/WSL2)"
    echo "  cai --help     - Show all options"
    echo ""
    info "Documentation: https://github.com/novotnyllc/containai#readme"
}

# ==============================================================================
# Main
# ==============================================================================
main() {
    echo ""
    info "ContainAI Installer"
    info "==================="
    echo ""

    local os
    os="$(detect_os)"
    info "Detected OS: $os"
    echo ""

    check_prerequisites
    echo ""

    install_containai
    echo ""

    setup_path
    echo ""

    post_install
}

# Run main
main "$@"
