#!/usr/bin/env bash
# ==============================================================================
# ContainAI Installer
# ==============================================================================
# One-liner installation:
#   curl -fsSL https://raw.githubusercontent.com/novotnyllc/ContainAI/main/install.sh | bash
#
# This script:
#   1. Detects OS (macOS, Linux)
#   2. Checks prerequisites (Docker, git, bash 4+)
#   3. Clones/updates the repo to ~/.local/share/containai
#   4. Creates symlink in ~/.local/bin/cai
#   5. Adds ~/.local/bin to PATH if needed
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
REPO_URL="https://github.com/novotnyllc/ContainAI.git"
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
                    ubuntu|debian)
                        echo "debian"
                        ;;
                    fedora|rhel|centos|rocky|almalinux)
                        echo "fedora"
                        ;;
                    arch|manjaro)
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
    # Check for bash 4.0+
    local major_version
    major_version="${BASH_VERSION%%.*}"

    if [[ "$major_version" -lt 4 ]]; then
        warn "bash version $BASH_VERSION detected (4.0+ required)"
        local os
        os="$(detect_os)"
        if [[ "$os" == "macos" ]]; then
            error "macOS ships with bash 3.2. Install bash 4+ with: brew install bash"
            error "Then run this script with: /usr/local/bin/bash install.sh"
        else
            error "Please install bash 4.0 or later"
        fi
        return 1
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

    if ! check_bash_version; then
        failed=1
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
        version=$(tr -d '[:space:]' < "$INSTALL_DIR/VERSION")
        info "Installed version: $version"
    fi
}

setup_path() {
    info "Setting up PATH integration..."

    # Create bin directory
    mkdir -p "$BIN_DIR"

    # Create wrapper script instead of symlink (sourced scripts need wrapper)
    local wrapper="$BIN_DIR/cai"
    cat > "$wrapper" << 'WRAPPER_EOF'
#!/usr/bin/env bash
# ContainAI CLI wrapper
# This wrapper sources containai.sh and runs the cai function

# Require bash
if [ -z "${BASH_VERSION:-}" ]; then
    echo "[ERROR] cai requires bash" >&2
    exit 1
fi

# Check bash version
major_version="${BASH_VERSION%%.*}"
if [[ "$major_version" -lt 4 ]]; then
    echo "[ERROR] cai requires bash 4.0 or later (found $BASH_VERSION)" >&2
    if [[ "$(uname -s)" == "Darwin" ]]; then
        echo "  Install with: brew install bash" >&2
        echo "  Then run: /usr/local/bin/bash $(which cai) $*" >&2
    fi
    exit 1
fi

# Determine install directory
CAI_INSTALL_DIR="${CAI_INSTALL_DIR:-$HOME/.local/share/containai}"

# Source the main script
if [[ ! -f "$CAI_INSTALL_DIR/src/containai.sh" ]]; then
    echo "[ERROR] ContainAI not found at $CAI_INSTALL_DIR" >&2
    echo "  Re-run the installer or set CAI_INSTALL_DIR" >&2
    exit 1
fi

# Source in a subshell-like manner to get the functions
source "$CAI_INSTALL_DIR/src/containai.sh"

# Run cai with all arguments
cai "$@"
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

        # Add to PATH in shell rc file (single quotes intentional - we want literal $HOME)
        # shellcheck disable=SC2016
        local path_line='export PATH="$HOME/.local/bin:$PATH"'
        if [[ "$shell_name" == "fish" ]]; then
            # shellcheck disable=SC2016
            path_line='set -gx PATH $HOME/.local/bin $PATH'
        fi

        if [[ -f "$rc_file" ]]; then
            # Check if already present
            if ! grep -q '\.local/bin' "$rc_file" 2>/dev/null; then
                {
                    echo ""
                    echo "# Added by ContainAI installer"
                    echo "$path_line"
                } >> "$rc_file"
                success "Added $BIN_DIR to PATH in $rc_file"
                warn "Run 'source $rc_file' or start a new terminal to use cai"
            else
                info "$rc_file already contains .local/bin PATH entry"
            fi
        else
            # Create the rc file
            {
                echo "# Added by ContainAI installer"
                echo "$path_line"
            } > "$rc_file"
            success "Created $rc_file with PATH entry"
            warn "Run 'source $rc_file' or start a new terminal to use cai"
        fi
    else
        success "$BIN_DIR is already in PATH"
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
    echo "  1. Open a new terminal (or run: source ~/.bashrc)"
    echo "  2. Navigate to your project: cd /path/to/your/project"
    echo "  3. Start the sandbox: cai"
    echo ""
    info "Other commands:"
    echo "  cai doctor     - Check system capabilities"
    echo "  cai setup      - Install Sysbox (Linux/WSL2)"
    echo "  cai --help     - Show all options"
    echo ""
    info "Documentation: https://github.com/novotnyllc/ContainAI#readme"
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
