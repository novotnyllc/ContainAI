#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Build ContainAI CLI tarballs for container installation
# ==============================================================================
# Usage: ./src/scripts/build-cai-tarballs.sh [options]
#   --platforms PLATFORMS   Target platforms (default: linux/<host-arch>)
#                           e.g., linux/amd64,linux/arm64
#   --version VERSION       Version string (default: NBGV_SemVer2 or "unknown")
#   --output-dir DIR        Output directory (default: artifacts/cai-tarballs)
#   --help                  Show this help
#
# Output files (in output dir):
#   containai-<version>-linux-x64.tar.gz
#   containai-<version>-linux-arm64.tar.gz
#   containai-<version>-macos-x64.tar.gz
#   containai-<version>-macos-arm64.tar.gz
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

require_bash_4() {
    if [[ -z "${BASH_VERSINFO:-}" ]] || ((BASH_VERSINFO[0] < 4)); then
        local current_version="${BASH_VERSION:-unknown}"
        printf 'ERROR: %s requires bash 4.0+ (detected: %s)\n' "$0" "$current_version" >&2
        if [[ "$(uname -s)" == "Darwin" ]]; then
            printf 'Install bash with: %s\n' "$REPO_ROOT/scripts/install-build-dependencies.sh" >&2
            if command -v brew >/dev/null 2>&1; then
                local brew_prefix
                brew_prefix="$(brew --prefix 2>/dev/null || true)"
                if [[ -n "$brew_prefix" ]]; then
                    printf 'Then run with: %s %s\n' "$brew_prefix/bin/bash" "$0" >&2
                fi
            fi
        fi
        exit 2
    fi
}

require_bash_4

PLATFORMS=""
BUILD_VERSION=""
OUTPUT_DIR="$REPO_ROOT/artifacts/cai-tarballs"

detect_host_arch() {
    local arch
    arch="$(uname -m)"
    case "$arch" in
        x86_64|amd64)
            printf '%s' "amd64"
            ;;
        aarch64|arm64)
            printf '%s' "arm64"
            ;;
        *)
            printf 'ERROR: Unsupported host architecture: %s\n' "$arch" >&2
            return 1
            ;;
    esac
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --platforms|--platform)
            if [[ -z "${2-}" ]]; then
                printf 'ERROR: --platforms requires a value\n' >&2
                exit 1
            fi
            PLATFORMS="$2"
            shift 2
            ;;
        --platforms=*|--platform=*)
            PLATFORMS="${1#*=}"
            if [[ -z "$PLATFORMS" ]]; then
                printf 'ERROR: --platforms requires a value\n' >&2
                exit 1
            fi
            shift
            ;;
        --version)
            if [[ -z "${2-}" ]]; then
                printf 'ERROR: --version requires a value\n' >&2
                exit 1
            fi
            BUILD_VERSION="$2"
            shift 2
            ;;
        --version=*)
            BUILD_VERSION="${1#*=}"
            if [[ -z "$BUILD_VERSION" ]]; then
                printf 'ERROR: --version requires a value\n' >&2
                exit 1
            fi
            shift
            ;;
        --output-dir)
            if [[ -z "${2-}" ]]; then
                printf 'ERROR: --output-dir requires a value\n' >&2
                exit 1
            fi
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --output-dir=*)
            OUTPUT_DIR="${1#*=}"
            if [[ -z "$OUTPUT_DIR" ]]; then
                printf 'ERROR: --output-dir requires a value\n' >&2
                exit 1
            fi
            shift
            ;;
        --help|-h)
            sed -n '2,/^# ==/p' "$0" | grep '^#' | sed 's/^# //' | sed 's/^#//'
            exit 0
            ;;
        *)
            printf 'ERROR: Unknown option: %s\n' "$1" >&2
            exit 1
            ;;
    esac
done

if [[ -z "$PLATFORMS" ]]; then
    PLATFORMS="linux/$(detect_host_arch)"
fi

# Determine version for tarballs
if [[ -z "$BUILD_VERSION" ]]; then
    if [[ -n "${NBGV_SemVer2:-}" ]]; then
        BUILD_VERSION="$NBGV_SemVer2"
    elif command -v dotnet >/dev/null 2>&1 && [[ -f "$REPO_ROOT/version.json" ]]; then
        BUILD_VERSION="$(dotnet nbgv get-version -v SemVer2 2>/dev/null || echo 'unknown')"
    else
        BUILD_VERSION="unknown"
    fi
fi

if ! command -v dotnet >/dev/null 2>&1; then
    printf 'ERROR: dotnet is required to build cai tarballs\n' >&2
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

PLATFORMS="${PLATFORMS//[[:space:]]/}"
IFS=',' read -ra platform_list <<< "$PLATFORMS"

declare -A seen=()

printf 'Building ContainAI CLI tarballs (version: %s)\n' "$BUILD_VERSION"

host_arch="$(detect_host_arch)"
for platform in "${platform_list[@]}"; do
    case "$platform" in
        linux/amd64|macos/amd64)
            platform_arch="amd64"
            ;;
        linux/arm64|macos/arm64)
            platform_arch="arm64"
            ;;
        *)
            continue
            ;;
    esac

    if [[ "$platform_arch" != "$host_arch" ]]; then
        printf 'ERROR: Cross-arch tarball build is not supported (host: %s, requested: %s)\n' "$host_arch" "$platform" >&2
        printf 'Build tarballs on native runners and place them in: %s\n' "$OUTPUT_DIR" >&2
        exit 1
    fi
done

for platform in "${platform_list[@]}"; do
    local_rid=""
    local_arch=""

    case "$platform" in
        linux/amd64)
            local_rid="linux-x64"
            local_arch="linux-x64"
            ;;
        linux/arm64)
            local_rid="linux-arm64"
            local_arch="linux-arm64"
            ;;
        macos/amd64)
            local_rid="osx-x64"
            local_arch="macos-x64"
            ;;
        macos/arm64)
            local_rid="osx-arm64"
            local_arch="macos-arm64"
            ;;
        *)
            printf 'ERROR: Unsupported platform for cai tarball: %s\n' "$platform" >&2
            exit 1
            ;;
    esac

    if [[ -n "${seen[$local_arch]:-}" ]]; then
        continue
    fi
    seen["$local_arch"]=1

    printf '  Building acp-proxy (%s)...\n' "$local_rid"
    dotnet publish "$REPO_ROOT/src/acp-proxy" \
        -r "$local_rid" \
        -c Release \
        --self-contained \
        -p:Version="$BUILD_VERSION"

    printf '  Packaging tarball (%s)...\n' "$local_arch"
    "$REPO_ROOT/scripts/package-release.sh" \
        --arch "$local_arch" \
        --version "$BUILD_VERSION" \
        --output-dir "$OUTPUT_DIR"

    src_tarball="$OUTPUT_DIR/containai-${BUILD_VERSION}-${local_arch}.tar.gz"
    if [[ ! -f "$src_tarball" ]]; then
        printf 'ERROR: Expected tarball not found: %s\n' "$src_tarball" >&2
        exit 1
    fi
    printf '  Wrote: %s\n' "$src_tarball"
done

printf 'Tarball build complete.\n'
