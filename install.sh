#!/usr/bin/env bash
# ==============================================================================
# ContainAI Installer
# ==============================================================================
# Dual-mode installer: works both as standalone download and from inside tarball.
#
# Path A - Standalone (curl/wget):
#   curl -fsSL https://github.com/novotnyllc/containai/releases/latest/download/install.sh | bash
#
# Path B - From extracted tarball:
#   tar xzf containai-0.2.0-linux-x64.tar.gz
#   cd containai-0.2.0-linux-x64
#   ./install.sh           # Auto-detects local files
#   ./install.sh --local   # Force local install
#
# This script:
#   Local mode (--local or auto-detect):
#     1. Copies files from tarball to ~/.local/share/containai
#     2. Creates wrapper script in ~/.local/bin/cai
#     3. Adds bin directory to PATH if needed
#
#   Standalone mode (no local files):
#     1. Detects OS and architecture
#     2. Downloads tarball from GitHub Releases
#     3. Extracts and runs local install
#
# Flags:
#   --local     Force local install (from extracted tarball)
#   --yes       Auto-confirm all prompts (required for non-interactive install)
#   --no-setup  Skip post-install setup (cai setup/update)
#
# Environment variables:
#   CAI_INSTALL_DIR  - Installation directory (default: ~/.local/share/containai)
#   CAI_BIN_DIR      - Binary directory (default: ~/.local/bin)
#
# Note: Standalone download mode only supports Linux. macOS users should use
# local mode from a manually downloaded tarball, or install via git clone.
#
# ==============================================================================
set -euo pipefail

# ==============================================================================
# Flag Parsing (MUST be at TOP - before any other logic)
# ==============================================================================
YES_FLAG=""
NO_SETUP=""
LOCAL_MODE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --yes) YES_FLAG="1"; shift ;;
        --no-setup) NO_SETUP="true"; shift ;;
        --local) LOCAL_MODE="true"; shift ;;
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
GITHUB_REPO="novotnyllc/containai"
INSTALL_DIR="${CAI_INSTALL_DIR:-$HOME/.local/share/containai}"
BIN_DIR="${CAI_BIN_DIR:-$HOME/.local/bin}"

# Path to bash 4+ (set by bootstrap_bash if needed)
BASH4_PATH=""

# Track install state
IS_FRESH_INSTALL=""
IS_RERUN=""

# Detect script directory (for local mode detection)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ==============================================================================
# Mode Detection
# ==============================================================================
# Check if we're running from an extracted tarball (has containai.sh in same dir)
detect_local_mode() {
    if [[ -f "$SCRIPT_DIR/containai.sh" && -f "$SCRIPT_DIR/lib/core.sh" ]]; then
        return 0  # Local mode
    fi
    return 1  # Standalone mode
}

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

# Detect architecture for downloads (Linux only - macOS not supported for standalone)
detect_arch() {
    local os machine
    os="$(uname -s)"
    machine="$(uname -m)"

    # Only Linux is supported for standalone tarball downloads
    # macOS users should use local mode or git clone
    if [[ "$os" != "Linux" ]]; then
        error "Standalone download only supports Linux."
        error "macOS users: Download tarball manually and run: ./install.sh --local"
        error "Or install from source: git clone https://github.com/$GITHUB_REPO"
        exit 1
    fi

    case "$machine" in
        x86_64|amd64)
            echo "linux-x64"
            ;;
        aarch64|arm64)
            echo "linux-arm64"
            ;;
        *)
            error "Unsupported architecture: $machine"
            exit 1
            ;;
    esac
}

# ==============================================================================
# Bash Bootstrap (macOS)
# ==============================================================================
get_brew_path() {
    if [[ -x "/opt/homebrew/bin/brew" ]]; then
        echo "/opt/homebrew/bin/brew"
    elif [[ -x "/usr/local/bin/brew" ]]; then
        echo "/usr/local/bin/brew"
    else
        echo ""
    fi
}

find_homebrew_bash() {
    local brew_path
    brew_path="$(get_brew_path)"

    if [[ -z "$brew_path" ]]; then
        echo ""
        return
    fi

    local brew_prefix
    brew_prefix="$("$brew_path" --prefix 2>/dev/null)" || {
        echo ""
        return
    }

    local bash_path="${brew_prefix}/bin/bash"
    if [[ -x "$bash_path" ]]; then
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

can_prompt() {
    [[ -t 0 ]]
}

prompt_confirm() {
    local message="$1"
    local default_yes="${2:-false}"

    if [[ -n "$YES_FLAG" ]]; then
        return 0
    fi

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
        return 1
    fi

    response=$(printf '%s' "$response" | tr '[:upper:]' '[:lower:]')

    if [[ "$default_yes" == "true" ]]; then
        case "$response" in
            ""|y|yes) return 0 ;;
            *) return 1 ;;
        esac
    else
        case "$response" in
            y|yes) return 0 ;;
            *) return 1 ;;
        esac
    fi
}

install_homebrew() {
    info "Homebrew is required to install bash 4+ on macOS"

    if [[ -n "$YES_FLAG" ]]; then
        info "Installing Homebrew (--yes mode)..."
    elif can_prompt; then
        if ! prompt_confirm "Install Homebrew?"; then
            return 1
        fi
    else
        warn "Homebrew not found. Install it with:"
        warn '  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
        return 1
    fi

    if [[ -n "$YES_FLAG" ]]; then
        NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    else
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi

    local brew_path
    brew_path="$(get_brew_path)"
    if [[ -z "$brew_path" ]]; then
        error "Homebrew installation failed"
        return 1
    fi

    success "Homebrew installed"
    return 0
}

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
        local brew_prefix
        brew_prefix="$("$brew_path" --prefix 2>/dev/null)" || brew_prefix="/opt/homebrew"
        warn "bash 4+ required. Install it with:"
        warn "  $brew_path install bash"
        warn "Then run cai with: ${brew_prefix}/bin/bash cai"
        return 1
    fi

    "$brew_path" install bash

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

bootstrap_bash_macos() {
    local major_version
    major_version="${BASH_VERSION%%.*}"

    if [[ "$major_version" -ge 4 ]]; then
        BASH4_PATH="$BASH"
        return 0
    fi

    info "macOS ships with bash $BASH_VERSION (cai requires bash 4.0+)"

    local existing_bash
    existing_bash="$(find_homebrew_bash)"
    if [[ -n "$existing_bash" ]]; then
        success "Found Homebrew bash at $existing_bash"
        BASH4_PATH="$existing_bash"
        return 0
    fi

    local brew_path
    brew_path="$(get_brew_path)"

    if [[ -z "$brew_path" ]]; then
        if ! install_homebrew; then
            return 0
        fi
        brew_path="$(get_brew_path)"
    fi

    if ! install_bash_homebrew "$brew_path"; then
        return 0
    fi

    return 0
}

bootstrap_bash() {
    local os
    os="$(detect_os)"

    if [[ "$os" == "macos" ]]; then
        bootstrap_bash_macos
    else
        local major_version
        major_version="${BASH_VERSION%%.*}"
        if [[ "$major_version" -ge 4 ]]; then
            BASH4_PATH="$BASH"
        else
            warn "bash $BASH_VERSION detected, cai requires bash 4.0+"
            warn "Please install bash 4.0 or later"
        fi
    fi
}

# ==============================================================================
# Prerequisite Checks
# ==============================================================================
check_bash_version() {
    local major_version
    major_version="${BASH_VERSION%%.*}"

    if [[ "$major_version" -lt 4 ]]; then
        if [[ -n "$BASH4_PATH" ]]; then
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
        warn "Docker CLI not found"
        warn "ContainAI will install and manage its own isolated Docker during 'cai setup'"
        return 0
    fi

    if ! docker info >/dev/null 2>&1; then
        warn "Docker CLI is installed but the daemon is not running"
        warn "ContainAI will use its own isolated Docker during 'cai setup'"
    fi

    return 0
}

check_prerequisites() {
    info "Checking prerequisites..."
    local failed=0

    check_bash_version

    check_docker
    if command -v docker >/dev/null 2>&1; then
        local docker_version
        docker_version=$(docker --version 2>/dev/null | cut -d' ' -f3 | tr -d ',')
        success "Docker $docker_version"
    else
        info "Docker CLI not installed - will be installed during 'cai setup'"
    fi

    if [[ "$failed" -eq 1 ]]; then
        error "Prerequisites check failed. Please install missing dependencies."
        exit 1
    fi

    success "All prerequisites satisfied"
}

# ==============================================================================
# Download Functions (Standalone Mode)
# ==============================================================================
get_download_url() {
    local arch="$1"

    # Get latest release tag from GitHub API
    local api_url="https://api.github.com/repos/${GITHUB_REPO}/releases/latest"
    local release_info

    if command -v curl >/dev/null 2>&1; then
        release_info=$(curl -fsSL "$api_url" 2>/dev/null) || {
            error "Failed to fetch release information from GitHub"
            return 1
        }
    elif command -v wget >/dev/null 2>&1; then
        release_info=$(wget -qO- "$api_url" 2>/dev/null) || {
            error "Failed to fetch release information from GitHub"
            return 1
        }
    else
        error "Neither curl nor wget found. Please install one of them."
        return 1
    fi

    # Extract tarball download URL for the architecture
    # Look for asset matching containai-*-<arch>.tar.gz
    local tarball_url
    tarball_url=$(printf '%s' "$release_info" | grep -o "\"browser_download_url\":[[:space:]]*\"[^\"]*containai-[^\"]*-${arch}.tar.gz\"" | head -1 | sed 's/.*"\(https[^"]*\)".*/\1/')

    if [[ -z "$tarball_url" ]]; then
        error "Could not find tarball for architecture: $arch"
        return 1
    fi

    printf '%s' "$tarball_url"
}

download_and_extract() {
    local url="$1"

    info "Downloading tarball..."
    info "  URL: $url"

    local temp_dir
    temp_dir="$(mktemp -d)"
    local tarball_path="$temp_dir/containai.tar.gz"

    # Download tarball
    if command -v curl >/dev/null 2>&1; then
        if ! curl -fsSL -o "$tarball_path" "$url"; then
            error "Download failed"
            rm -rf "$temp_dir"
            return 1
        fi
    elif command -v wget >/dev/null 2>&1; then
        if ! wget -q -O "$tarball_path" "$url"; then
            error "Download failed"
            rm -rf "$temp_dir"
            return 1
        fi
    fi

    # Security: Validate tarball contents before extraction
    # Reject absolute paths, path traversal (..), symlinks, hardlinks, and anything not under containai-*/
    info "Validating tarball contents..."

    # Use tar -tvf to get detailed listing including file types
    local tar_verbose
    tar_verbose=$(tar -tvzf "$tarball_path" 2>/dev/null) || {
        error "Failed to list tarball contents"
        rm -rf "$temp_dir"
        return 1
    }

    # Check for malicious entries
    local entry_type entry_path
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        # tar -tv format: permissions links owner/group size date time path
        # First character indicates type: - regular, d directory, l symlink, h hardlink
        entry_type="${line:0:1}"
        # Extract path (last field)
        entry_path="${line##* }"

        # Reject symlinks and hardlinks
        if [[ "$entry_type" == "l" ]]; then
            error "Tarball contains symlink (security risk): $entry_path"
            rm -rf "$temp_dir"
            return 1
        fi
        if [[ "$entry_type" == "h" ]]; then
            error "Tarball contains hardlink (security risk): $entry_path"
            rm -rf "$temp_dir"
            return 1
        fi

        # Reject absolute paths
        if [[ "$entry_path" == /* ]]; then
            error "Tarball contains absolute path: $entry_path"
            rm -rf "$temp_dir"
            return 1
        fi
        # Reject path traversal
        if [[ "$entry_path" == *../* || "$entry_path" == ../* || "$entry_path" == */../* ]]; then
            error "Tarball contains path traversal: $entry_path"
            rm -rf "$temp_dir"
            return 1
        fi
        # Ensure all entries are under containai-*/
        if [[ ! "$entry_path" =~ ^containai-[^/]+(/.*)?$ ]]; then
            error "Tarball contains unexpected entry: $entry_path"
            rm -rf "$temp_dir"
            return 1
        fi
    done <<< "$tar_verbose"

    # Extract tarball (validated safe)
    info "Extracting tarball..."
    if ! tar -xzf "$tarball_path" -C "$temp_dir"; then
        error "Extraction failed"
        rm -rf "$temp_dir"
        return 1
    fi

    # Find extracted directory (containai-VERSION-ARCH)
    local extracted_dir
    extracted_dir=$(find "$temp_dir" -maxdepth 1 -type d -name 'containai-*' | head -1)

    if [[ -z "$extracted_dir" || ! -d "$extracted_dir" ]]; then
        error "Could not find extracted directory"
        rm -rf "$temp_dir"
        return 1
    fi

    # Additional security: verify critical files are regular files, not symlinks
    local install_script="$extracted_dir/install.sh"
    if [[ ! -f "$install_script" ]]; then
        error "install.sh not found in tarball"
        rm -rf "$temp_dir"
        return 1
    fi
    if [[ -L "$install_script" ]]; then
        error "install.sh is a symlink (security risk)"
        rm -rf "$temp_dir"
        return 1
    fi

    # Re-run install.sh from extracted directory in local mode
    info "Running local installer..."

    chmod +x "$install_script"

    # Build arguments to pass to local installer
    local args=("--local")
    [[ -n "$YES_FLAG" ]] && args+=("--yes")
    [[ -n "$NO_SETUP" ]] && args+=("--no-setup")

    # Execute local installer
    (cd "$extracted_dir" && bash ./install.sh "${args[@]}")
    local rc=$?

    # Cleanup
    rm -rf "$temp_dir"

    return $rc
}

# ==============================================================================
# Local Installation (from tarball)
# ==============================================================================
install_from_local() {
    info "Installing ContainAI from local files..."

    # Determine if this is update or fresh install
    if [[ -d "$INSTALL_DIR" && -f "$INSTALL_DIR/containai.sh" ]]; then
        IS_FRESH_INSTALL="false"
        if [[ -f "$BIN_DIR/cai" ]]; then
            IS_RERUN="true"
        fi
        info "Updating existing installation at $INSTALL_DIR"

        # For updates, wipe the runtime directories to remove stale files
        # Keep the install dir itself but remove subdirs we manage
        rm -rf "${INSTALL_DIR:?}/lib" "${INSTALL_DIR:?}/scripts" "${INSTALL_DIR:?}/templates" 2>/dev/null || true
    else
        IS_FRESH_INSTALL="true"
        info "Installing to $INSTALL_DIR"
    fi

    # Create installation directory structure
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$INSTALL_DIR/lib"
    mkdir -p "$INSTALL_DIR/scripts"
    mkdir -p "$INSTALL_DIR/templates"

    # Copy files from tarball to install directory
    info "Copying files..."

    # Main CLI
    cp "$SCRIPT_DIR/containai.sh" "$INSTALL_DIR/containai.sh"
    chmod +x "$INSTALL_DIR/containai.sh"

    # Shell libraries
    cp "$SCRIPT_DIR/lib/"*.sh "$INSTALL_DIR/lib/"

    # Runtime scripts (only parse-manifest.sh)
    cp "$SCRIPT_DIR/scripts/parse-manifest.sh" "$INSTALL_DIR/scripts/"
    chmod +x "$INSTALL_DIR/scripts/parse-manifest.sh"

    # Sync manifest
    cp "$SCRIPT_DIR/sync-manifest.toml" "$INSTALL_DIR/"

    # Templates
    if [[ -d "$SCRIPT_DIR/templates" ]]; then
        cp -r "$SCRIPT_DIR/templates/"* "$INSTALL_DIR/templates/" 2>/dev/null || true
    fi

    # ACP proxy binary
    if [[ -f "$SCRIPT_DIR/acp-proxy" ]]; then
        cp "$SCRIPT_DIR/acp-proxy" "$INSTALL_DIR/acp-proxy"
        chmod +x "$INSTALL_DIR/acp-proxy"
    fi

    # Version file
    if [[ -f "$SCRIPT_DIR/VERSION" ]]; then
        cp "$SCRIPT_DIR/VERSION" "$INSTALL_DIR/VERSION"
    fi

    # LICENSE
    if [[ -f "$SCRIPT_DIR/LICENSE" ]]; then
        cp "$SCRIPT_DIR/LICENSE" "$INSTALL_DIR/LICENSE"
    fi

    success "Files installed to $INSTALL_DIR"

    # Show version
    if [[ -f "$INSTALL_DIR/VERSION" ]]; then
        local version
        version=$(tr -d '[:space:]' <"$INSTALL_DIR/VERSION")
        info "Installed version: $version"
    fi
}

# ==============================================================================
# PATH Setup
# ==============================================================================
setup_path() {
    info "Setting up PATH integration..."

    mkdir -p "$BIN_DIR"

    local wrapper="$BIN_DIR/cai"

    # Part 1: Script header and bash version check
    cat >"$wrapper" <<'WRAPPER_PART1'
#!/usr/bin/env bash
# ContainAI CLI wrapper
# Generated by install.sh - install directory baked in at install time

if [ -z "${BASH_VERSION:-}" ]; then
    echo "[ERROR] cai requires bash" >&2
    exit 1
fi

major_version="${BASH_VERSION%%.*}"
if [[ "$major_version" -lt 4 ]]; then
    if [[ "$(uname -s)" == "Darwin" ]]; then
        if [[ -z "${_CAI_REEXEC:-}" ]]; then
            for brew_bash in /opt/homebrew/bin/bash /usr/local/bin/bash; do
                if [[ -x "$brew_bash" ]]; then
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

_CAI_DEFAULT_INSTALL_DIR="__CAI_ESCAPED_INSTALL_DIR__"
CAI_INSTALL_DIR="${CAI_INSTALL_DIR:-$_CAI_DEFAULT_INSTALL_DIR}"
WRAPPER_PART1

    # Part 2: Replace placeholder with install directory
    local escaped_dir
    escaped_dir="$INSTALL_DIR"
    escaped_dir="${escaped_dir//\\/\\\\}"
    escaped_dir="${escaped_dir//\"/\\\"}"
    escaped_dir="${escaped_dir//\`/\\\`}"
    escaped_dir="${escaped_dir//\$/\\\$}"

    local tmp_wrapper
    tmp_wrapper=$(mktemp)
    sed "s|__CAI_ESCAPED_INSTALL_DIR__|$escaped_dir|g" "$wrapper" > "$tmp_wrapper"
    mv "$tmp_wrapper" "$wrapper"

    # Part 3: Rest of the script
    cat >>"$wrapper" <<'WRAPPER_PART2'

if [[ ! -f "$CAI_INSTALL_DIR/containai.sh" ]]; then
    echo "[ERROR] ContainAI not found at $CAI_INSTALL_DIR" >&2
    echo "  Re-run the installer or set CAI_INSTALL_DIR" >&2
    exit 1
fi

source "$CAI_INSTALL_DIR/containai.sh"
cai "$@"
WRAPPER_PART2

    chmod +x "$wrapper"
    success "Created cai wrapper at $wrapper"

    # Check PATH and update shell config
    if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
        warn "$BIN_DIR is not in your PATH"

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

        mkdir -p "$(dirname "$rc_file")"

        local path_line
        if [[ "$shell_name" == "fish" ]]; then
            path_line="set -gx PATH $BIN_DIR \$PATH"
        else
            path_line="export PATH=\"$BIN_DIR:\$PATH\""
        fi

        if [[ -f "$rc_file" ]]; then
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
            {
                echo "# Added by ContainAI installer"
                echo "$path_line"
            } >"$rc_file"
            success "Created $rc_file with PATH entry"
            warn "Run 'source $rc_file' or start a new terminal to use cai"
        fi

        _CAI_RC_FILE="$rc_file"
    else
        success "$BIN_DIR is already in PATH"
        _CAI_RC_FILE=""
    fi
}

# ==============================================================================
# Post-installation
# ==============================================================================
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
                echo "  - Other distros: manual setup required (see docs)"
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

run_auto_setup() {
    local cai_yes_value="$1"

    echo ""
    info "Running initial setup..."
    echo ""

    local bash_cmd
    if [[ -n "$BASH4_PATH" ]]; then
        bash_cmd="$BASH4_PATH"
    else
        bash_cmd="bash"
    fi

    local cai_wrapper="$BIN_DIR/cai"
    if [[ -x "$cai_wrapper" ]]; then
        local rc=0
        if [[ "$cai_yes_value" == "1" ]]; then
            CAI_YES=1 "$bash_cmd" "$cai_wrapper" setup || rc=$?
        else
            "$bash_cmd" "$cai_wrapper" setup || rc=$?
        fi
        if [[ $rc -eq 0 ]]; then
            success "Setup completed successfully!"
        elif [[ $rc -eq 75 ]]; then
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

run_auto_update() {
    local cai_yes_value="$1"

    echo ""
    info "Updating existing installation..."
    echo ""

    local bash_cmd
    if [[ -n "$BASH4_PATH" ]]; then
        bash_cmd="$BASH4_PATH"
    else
        bash_cmd="bash"
    fi

    local cai_wrapper="$BIN_DIR/cai"
    if [[ -f "$cai_wrapper" ]]; then
        local rc=0
        if [[ "$cai_yes_value" == "1" ]]; then
            CAI_YES=1 "$bash_cmd" "$cai_wrapper" update || rc=$?
        else
            "$bash_cmd" "$cai_wrapper" update || rc=$?
        fi
        if [[ $rc -eq 0 ]]; then
            success "Update completed successfully!"
        elif [[ $rc -eq 75 ]]; then
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

    if [[ "$NO_SETUP" == "true" ]]; then
        info "Skipping automatic configuration (--no-setup flag)"
        if [[ "$IS_RERUN" == "true" ]]; then
            show_setup_instructions "update"
        else
            show_setup_instructions
        fi
        return
    fi

    local bash_cmd bash_major
    if [[ -n "$BASH4_PATH" ]]; then
        bash_cmd="$BASH4_PATH"
    else
        bash_cmd="bash"
    fi
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

    local cai_yes_value=""

    if [[ "$IS_RERUN" == "true" ]]; then
        if [[ -n "$YES_FLAG" ]]; then
            cai_yes_value="1"
            run_auto_update "$cai_yes_value"
        elif can_prompt; then
            echo ""
            if prompt_confirm "Would you like to run 'cai update' now to update your environment?" "true"; then
                cai_yes_value="1"
                run_auto_update "$cai_yes_value"
            else
                info "Skipping update."
                show_setup_instructions "update"
            fi
        else
            info "Non-interactive install detected. Skipping automatic update."
            info "To auto-run update, use: curl ... | bash -s -- --yes"
            show_setup_instructions "update"
        fi
    else
        if [[ -n "$YES_FLAG" ]]; then
            cai_yes_value="1"
            run_auto_setup "$cai_yes_value"
        elif can_prompt; then
            echo ""
            if prompt_confirm "Would you like to run 'cai setup' now to configure your environment?" "true"; then
                cai_yes_value="1"
                run_auto_setup "$cai_yes_value"
            else
                info "Skipping setup."
                show_setup_instructions
            fi
        else
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

    # Determine mode: local (from tarball) or standalone (download)
    local use_local_mode="false"

    if [[ "$LOCAL_MODE" == "true" ]]; then
        # Explicit --local flag
        use_local_mode="true"
        info "Mode: Local install (--local flag)"
    elif detect_local_mode; then
        # Auto-detected local files
        use_local_mode="true"
        info "Mode: Local install (tarball detected)"
    else
        info "Mode: Standalone install (will download)"
    fi
    echo ""

    # Bootstrap bash 4+ on macOS
    bootstrap_bash
    echo ""

    # Check prerequisites
    check_prerequisites
    echo ""

    if [[ "$use_local_mode" == "true" ]]; then
        # Local mode: install from tarball files
        install_from_local
        echo ""
        setup_path
        echo ""
        post_install
    else
        # Standalone mode: download tarball and run local installer
        local arch
        arch="$(detect_arch)"
        info "Detected architecture: $arch"

        local download_url
        if ! download_url="$(get_download_url "$arch")"; then
            exit 1
        fi

        download_and_extract "$download_url"
        # Note: download_and_extract runs the local installer which handles
        # setup_path and post_install
    fi
}

# Run main
main "$@"
