#!/usr/bin/env bash
# ==============================================================================
# ContainAI Installer
# ==============================================================================
# One-liner installation:
#   curl -fsSL https://raw.githubusercontent.com/novotnyllc/containai/main/install.sh | bash
#
# With auto-confirmation (no prompts):
#   curl -fsSL https://raw.githubusercontent.com/novotnyllc/containai/main/install.sh | bash -s -- --yes
#
# This script:
#   1. Detects OS (macOS, Linux)
#   2. On macOS: bootstraps bash 4+ via Homebrew if needed
#   3. Checks prerequisites (Docker, git)
#   4. Clones/updates the repo to ~/.local/share/containai
#   5. Creates wrapper script in ~/.local/bin/cai
#   6. Adds bin directory to PATH if needed
#
# Note: The installer runs on bash 3.2+, but the cai CLI requires bash 4.0+.
# On macOS, the installer can auto-install bash 4+ via Homebrew.
#
# Flags:
#   --yes       Auto-confirm all prompts (required for non-interactive install)
#   --no-setup  Skip post-install setup (cai setup/update)
#
# Environment variables:
#   CAI_INSTALL_DIR  - Installation directory (default: ~/.local/share/containai)
#   CAI_BIN_DIR      - Binary directory (default: ~/.local/bin)
#   CAI_BRANCH       - Git branch to install (default: main)
#
# ==============================================================================
set -euo pipefail

# ==============================================================================
# Flag Parsing (MUST be at TOP - before bash bootstrap)
# These variables are used by this task AND fn-16-4c9.3/4
# ==============================================================================
YES_FLAG=""
NO_SETUP=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --yes) YES_FLAG="1"; shift ;;
        --no-setup) NO_SETUP="true"; shift ;;
        *) shift ;;
    esac
done

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

# Path to bash 4+ (set by bootstrap_bash if needed)
BASH4_PATH=""

# Track if this is a fresh install or update (set by install_containai)
IS_FRESH_INSTALL=""

# Track if this is a proper re-run (.git exists AND cai wrapper exists)
# Used to decide whether to run update vs setup in post_install
IS_RERUN=""

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
# Bash Bootstrap (macOS)
# ==============================================================================
# Detect Homebrew installation path (Apple Silicon vs Intel)
get_brew_path() {
    # Check Apple Silicon location first
    if [[ -x "/opt/homebrew/bin/brew" ]]; then
        echo "/opt/homebrew/bin/brew"
    # Then Intel location
    elif [[ -x "/usr/local/bin/brew" ]]; then
        echo "/usr/local/bin/brew"
    else
        echo ""
    fi
}

# Check for existing Homebrew bash
find_homebrew_bash() {
    local brew_path
    brew_path="$(get_brew_path)"

    if [[ -z "$brew_path" ]]; then
        echo ""
        return
    fi

    # Get Homebrew prefix directly
    local brew_prefix
    brew_prefix="$("$brew_path" --prefix 2>/dev/null)" || {
        echo ""
        return
    }

    local bash_path="${brew_prefix}/bin/bash"
    if [[ -x "$bash_path" ]]; then
        # Verify it's bash 4+
        local version
        version="$("$bash_path" -c 'echo "${BASH_VERSION%%.*}"' 2>/dev/null)" || {
            echo ""
            return
        }
        if [[ "$version" -ge 4 ]]; then
            echo "$bash_path"
            return
        fi
    fi
    echo ""
}

# Check if stdin is interactive (can prompt user)
# For piped installs (stdin not a TTY), we NEVER prompt - this is per spec
can_prompt() {
    # Only allow prompting if stdin is a TTY
    # Do NOT use /dev/tty fallback - piped installs must not prompt
    [[ -t 0 ]]
}

# Prompt for confirmation (respects YES_FLAG)
# Arguments: $1 = message
#            $2 = default_yes ("true" for default Y, otherwise default N)
prompt_confirm() {
    local message="$1"
    local default_yes="${2:-false}"

    # Auto-confirm if --yes flag
    if [[ -n "$YES_FLAG" ]]; then
        return 0
    fi

    # Can't prompt in non-interactive mode without --yes
    if ! can_prompt; then
        return 1
    fi

    local prompt_suffix response
    if [[ "$default_yes" == "true" ]]; then
        prompt_suffix="[Y/n]"
    else
        prompt_suffix="[y/N]"
    fi

    printf '%s %s: ' "$message" "$prompt_suffix"
    if ! read -r response; then
        # EOF (Ctrl-D) - treat as decline/cancel
        return 1
    fi

    # Normalize: lowercase for consistent matching (bash 3.2 compatible)
    response=$(printf '%s' "$response" | tr '[:upper:]' '[:lower:]')

    # Evaluate response based on default
    # Only accept explicit y/yes/n/no/empty - reject ambiguous input like "maybe"
    if [[ "$default_yes" == "true" ]]; then
        # Default Y: empty/y/yes confirms, n/no denies, other input denies (safe default)
        case "$response" in
            ""|y|yes) return 0 ;;
            n|no)     return 1 ;;
            *)        return 1 ;;  # Ambiguous input defaults to deny for safety
        esac
    else
        # Default N: y/yes confirms, empty/n/no/other denies
        case "$response" in
            y|yes) return 0 ;;
            *)     return 1 ;;
        esac
    fi
}

# Install Homebrew (macOS only)
install_homebrew() {
    info "Homebrew is required to install bash 4+ on macOS"

    if [[ -n "$YES_FLAG" ]]; then
        info "Installing Homebrew (--yes mode)..."
    elif can_prompt; then
        if ! prompt_confirm "Install Homebrew?"; then
            return 1
        fi
    else
        # Non-interactive without --yes: show instructions only
        warn "Homebrew not found. Install it with:"
        warn '  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
        return 1
    fi

    # Install Homebrew
    # NONINTERACTIVE=1 prevents prompts (Homebrew's official non-interactive mode)
    if [[ -n "$YES_FLAG" ]]; then
        NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    else
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi

    # Verify installation
    local brew_path
    brew_path="$(get_brew_path)"
    if [[ -z "$brew_path" ]]; then
        error "Homebrew installation failed"
        return 1
    fi

    success "Homebrew installed"
    return 0
}

# Install bash via Homebrew (macOS only)
install_bash_homebrew() {
    local brew_path="$1"

    info "bash 4+ is required for the cai CLI"

    if [[ -n "$YES_FLAG" ]]; then
        info "Installing bash via Homebrew (--yes mode)..."
    elif can_prompt; then
        if ! prompt_confirm "Install bash 4+ via Homebrew?"; then
            return 1
        fi
    else
        # Non-interactive without --yes: show instructions only
        local brew_prefix
        brew_prefix="$("$brew_path" --prefix 2>/dev/null)" || brew_prefix="/opt/homebrew"
        warn "bash 4+ required. Install it with:"
        warn "  $brew_path install bash"
        warn "Then run cai with: ${brew_prefix}/bin/bash cai"
        return 1
    fi

    # Install bash
    "$brew_path" install bash

    # Verify installation
    local bash_path
    bash_path="$(find_homebrew_bash)"
    if [[ -z "$bash_path" ]]; then
        error "bash installation failed"
        return 1
    fi

    success "bash 4+ installed at $bash_path"
    BASH4_PATH="$bash_path"
    return 0
}

# Bootstrap bash 4+ on macOS
# Sets BASH4_PATH if bash 4+ is available/installed
bootstrap_bash_macos() {
    local major_version
    major_version="${BASH_VERSION%%.*}"

    # Already running bash 4+, no bootstrap needed
    if [[ "$major_version" -ge 4 ]]; then
        BASH4_PATH="$BASH"
        return 0
    fi

    info "macOS ships with bash $BASH_VERSION (cai requires bash 4.0+)"

    # Check for existing Homebrew bash first
    local existing_bash
    existing_bash="$(find_homebrew_bash)"
    if [[ -n "$existing_bash" ]]; then
        success "Found Homebrew bash at $existing_bash"
        BASH4_PATH="$existing_bash"
        return 0
    fi

    # Check for Homebrew
    local brew_path
    brew_path="$(get_brew_path)"

    if [[ -z "$brew_path" ]]; then
        # Need to install Homebrew first
        if ! install_homebrew; then
            # Couldn't install Homebrew, BASH4_PATH remains empty
            return 0
        fi
        brew_path="$(get_brew_path)"
    fi

    # Install bash via Homebrew
    if ! install_bash_homebrew "$brew_path"; then
        # Couldn't install bash, BASH4_PATH remains empty
        return 0
    fi

    return 0
}

# Main bash bootstrap function
# Called early in install.sh, BEFORE creating the cai wrapper
bootstrap_bash() {
    local os
    os="$(detect_os)"

    if [[ "$os" == "macos" ]]; then
        bootstrap_bash_macos
    else
        # Linux typically has bash 4+ in standard packages
        local major_version
        major_version="${BASH_VERSION%%.*}"
        if [[ "$major_version" -ge 4 ]]; then
            BASH4_PATH="$BASH"
        else
            warn "bash $BASH_VERSION detected, cai requires bash 4.0+"
            warn "Please install bash 4.0 or later"
            # Continue without BASH4_PATH - wrapper will handle it
        fi
    fi
}

# ==============================================================================
# Prerequisite Checks
# ==============================================================================
check_bash_version() {
    # Check for bash 4.0+ (required by cai CLI, not installer)
    # This is now just a status display, bootstrap_bash handles installation
    local major_version
    major_version="${BASH_VERSION%%.*}"

    if [[ "$major_version" -lt 4 ]]; then
        if [[ -n "$BASH4_PATH" ]]; then
            # bash 4+ was installed/found during bootstrap
            local bash4_version
            bash4_version="$("$BASH4_PATH" -c 'echo "$BASH_VERSION"' 2>/dev/null)" || bash4_version="4.x"
            success "bash $bash4_version (Homebrew)"
        else
            warn "bash ${BASH_VERSION} (4.0+ needed for cai CLI)"
        fi
    else
        success "bash ${BASH_VERSION}"
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

    # bash check (warn only, don't fail) - check_bash_version handles its own output
    check_bash_version

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

    # Validate branch name (reject empty or option-like values)
    if [[ -z "$BRANCH" ]] || [[ "$BRANCH" == -* ]]; then
        error "Invalid branch name: '$BRANCH'"
        return 1
    fi

    if [[ -d "$INSTALL_DIR/.git" ]]; then
        # Existing installation - update
        IS_FRESH_INSTALL="false"
        # Check if cai wrapper also exists (proper re-run vs corrupted state)
        # Use -f (file exists) not -x (executable) since wrapper is invoked via bash
        if [[ -f "$BIN_DIR/cai" ]]; then
            IS_RERUN="true"
        fi
        info "Existing installation found, updating..."
        (
            cd -- "$INSTALL_DIR"
            # Use refspec to avoid branch name being parsed as option
            git fetch origin "refs/heads/$BRANCH:refs/remotes/origin/$BRANCH"
            # Use -B to create/reset local branch tracking remote (handles missing local branch)
            git checkout -B "$BRANCH" "origin/$BRANCH"
        )
        success "Updated to latest version"
    else
        # Fresh installation
        IS_FRESH_INSTALL="true"
        if [[ -d "$INSTALL_DIR" ]]; then
            warn "Directory exists but is not a git repository: $INSTALL_DIR"
            warn "Removing and re-cloning..."
            rm -rf "$INSTALL_DIR"
        fi
        # Clone with explicit refspec to avoid branch name being parsed as option
        git clone --branch "$BRANCH" --depth 1 -- "$REPO_URL" "$INSTALL_DIR"
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

    # Write wrapper in two parts:
    # 1. First part: single-quoted heredoc (no expansion)
    # 2. Install dir: written separately with proper escaping
    # 3. Second part: rest of the script

    # Part 1: Script header and bash version check (quoted heredoc - no expansion)
    cat >"$wrapper" <<'WRAPPER_PART1'
#!/usr/bin/env bash
# ContainAI CLI wrapper
# This wrapper sources containai.sh and runs the cai function
# Generated by install.sh - install directory baked in at install time

# Require bash
if [ -z "${BASH_VERSION:-}" ]; then
    echo "[ERROR] cai requires bash" >&2
    exit 1
fi

# Check bash version - re-exec with Homebrew bash on macOS if needed
major_version="${BASH_VERSION%%.*}"
if [[ "$major_version" -lt 4 ]]; then
    # On macOS, try to re-exec with Homebrew bash
    if [[ "$(uname -s)" == "Darwin" ]]; then
        # Prevent infinite re-exec loop
        if [[ -z "${_CAI_REEXEC:-}" ]]; then
            # Check for Homebrew bash (Apple Silicon then Intel)
            for brew_bash in /opt/homebrew/bin/bash /usr/local/bin/bash; do
                if [[ -x "$brew_bash" ]]; then
                    # Verify it's bash 4+
                    brew_major="$("$brew_bash" -c 'echo "${BASH_VERSION%%.*}"' 2>/dev/null)" || continue
                    if [[ "$brew_major" -ge 4 ]]; then
                        export _CAI_REEXEC=1
                        exec "$brew_bash" "$0" "$@"
                    fi
                fi
            done
        fi
        echo "[ERROR] cai requires bash 4.0 or later (found $BASH_VERSION)" >&2
        echo "  Install with: brew install bash" >&2
        exit 1
    else
        echo "[ERROR] cai requires bash 4.0 or later (found $BASH_VERSION)" >&2
        echo "  Please install bash 4.0 or later" >&2
        exit 1
    fi
fi

# Default install directory (baked in at install time)
# __CAI_ESCAPED_INSTALL_DIR__ is replaced during installation
_CAI_DEFAULT_INSTALL_DIR="__CAI_ESCAPED_INSTALL_DIR__"

# Allow override via environment variable
CAI_INSTALL_DIR="${CAI_INSTALL_DIR:-$_CAI_DEFAULT_INSTALL_DIR}"
WRAPPER_PART1

    # Part 2: Replace placeholder with properly escaped install directory
    # Escape for double-quoted context: \, ", `, $
    local escaped_dir
    escaped_dir="$INSTALL_DIR"
    escaped_dir="${escaped_dir//\\/\\\\}"  # \ -> \\
    escaped_dir="${escaped_dir//\"/\\\"}"  # " -> \"
    escaped_dir="${escaped_dir//\`/\\\`}"  # ` -> \`
    escaped_dir="${escaped_dir//\$/\\\$}"  # $ -> \$

    # Use a unique delimiter that won't appear in typical paths
    # Write to temp file and mv to avoid BSD/GNU sed -i incompatibility
    local tmp_wrapper
    tmp_wrapper=$(mktemp)
    sed "s|__CAI_ESCAPED_INSTALL_DIR__|$escaped_dir|g" "$wrapper" > "$tmp_wrapper"
    mv "$tmp_wrapper" "$wrapper"

    # Part 3: Rest of the script (quoted heredoc - no expansion)
    cat >>"$wrapper" <<'WRAPPER_PART2'

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
WRAPPER_PART2

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

# Show manual setup instructions (when auto-setup is skipped)
# Arguments: $1 = "update" for update-specific instructions, otherwise setup
show_setup_instructions() {
    local mode="${1:-setup}"
    local os
    os="$(detect_os)"

    echo ""
    info "Quick start:"
    if [[ -n "${_CAI_RC_FILE:-}" ]]; then
        echo "  1. Open a new terminal (or run: source $_CAI_RC_FILE)"
    else
        echo "  1. Open a new terminal"
    fi
    if [[ "$mode" == "update" ]]; then
        echo "  2. Run: cai update"
    else
        echo "  2. Run: cai setup"
    fi
    echo "  3. Navigate to your project: cd /path/to/your/project"
    echo "  4. Start the sandbox: cai"
    echo ""

    # Platform-specific setup information
    if [[ "$mode" != "update" ]]; then
        info "What 'cai setup' does:"
        case "$os" in
            macos)
                echo "  - Creates a lightweight Linux VM using Lima"
                echo "  - Installs Docker Engine and Sysbox inside the VM"
                echo "  - Configures secure container isolation"
                ;;
            debian)
                echo "  - Installs Sysbox for secure container isolation"
                echo "  - Creates an isolated Docker daemon (containai-docker)"
                echo "  - Does NOT modify your system Docker"
                ;;
            *)
                echo "  - Configures secure container isolation"
                echo "  - Ubuntu/Debian: auto-installs Sysbox"
                echo "  - Other distros: requires manual Sysbox install"
                ;;
        esac
        echo ""
    fi

    info "Other commands:"
    echo "  cai doctor     - Check system capabilities"
    echo "  cai --help     - Show all options"
    echo ""
    info "Documentation: https://github.com/novotnyllc/containai#readme"
}

# Run cai setup automatically
# Arguments: $1 = CAI_YES_VALUE (1 for auto-confirm, empty otherwise)
run_auto_setup() {
    local cai_yes_value="$1"

    echo ""
    info "Running initial setup..."
    echo ""

    # Determine bash path to use
    local bash_cmd
    if [[ -n "$BASH4_PATH" ]]; then
        bash_cmd="$BASH4_PATH"
    else
        bash_cmd="bash"
    fi

    # Run cai setup with CAI_YES if auto-confirm is enabled
    # Use explicit path to cai wrapper we just created
    local cai_wrapper="$BIN_DIR/cai"
    if [[ -x "$cai_wrapper" ]]; then
        # Capture exit code without triggering set -e
        # cai setup may return non-zero for expected reasons (e.g., 75 = WSL restart)
        local rc=0
        if [[ "$cai_yes_value" == "1" ]]; then
            CAI_YES=1 "$bash_cmd" "$cai_wrapper" setup || rc=$?
        else
            "$bash_cmd" "$cai_wrapper" setup || rc=$?
        fi
        if [[ $rc -eq 0 ]]; then
            success "Setup completed successfully!"
        elif [[ $rc -eq 75 ]]; then
            # Special exit code: WSL restart required
            info "Please restart your terminal and run 'cai setup' again."
        else
            warn "Setup had some issues (exit code: $rc)"
            warn "You can re-run 'cai setup' later to complete configuration."
        fi
    else
        warn "Could not find cai wrapper at $cai_wrapper"
        show_setup_instructions
    fi
}

# Run cai update automatically (for re-runs)
# Arguments: $1 = CAI_YES_VALUE (1 for auto-confirm, empty otherwise)
run_auto_update() {
    local cai_yes_value="$1"

    echo ""
    info "Updating existing installation..."
    echo ""

    # Determine bash path to use
    local bash_cmd
    if [[ -n "$BASH4_PATH" ]]; then
        bash_cmd="$BASH4_PATH"
    else
        bash_cmd="bash"
    fi

    # Run cai update with CAI_YES if auto-confirm is enabled
    # Use explicit path to cai wrapper
    local cai_wrapper="$BIN_DIR/cai"
    # Use -f (file exists) not -x (executable) since wrapper is invoked via bash
    if [[ -f "$cai_wrapper" ]]; then
        # Capture exit code without triggering set -e
        # cai update may return non-zero for expected reasons
        local rc=0
        if [[ "$cai_yes_value" == "1" ]]; then
            CAI_YES=1 "$bash_cmd" "$cai_wrapper" update || rc=$?
        else
            "$bash_cmd" "$cai_wrapper" update || rc=$?
        fi
        if [[ $rc -eq 0 ]]; then
            success "Update completed successfully!"
        elif [[ $rc -eq 75 ]]; then
            # Special exit code: WSL restart required
            info "Please restart your terminal and run 'cai update' again."
        else
            warn "Update had some issues (exit code: $rc)"
            warn "You can re-run 'cai update' later to complete configuration."
        fi
    else
        warn "Could not find cai wrapper at $cai_wrapper"
        show_setup_instructions "update"
    fi
}

post_install() {
    echo ""
    if [[ "$IS_FRESH_INSTALL" == "true" ]]; then
        success "ContainAI installed successfully!"
    else
        success "ContainAI updated successfully!"
    fi

    # Determine whether to auto-run setup/update
    # Skip if --no-setup was passed
    if [[ "$NO_SETUP" == "true" ]]; then
        info "Skipping automatic configuration (--no-setup flag)"
        if [[ "$IS_RERUN" == "true" ]]; then
            show_setup_instructions "update"
        else
            show_setup_instructions
        fi
        return
    fi

    # Require bash 4+ to run setup/update (cai CLI needs it)
    # Check the bash_cmd we'll use for auto-setup/update
    local bash_cmd bash_major
    if [[ -n "$BASH4_PATH" ]]; then
        bash_cmd="$BASH4_PATH"
    else
        bash_cmd="bash"
    fi
    # Verify bash 4+ is available
    bash_major=$("$bash_cmd" -c 'echo "${BASH_VERSION%%.*}"' 2>/dev/null) || bash_major=0
    if [[ "$bash_major" -lt 4 ]]; then
        local os
        os="$(detect_os)"
        warn "Cannot run setup: bash 4+ is required but not installed."
        if [[ "$os" == "macos" ]]; then
            warn "Install bash via Homebrew: brew install bash"
        else
            warn "Please install bash 4.0 or later"
        fi
        if [[ "$IS_RERUN" == "true" ]]; then
            warn "Then run: cai update"
            show_setup_instructions "update"
        else
            warn "Then run: cai setup"
            show_setup_instructions
        fi
        return
    fi

    # Determine CAI_YES_VALUE for auto-confirm
    # Set CAI_YES=1 when EITHER --yes flag is passed OR user confirms interactively
    # This auto-confirms downstream prompts in cai setup/update
    local cai_yes_value=""

    # Determine which action to run: setup (fresh) or update (re-run)
    if [[ "$IS_RERUN" == "true" ]]; then
        # Re-run: call cai update instead of setup
        if [[ -n "$YES_FLAG" ]]; then
            # --yes flag passed: auto-confirm everything including downstream prompts
            cai_yes_value="1"
            run_auto_update "$cai_yes_value"
        elif can_prompt; then
            # Interactive mode: prompt user (default Y for updates)
            echo ""
            if prompt_confirm "Would you like to run 'cai update' now to update your environment?" "true"; then
                # User confirmed interactively: auto-confirm downstream prompts too
                cai_yes_value="1"
                run_auto_update "$cai_yes_value"
            else
                info "Skipping update."
                show_setup_instructions "update"
            fi
        else
            # Non-interactive without --yes: show instructions only
            info "Non-interactive install detected. Skipping automatic update."
            info "To auto-run update, use: curl ... | bash -s -- --yes"
            show_setup_instructions "update"
        fi
    else
        # Fresh install: call cai setup
        if [[ -n "$YES_FLAG" ]]; then
            # --yes flag passed: auto-confirm everything including downstream prompts
            cai_yes_value="1"
            run_auto_setup "$cai_yes_value"
        elif can_prompt; then
            # Interactive mode: prompt user (default Y for first-time install)
            echo ""
            if prompt_confirm "Would you like to run 'cai setup' now to configure your environment?" "true"; then
                # User confirmed interactively: auto-confirm downstream prompts too
                cai_yes_value="1"
                run_auto_setup "$cai_yes_value"
            else
                info "Skipping setup."
                show_setup_instructions
            fi
        else
            # Non-interactive without --yes: show instructions only
            info "Non-interactive install detected. Skipping automatic setup."
            info "To auto-run setup, use: curl ... | bash -s -- --yes"
            show_setup_instructions
        fi
    fi
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

    # Bootstrap bash 4+ on macOS BEFORE creating wrapper
    # This sets BASH4_PATH if bash 4+ is available/installed
    bootstrap_bash
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
