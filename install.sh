#!/usr/bin/env bash
set -euo pipefail

GITHUB_REPO="novotnyllc/containai"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -t 1 ]]; then
    BLUE='\033[0;34m'
    YELLOW='\033[0;33m'
    RED='\033[0;31m'
    NC='\033[0m'
else
    BLUE=''
    YELLOW=''
    RED=''
    NC=''
fi

info() { printf '%b[INFO]%b %s\n' "$BLUE" "$NC" "$1"; }
warn() { printf '%b[WARN]%b %s\n' "$YELLOW" "$NC" "$1" >&2; }
error() { printf '%b[ERROR]%b %s\n' "$RED" "$NC" "$1" >&2; }

usage() {
    cat <<'USAGE'
ContainAI installer bootstrap

Usage:
  ./install.sh [install-options]

This script only bootstraps a cai binary, then delegates to:
  cai install [install-options]

Common install options:
  --local
  --yes
  --no-setup
  --install-dir <path>
  --bin-dir <path>
  --channel <stable|nightly>
  --verbose
USAGE
}

parse_local_flag() {
    local arg
    for arg in "$@"; do
        case "$arg" in
            --help|-h)
                usage
                exit 0
                ;;
            --local)
                return 0
                ;;
        esac
    done

    return 1
}

resolve_local_mode() {
    if [[ -x "$SCRIPT_DIR/cai" ]]; then
        printf '%s' "binary"
        return 0
    fi

    if [[ -f "$SCRIPT_DIR/src/cai/cai.csproj" ]]; then
        printf '%s' "source"
        return 0
    fi

    return 1
}

detect_arch() {
    local os machine
    os="$(uname -s)"
    machine="$(uname -m)"

    if [[ "$os" != "Linux" ]]; then
        error "Standalone download only supports Linux."
        error "Use a local payload (./cai) and run ./install.sh --local on macOS."
        return 1
    fi

    case "$machine" in
        x86_64|amd64)
            printf '%s' "linux-x64"
            ;;
        aarch64|arm64)
            printf '%s' "linux-arm64"
            ;;
        *)
            error "Unsupported architecture: $machine"
            return 1
            ;;
    esac
}

get_download_url() {
    local arch="$1"
    local api_url="https://api.github.com/repos/${GITHUB_REPO}/releases/latest"
    local release_info tarball_url

    if command -v curl >/dev/null 2>&1; then
        release_info="$(curl -fsSL "$api_url")" || {
            error "Failed to fetch release metadata from GitHub"
            return 1
        }
    elif command -v wget >/dev/null 2>&1; then
        release_info="$(wget -qO- "$api_url")" || {
            error "Failed to fetch release metadata from GitHub"
            return 1
        }
    else
        error "Neither curl nor wget is available"
        return 1
    fi

    tarball_url="$(printf '%s' "$release_info" | grep -o '"browser_download_url":[[:space:]]*"[^"]*containai-[^"]*-'"$arch"'\.tar\.gz"' | head -n 1 | sed 's/.*"\(https[^\"]*\)".*/\1/')"
    if [[ -z "$tarball_url" ]]; then
        error "Could not find release tarball for architecture: $arch"
        return 1
    fi

    printf '%s' "$tarball_url"
}

run_local_install() {
    local mode="$1"
    shift

    case "$mode" in
        binary)
            info "Using local cai payload at $SCRIPT_DIR/cai"
            exec "$SCRIPT_DIR/cai" install --local "$@"
            ;;
        source)
            if ! command -v dotnet >/dev/null 2>&1; then
                error "dotnet SDK is required for source-checkout bootstrap mode"
                return 1
            fi

            info "Using source checkout via dotnet run"
            exec dotnet run --project "$SCRIPT_DIR/src/cai/cai.csproj" -- install --local "$@"
            ;;
        *)
            error "Unknown local mode: $mode"
            return 1
            ;;
    esac
}

download_and_run_install() {
    local url="$1"
    shift

    local temp_dir
    temp_dir="$(mktemp -d)"
    trap 'rm -rf "$temp_dir"' EXIT

    local tarball_path="$temp_dir/containai.tar.gz"
    info "Downloading release payload"
    info "URL: $url"

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$tarball_path" "$url"
    else
        wget -q -O "$tarball_path" "$url"
    fi

    tar -xzf "$tarball_path" -C "$temp_dir"

    local extracted_dir
    extracted_dir="$(find "$temp_dir" -maxdepth 1 -type d -name 'containai-*' | head -n 1)"
    if [[ -z "$extracted_dir" ]]; then
        error "Failed to locate extracted release directory"
        return 1
    fi

    local cai_binary="$extracted_dir/cai"
    if [[ ! -x "$cai_binary" ]]; then
        error "Extracted payload does not include an executable cai binary"
        return 1
    fi

    info "Delegating installation to extracted cai binary"
    exec "$cai_binary" install --local "$@"
}

main() {
    local local_only="false"
    if parse_local_flag "$@"; then
        local_only="true"
    fi

    local local_mode=""
    if local_mode="$(resolve_local_mode)"; then
        run_local_install "$local_mode" "$@"
    fi

    if [[ "$local_only" == "true" ]]; then
        error "--local was specified but no local payload was found next to install.sh"
        error "Expected either ./cai or ./src/cai/cai.csproj"
        return 1
    fi

    local arch download_url
    arch="$(detect_arch)" || return 1
    info "Detected architecture: $arch"

    download_url="$(get_download_url "$arch")" || return 1
    download_and_run_install "$download_url" "$@"
}

main "$@"
