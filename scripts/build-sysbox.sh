#!/usr/bin/env bash
# ==============================================================================
# ContainAI Sysbox Build Script
# ==============================================================================
# Builds sysbox-ce deb packages from the master branch, which includes the
# openat2 fix for runc 1.3.3+ compatibility (commit 1302a6f in sysbox-fs).
#
# This script is designed to be run locally or in GitHub Actions to produce
# custom sysbox builds with the fix that hasn't been released upstream yet.
#
# Usage:
#   ./scripts/build-sysbox.sh [OPTIONS]
#
# Options:
#   --arch ARCH       Target architecture: amd64 or arm64 (default: host arch)
#   --output DIR      Output directory for deb and checksums (default: ./dist)
#   --version-suffix  Custom suffix (default: +containai.YYYYMMDD)
#   --dry-run         Show commands without executing
#   --verbose         Enable verbose output
#   --help            Show this help message
#
# Requirements:
#   - Docker (with privileged mode support)
#   - git
#   - At least 10GB free disk space
#   - Kernel headers (for native builds)
#
# Output:
#   - sysbox-ce_<version><suffix>.linux_<arch>.deb
#   - sysbox-ce_<version><suffix>.linux_<arch>.deb.sha256
#
# The version is taken from sysbox's VERSION file, with the suffix appended
# to indicate this is a custom ContainAI build from master.
#
# Example:
#   ./scripts/build-sysbox.sh --arch amd64 --output ./dist
#   # Produces: dist/sysbox-ce_0.6.7+containai.20260126.linux_amd64.deb
#
# ==============================================================================

set -euo pipefail

# Script directory for relative paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Defaults
ARCH=""
OUTPUT_DIR="$PROJECT_ROOT/dist"
VERSION_SUFFIX=""
DRY_RUN="false"
VERBOSE="false"

# Sysbox repository
SYSBOX_REPO="https://github.com/nestybox/sysbox.git"
SYSBOX_BRANCH="master"

# Logging functions - all output goes to stderr to avoid polluting stdout
# (stdout is reserved for function return values via printf)
log_info() {
    printf '[INFO] %s\n' "$*" >&2
}

log_step() {
    printf '\n[STEP] %s\n' "$*" >&2
}

log_ok() {
    printf '[OK] %s\n' "$*" >&2
}

log_warn() {
    printf '[WARN] %s\n' "$*" >&2
}

log_error() {
    printf '[ERROR] %s\n' "$*" >&2
}

# Show usage
show_help() {
    sed -n '/^# Usage:/,/^# ==/p' "$0" | grep -v '^# ==' | sed 's/^# \?//'
    exit 0
}

# Parse arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --arch)
                if [[ $# -lt 2 ]] || [[ "$2" == --* ]]; then
                    log_error "--arch requires a value (amd64 or arm64)"
                    exit 1
                fi
                ARCH="$2"
                shift 2
                ;;
            --output)
                if [[ $# -lt 2 ]] || [[ "$2" == --* ]]; then
                    log_error "--output requires a directory path"
                    exit 1
                fi
                OUTPUT_DIR="$2"
                shift 2
                ;;
            --version-suffix)
                if [[ $# -lt 2 ]] || [[ "$2" == --* ]]; then
                    log_error "--version-suffix requires a value"
                    exit 1
                fi
                VERSION_SUFFIX="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN="true"
                shift
                ;;
            --verbose)
                VERBOSE="true"
                shift
                ;;
            --help|-h)
                show_help
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                ;;
        esac
    done

    # Determine host architecture
    local host_arch
    host_arch=$(uname -m)
    local host_arch_normalized
    case "$host_arch" in
        x86_64)
            host_arch_normalized="amd64"
            ;;
        aarch64)
            host_arch_normalized="arm64"
            ;;
        *)
            log_error "Unsupported host architecture: $host_arch"
            exit 1
            ;;
    esac

    # Determine target architecture if not specified
    if [[ -z "$ARCH" ]]; then
        ARCH="$host_arch_normalized"
        log_info "Auto-detected architecture: $ARCH"
    fi

    # Validate architecture
    case "$ARCH" in
        amd64|arm64) ;;
        *)
            log_error "Unsupported architecture: $ARCH (must be amd64 or arm64)"
            exit 1
            ;;
    esac

    # Warn if target architecture differs from host (requires QEMU)
    if [[ "$ARCH" != "$host_arch_normalized" ]]; then
        log_warn "Cross-compilation requested: building $ARCH on $host_arch_normalized host"
        log_warn "This requires QEMU to be configured for Docker"
        log_warn "The sysbox-pkgr build will use TARGET_ARCH=$ARCH"
    fi

    # Set default version suffix with current date
    if [[ -z "$VERSION_SUFFIX" ]]; then
        VERSION_SUFFIX="+containai.$(date +%Y%m%d)"
    fi
}

# Check prerequisites
check_prerequisites() {
    log_step "Checking prerequisites"

    local missing=()

    # Git is always required (even for dry-run to show realistic output)
    if ! command -v git >/dev/null 2>&1; then
        missing+=("git")
    fi

    # Docker checks are skipped in dry-run mode
    if [[ "$DRY_RUN" == "true" ]]; then
        if ! command -v docker >/dev/null 2>&1; then
            log_info "[DRY-RUN] Docker not found (would be required for actual build)"
        fi
        if [[ ${#missing[@]} -gt 0 ]]; then
            log_error "Missing required tools: ${missing[*]}"
            exit 1
        fi
        log_ok "Prerequisites satisfied (dry-run mode)"
        return 0
    fi

    # For actual builds, Docker is required
    if ! command -v docker >/dev/null 2>&1; then
        missing+=("docker")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing[*]}"
        exit 1
    fi

    # Check Docker is running
    if ! docker info >/dev/null 2>&1; then
        log_error "Docker is not running or not accessible"
        exit 1
    fi

    # Check for privileged mode support (needed for sysbox build)
    if ! docker run --rm --privileged alpine:latest true 2>/dev/null; then
        log_error "Docker privileged mode is not available (required for sysbox build)"
        exit 1
    fi

    log_ok "Prerequisites satisfied"
}

# Clone sysbox repository
clone_sysbox() {
    log_step "Cloning sysbox repository (branch: $SYSBOX_BRANCH)"

    local build_dir="$PROJECT_ROOT/.build-sysbox"
    local sysbox_dir="$build_dir/sysbox"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would clone $SYSBOX_REPO to $sysbox_dir"
        log_info "[DRY-RUN] Would checkout branch: $SYSBOX_BRANCH"
        log_info "[DRY-RUN] Would update submodules recursively"
        return 0
    fi

    # Clean previous build directory if it exists
    if [[ -d "$build_dir" ]]; then
        log_info "Removing previous build directory"
        rm -rf "$build_dir"
    fi

    mkdir -p "$build_dir"

    # Clone with submodules
    log_info "Cloning sysbox repository..."
    if ! git clone --recursive --depth 1 --branch "$SYSBOX_BRANCH" "$SYSBOX_REPO" "$sysbox_dir"; then
        log_error "Failed to clone sysbox repository"
        exit 1
    fi

    # Verify the openat2 fix is present in sysbox-fs (this is the whole point of this build)
    log_info "Verifying openat2 fix is present..."
    local sysbox_fs_dir="$sysbox_dir/sysbox-fs"
    local fix_commit="1302a6f"
    local fix_verified="false"

    # Try to verify via commit ancestry (most reliable)
    # Need to fetch more history since we cloned with --depth 1
    if git -C "$sysbox_fs_dir" fetch --unshallow 2>/dev/null || \
       git -C "$sysbox_fs_dir" fetch --depth=100 origin master 2>/dev/null; then
        true  # fetched more history
    fi

    if git -C "$sysbox_fs_dir" merge-base --is-ancestor "$fix_commit" HEAD 2>/dev/null; then
        log_ok "openat2 fix verified: commit $fix_commit is ancestor of HEAD"
        fix_verified="true"
    fi

    # Fallback: check for the specific handler file that implements the fix
    if [[ "$fix_verified" != "true" ]] && [[ -f "$sysbox_fs_dir/handler/implementations/openat2.go" ]]; then
        log_ok "openat2 fix verified: handler/implementations/openat2.go exists"
        fix_verified="true"
    fi

    if [[ "$fix_verified" != "true" ]]; then
        log_error "openat2 fix NOT found in sysbox-fs"
        log_error "Could not verify commit $fix_commit ancestry or find openat2.go handler"
        log_error "The whole purpose of this build is to include the openat2 fix for runc 1.3.3+"
        exit 1
    fi

    # Get version from VERSION file
    local version
    version=$(tr -d '[:space:]' < "$sysbox_dir/VERSION")
    log_info "Sysbox version: $version"

    # Export for later use
    printf '%s' "$sysbox_dir"
}

# Build sysbox deb package
build_sysbox_deb() {
    local sysbox_dir="$1"
    local version
    local full_version

    log_step "Building sysbox-ce deb package"
    log_info "Architecture: $ARCH"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Version: <from sysbox VERSION file>${VERSION_SUFFIX}"
        log_info "[DRY-RUN] Would build sysbox-ce deb package"
        log_info "[DRY-RUN] Would run: make -C sysbox-pkgr sysbox-ce-deb generic"
        return 0
    fi

    version=$(tr -d '[:space:]' < "$sysbox_dir/VERSION")
    full_version="${version}${VERSION_SUFFIX}"
    log_info "Version: $full_version"

    local pkgr_dir="$sysbox_dir/sysbox-pkgr"

    # Verify sysbox-pkgr exists
    if [[ ! -d "$pkgr_dir" ]]; then
        log_error "sysbox-pkgr directory not found at $pkgr_dir"
        exit 1
    fi

    # Set up environment for the build
    export EDITION=ce
    # Set target architecture for the build (supports cross-compilation with QEMU)
    export TARGET_ARCH="$ARCH"

    # The sysbox-pkgr needs sources/sysbox to point to the sysbox repo
    # Since we're building from within the repo, we need to set up the symlink
    log_info "Setting up sysbox-pkgr sources..."
    mkdir -p "$pkgr_dir/sources"
    ln -sfn "$sysbox_dir" "$pkgr_dir/sources/sysbox"

    # Patch control files to add fuse3 dependency (sysbox-fs requires fusermount3)
    # Use find to locate all control files in the deb directory (handles various template layouts)
    log_info "Patching control files to add fuse3 dependency..."
    local patched_count=0
    local control_files
    control_files=$(find "$pkgr_dir/deb" -name control -type f 2>/dev/null)

    if [[ -z "$control_files" ]]; then
        log_error "No control files found in $pkgr_dir/deb"
        exit 1
    fi

    local f
    for f in $control_files; do
        # Skip if fuse3 already present in Depends line (idempotent)
        if grep -qE '^Depends:.*\bfuse3\b' "$f"; then
            log_info "fuse3 already present in $f"
            continue
        fi

        # Add fuse3 to the beginning of the Depends line
        if grep -q '^Depends:' "$f"; then
            sed -i 's/^Depends:/Depends: fuse3,/' "$f"
            # Verify the patch worked
            if grep -qE '^Depends:[[:space:]]*fuse3\b' "$f"; then
                log_ok "fuse3 dependency added to $f"
                patched_count=$((patched_count + 1))
            else
                log_error "Failed to patch $f"
                exit 1
            fi
        fi
    done

    if [[ "$patched_count" -eq 0 ]]; then
        log_error "No control files were patched - fuse3 dependency not added"
        exit 1
    fi
    log_info "Patched $patched_count control file(s)"

    # Patch the VERSION file to include our suffix
    log_info "Patching version to: $full_version"
    printf '%s' "$full_version" > "$sysbox_dir/VERSION"

    # Build the generic deb package (ubuntu-jammy based, works across distros)
    log_info "Building deb package for $ARCH (this may take 10-20 minutes)..."
    cd -- "$pkgr_dir"

    # Run the build with proper environment
    # The build uses Docker internally; TARGET_ARCH enables cross-compilation
    if ! make -C deb generic EDITION=ce TARGET_ARCH="$ARCH"; then
        log_error "Failed to build sysbox-ce deb package"
        exit 1
    fi

    # Find the built package
    local deb_path
    deb_path=$(find "$pkgr_dir/deb/build" -name "sysbox-ce*.deb" -type f | head -1)

    if [[ -z "$deb_path" ]] || [[ ! -f "$deb_path" ]]; then
        log_error "Built deb package not found"
        log_info "Searched in: $pkgr_dir/deb/build"
        exit 1
    fi

    log_ok "Built package: $deb_path"

    # Export the path for later use
    printf '%s' "$deb_path"
}

# Copy artifacts and generate checksums
finalize_artifacts() {
    local deb_path="$1"
    local version
    local sysbox_dir="$PROJECT_ROOT/.build-sysbox/sysbox"

    if [[ -f "$sysbox_dir/VERSION" ]]; then
        version=$(tr -d '[:space:]' < "$sysbox_dir/VERSION")
    else
        version="unknown"
    fi

    log_step "Finalizing artifacts"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would create output directory: $OUTPUT_DIR"
        log_info "[DRY-RUN] Would copy deb package to output"
        log_info "[DRY-RUN] Would generate SHA256 checksum"
        return 0
    fi

    # Create output directory
    mkdir -p "$OUTPUT_DIR"

    # Determine final filename
    local final_name="sysbox-ce_${version}.linux_${ARCH}.deb"
    local final_path="$OUTPUT_DIR/$final_name"

    # Copy the deb package
    log_info "Copying package to: $final_path"
    cp -- "$deb_path" "$final_path"

    # Generate SHA256 checksum
    log_info "Generating SHA256 checksum..."
    cd -- "$OUTPUT_DIR"
    sha256sum "$final_name" > "${final_name}.sha256"

    log_ok "Artifacts created in: $OUTPUT_DIR"
    log_info "  - $final_name"
    log_info "  - ${final_name}.sha256"

    # Print checksum
    log_info "SHA256: $(cat "${final_name}.sha256")"
}

# Cleanup build directory
cleanup() {
    local build_dir="$PROJECT_ROOT/.build-sysbox"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would clean up build directory: $build_dir"
        return 0
    fi

    if [[ -d "$build_dir" ]]; then
        log_info "Cleaning up build directory..."
        rm -rf "$build_dir"
    fi
}

# Main entry point
main() {
    parse_args "$@"

    log_info "ContainAI Sysbox Build"
    log_info "======================"
    log_info "Architecture: $ARCH"
    log_info "Output: $OUTPUT_DIR"
    log_info "Version suffix: $VERSION_SUFFIX"
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Mode: DRY-RUN"
    fi

    check_prerequisites

    # Clone and build
    local sysbox_dir
    sysbox_dir=$(clone_sysbox)

    if [[ "$DRY_RUN" != "true" ]]; then
        local deb_path
        deb_path=$(build_sysbox_deb "$sysbox_dir")
        finalize_artifacts "$deb_path"
    else
        build_sysbox_deb "$PROJECT_ROOT/.build-sysbox/sysbox"
        finalize_artifacts ""
    fi

    # Cleanup is optional - uncomment to auto-clean after build
    # cleanup

    log_step "Build complete"
    log_ok "Sysbox deb package built successfully"

    if [[ "$DRY_RUN" != "true" ]]; then
        log_info ""
        log_info "To install the package:"
        log_info "  sudo dpkg -i $OUTPUT_DIR/sysbox-ce_*.deb"
        log_info "  sudo apt-get install -f  # if there are dependency issues"
    fi
}

main "$@"
