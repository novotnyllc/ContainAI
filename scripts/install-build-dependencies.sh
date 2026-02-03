#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Install build-time dependencies for ContainAI
# ==============================================================================
# Usage: ./scripts/install-build-dependencies.sh [options]
#   --yes, -y   Install without prompting (CI friendly)
#   --help      Show this help
#
# Installs (best-effort):
#   - bash 4.0+ (required for build scripts)
#   - git
#   - docker CLI (required for image builds)
#   - dotnet SDK (version from global.json)
#   - tar, gzip (packaging)
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ASSUME_YES="false"

usage() {
    sed -n '2,/^# ==/p' "$0" | sed 's/^# //' | sed 's/^#//'
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --yes|-y)
            ASSUME_YES="true"
            shift
            ;;
        --help|-h)
            usage
            ;;
        *)
            printf 'ERROR: Unknown option: %s\n' "$1" >&2
            exit 1
            ;;
    esac
done

confirm_install() {
    if [[ "$ASSUME_YES" == "true" ]]; then
        return 0
    fi
    local reply=""
    printf 'Install missing build dependencies? [y/N] '
    if [[ -t 0 ]]; then
        read -r reply
    else
        read -r reply </dev/tty || reply=""
    fi
    case "$reply" in
        y|Y|yes|YES) return 0 ;;
        *) return 1 ;;
    esac
}

require_sudo() {
    if [[ "$(id -u)" -eq 0 ]]; then
        return 0
    fi
    if ! command -v sudo >/dev/null 2>&1; then
        printf 'ERROR: sudo is required to install packages\n' >&2
        return 1
    fi
    return 0
}

read_dotnet_version() {
    local version=""
    if [[ -f "$REPO_ROOT/global.json" ]]; then
        version="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$REPO_ROOT/global.json" | head -1)"
    fi
    if [[ -z "$version" ]]; then
        version="latest"
    fi
    printf '%s' "$version"
}

dotnet_major_version() {
    if ! command -v dotnet >/dev/null 2>&1; then
        return 1
    fi
    dotnet --version 2>/dev/null | cut -d. -f1
}

detect_bash_major() {
    if ! command -v bash >/dev/null 2>&1; then
        return 1
    fi
    bash -c 'printf "%s" "${BASH_VERSINFO[0]}"' 2>/dev/null
}

install_dotnet_sdk() {
    local version="$1"
    local install_dir="$HOME/.dotnet"
    local script_file
    script_file="$(mktemp)"

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL https://dot.net/v1/dotnet-install.sh -o "$script_file"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$script_file" https://dot.net/v1/dotnet-install.sh
    else
        printf 'ERROR: curl or wget is required to install dotnet\n' >&2
        rm -f "$script_file"
        return 1
    fi

    if [[ "$version" == "latest" ]]; then
        bash "$script_file" --install-dir "$install_dir"
    else
        bash "$script_file" --version "$version" --install-dir "$install_dir"
    fi
    rm -f "$script_file"

    export DOTNET_ROOT="$install_dir"
    export PATH="$install_dir:$PATH"
    return 0
}

OS_NAME="$(uname -s)"

DOTNET_VERSION="$(read_dotnet_version)"
DOTNET_MAJOR="${DOTNET_VERSION%%.*}"

NEED_DOTNET="false"
if ! command -v dotnet >/dev/null 2>&1; then
    NEED_DOTNET="true"
else
    INSTALLED_DOTNET_MAJOR="$(dotnet_major_version || printf '')"
    if [[ -n "$DOTNET_MAJOR" ]] && [[ -n "$INSTALLED_DOTNET_MAJOR" ]] && [[ "$DOTNET_MAJOR" != "$INSTALLED_DOTNET_MAJOR" ]]; then
        NEED_DOTNET="true"
    fi
fi

BASH_MAJOR="$(detect_bash_major || printf '')"
NEED_BASH="false"
if [[ -z "$BASH_MAJOR" ]] || [[ "$BASH_MAJOR" -lt 4 ]]; then
    NEED_BASH="true"
fi

case "$OS_NAME" in
    Darwin)
        if ! command -v brew >/dev/null 2>&1; then
            printf 'ERROR: Homebrew is required on macOS to install build dependencies.\n' >&2
            printf 'Install Homebrew: https://brew.sh\n' >&2
            exit 1
        fi

        brew_prefix="$(brew --prefix)"
        export PATH="$brew_prefix/bin:$PATH"

        brew_pkgs=()
        if [[ "$NEED_BASH" == "true" ]]; then
            brew_pkgs+=(bash)
        fi
        if ! command -v git >/dev/null 2>&1; then
            brew_pkgs+=(git)
        fi
        if ! command -v docker >/dev/null 2>&1; then
            brew_pkgs+=(docker)
        fi

        if ((${#brew_pkgs[@]} > 0)); then
            printf 'Missing Homebrew packages: %s\n' "${brew_pkgs[*]}"
            if ! confirm_install; then
                printf 'Aborted.\n' >&2
                exit 1
            fi
            brew install "${brew_pkgs[@]}"
        fi

        if [[ "$NEED_DOTNET" == "true" ]]; then
            printf 'Installing dotnet SDK %s...\n' "$DOTNET_VERSION"
            if ! confirm_install; then
                printf 'Aborted.\n' >&2
                exit 1
            fi
            install_dotnet_sdk "$DOTNET_VERSION"
        fi

        if [[ "$NEED_BASH" == "true" ]]; then
            printf 'NOTE: Use Homebrew bash for build scripts: %s/bin/bash\n' "$brew_prefix"
        fi

        if ! command -v docker >/dev/null 2>&1; then
            printf 'NOTE: Docker Desktop is required for local image builds on macOS.\n'
        fi
        ;;
    Linux)
        if ! command -v apt-get >/dev/null 2>&1; then
            printf 'ERROR: Only apt-get based distributions are supported by this script.\n' >&2
            exit 1
        fi

        apt_pkgs=()
        if [[ "$NEED_BASH" == "true" ]]; then
            apt_pkgs+=(bash)
        fi
        if ! command -v git >/dev/null 2>&1; then
            apt_pkgs+=(git)
        fi
        if ! command -v tar >/dev/null 2>&1; then
            apt_pkgs+=(tar)
        fi
        if ! command -v gzip >/dev/null 2>&1; then
            apt_pkgs+=(gzip)
        fi
        if ! command -v docker >/dev/null 2>&1; then
            apt_pkgs+=(docker.io)
        fi
        if [[ "$NEED_DOTNET" == "true" ]]; then
            if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
                apt_pkgs+=(curl)
            fi
        fi

        if ((${#apt_pkgs[@]} > 0)); then
            printf 'Missing APT packages: %s\n' "${apt_pkgs[*]}"
            if ! confirm_install; then
                printf 'Aborted.\n' >&2
                exit 1
            fi
            require_sudo
            if [[ "$ASSUME_YES" == "true" ]]; then
                sudo apt-get update -qq
                sudo apt-get install -y "${apt_pkgs[@]}"
            else
                sudo apt-get update -qq
                sudo apt-get install "${apt_pkgs[@]}"
            fi
        fi

        if [[ "$NEED_DOTNET" == "true" ]]; then
            printf 'Installing dotnet SDK %s...\n' "$DOTNET_VERSION"
            if ! confirm_install; then
                printf 'Aborted.\n' >&2
                exit 1
            fi
            install_dotnet_sdk "$DOTNET_VERSION"
        fi
        ;;
    *)
        printf 'ERROR: Unsupported OS: %s\n' "$OS_NAME" >&2
        exit 1
        ;;
esac

printf 'Build dependencies are installed or already present.\n'
